#!/usr/bin/env python3
"""Create one free personal identity. No trust-root installation or TCC changes."""
import argparse
import hashlib
import json
import os
import secrets
import subprocess
import tempfile
import re
import shlex
import base64
import uuid
from pathlib import Path
from local_signing import CONFIG, ROOT, load_profile, requirement


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def setup(config, keychain=None):
    if config.exists():
        profile = load_profile(config)
        # No regeneration when a previously configured keychain/key is missing.
        verify(profile)
        print('Existing personal identity is available; nothing regenerated.')
        return
    if keychain is None:
        paths = shlex.split(run(['security', 'default-keychain', '-d', 'user']).stdout.decode())
        if len(paths) != 1: raise ValueError('Cannot identify the user signing keychain')
        keychain = Path(paths[0])
    keychain = keychain.resolve(strict=True)
    existing = run(['security', 'find-identity', '-p', 'codesigning', str(keychain)]).stdout.decode()
    matches = set(re.findall(r'\b([A-Fa-f0-9]{40}) "Veylume Personal Development"', existing))
    if len(matches) > 1: raise ValueError('Multiple personal identities exist. Choose the original explicitly; no new identity created.')
    found = subprocess.run(['security', 'find-certificate', '-a', '-c', 'Veylume Personal Development', '-p', str(keychain)], capture_output=True)
    certificates = []
    if found.returncode == 0:
        for encoded in re.findall(rb'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', found.stdout, re.S):
            certificates.append(base64.b64decode(encoded))
    if certificates:
        if len(matches) != 1: raise ValueError('A personal certificate already exists without its usable private key. Restore that key instead of generating another identity.')
        fingerprint = next(iter(matches)).upper()
        der = next((x for x in certificates if hashlib.sha1(x).hexdigest().upper() == fingerprint), None)
        if der is None: raise ValueError('Personal certificate and private identity do not match')
        profile = dict(version=1, identitySHA1=fingerprint, certificateSHA256=hashlib.sha256(der).hexdigest(), keychain=str(keychain), kind='personal-self-signed-not-notarized')
        verify(profile); save_profile(config, profile)
        print('Original personal identity reused; nothing regenerated.')
        return
    with tempfile.TemporaryDirectory(prefix='Veylume-signing-') as directory:
        temporary = Path(directory)
        os.chmod(temporary, 0o700)
        password = secrets.token_hex(32)
        password_file = temporary / 'passphrase'
        password_file.write_text(password + '\n')
        password_file.chmod(0o600)
        export_password_file = temporary / 'export-passphrase'
        export_password_file.write_text(password + '\n')
        export_password_file.chmod(0o600)
        openssl_config = temporary / 'openssl.cnf'
        openssl_config.write_text('''[req]
distinguished_name=dn
x509_extensions=signing
prompt=no
[dn]
CN=Veylume Personal Development
[signing]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
''')
        private_key, certificate, pkcs12 = (temporary / x for x in ['key.pem', 'certificate.pem', 'identity.p12'])
        # The temporary private key and PKCS#12 are encrypted; credentials are
        # read from a private file or stdin, never command-line values or logs.
        run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:3072', '-days', '3650',
             '-config', str(openssl_config), '-passout', 'file:' + str(password_file),
             '-keyout', str(private_key), '-out', str(certificate)])
        private_key.chmod(0o600)
        run(['openssl', 'pkcs12', '-export', '-legacy', '-inkey', str(private_key), '-in', str(certificate),
             '-name', 'Veylume Personal Development', '-passin', 'file:' + str(password_file),
             '-passout', 'file:' + str(export_password_file), '-out', str(pkcs12)])
        pkcs12.chmod(0o600)
        der = run(['openssl', 'x509', '-in', str(certificate), '-outform', 'DER']).stdout
        fingerprint = hashlib.sha1(der).hexdigest().upper()
        helper = temporary / 'import-identity'
        run(['xcrun', 'swiftc', str(ROOT / 'scripts/import-local-signing.swift'), '-o', str(helper)])
        payload = {'pkcs12': str(pkcs12), 'passphrase': password}
        payload['keychain'] = str(keychain)
        imported = run([str(helper)], input=json.dumps(payload).encode())
        profile = {'version': 1, 'identitySHA1': fingerprint, 'certificateSHA256': hashlib.sha256(der).hexdigest(),
                   'keychain': json.loads(imported.stdout)['keychain'], 'kind': 'personal-self-signed-not-notarized'}
        # Persist the pin immediately after import, even if a later verification
        # fails. Re-running must never create a replacement identity silently.
        save_profile(config, profile)
    verify(profile)
    print('Personal identity created and pinned. No trusted root or privacy permissions changed.')


def save_profile(config, profile):
    config.parent.mkdir(parents=True, exist_ok=True)
    with config.open('x') as stream: json.dump(profile, stream, indent=2); stream.write('\n')
    config.chmod(0o600)


def adopt_existing(config, fingerprint, keychain=None):
    """Explicitly select an existing identity, including Apple Development.

    Certificate issuance/account sign-in remain in Xcode. This command never
    generates a replacement for an existing private key or changes trust.
    """
    if not re.fullmatch(r'[A-Fa-f0-9]{40}', fingerprint):
        raise ValueError('Use the exact 40-character SHA-1 of an existing code-signing identity')
    fingerprint = fingerprint.upper()
    if keychain is None:
        paths = shlex.split(run(['security', 'default-keychain', '-d', 'user']).stdout.decode())
        if len(paths) != 1: raise ValueError('Cannot identify the signing keychain')
        keychain = Path(paths[0])
    keychain = keychain.resolve(strict=True)
    identities = run(['security', 'find-identity', '-p', 'codesigning', str(keychain)]).stdout.decode().upper()
    if fingerprint not in identities:
        raise ValueError('The selected identity/private key is unavailable; no new identity created')
    result = run(['security', 'find-certificate', '-a', '-p', str(keychain)])
    certificates = [base64.b64decode(x) for x in re.findall(rb'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', result.stdout, re.S)]
    der = next((x for x in certificates if hashlib.sha1(x).hexdigest().upper() == fingerprint), None)
    if der is None: raise ValueError('Cannot locate the certificate of the selected identity')
    profile = dict(version=1, identitySHA1=fingerprint, certificateSHA256=hashlib.sha256(der).hexdigest(),
                   keychain=str(keychain), kind='explicit-existing-code-signing-identity')
    verify(profile)
    if config.exists():
        old = load_profile(config)
        if old['identitySHA1'] == fingerprint and old['keychain'] == str(keychain):
            print('Selected identity is already pinned; nothing changed.')
            return
        backup = config.with_name('LocalSigning-previous-' + uuid.uuid4().hex + '.local.json')
        config.rename(backup)
    save_profile(config, profile)
    print('Existing identity verified and pinned. Previous profile preserved; no keys or trust settings changed.')


def verify(profile):
    with tempfile.TemporaryDirectory(prefix='Veylume-signer-check-') as directory:
        temporary = Path(directory)
        source = temporary / 'probe.c'; binary = temporary / 'probe'
        source.write_text('int main(void) { return 0; }\n')
        run(['xcrun', 'clang', str(source), '-o', str(binary)])
        run(['/usr/bin/codesign', '--force', '--sign', profile['identitySHA1'], '--keychain', profile['keychain'],
             '--timestamp=none', '--identifier', 'local.Veylume.signing-probe', str(binary)])
        run(['/usr/bin/codesign', '--verify', '--strict', '-R=' + requirement('local.Veylume.signing-probe', profile['identitySHA1']), str(binary)])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=CONFIG)
    parser.add_argument('--keychain', type=Path, help='Existing unlocked signing keychain; default is the user default keychain')
    parser.add_argument('--use-identity', help='Explicitly pin an already issued code-signing identity by SHA-1; no certificate is generated')
    args = parser.parse_args()
    try:
        if args.use_identity: adopt_existing(args.config.resolve(), args.use_identity, args.keychain)
        else: setup(args.config.resolve(), args.keychain)
    except subprocess.CalledProcessError as error:
        # Child output can contain system paths; never echo command arguments or
        # the helper input. User passwords are never accepted by this script.
        raise SystemExit(f'Personal signing setup failed at {Path(error.cmd[0]).name} (exit {error.returncode}). The existing app was not changed; unlock the signing keychain and retry.')
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
