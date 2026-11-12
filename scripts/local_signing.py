#!/usr/bin/env python3
"""Pinned personal signing. Never alters certificate trust or privacy grants."""
import argparse
import json
import os
import re
import subprocess
import hashlib
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'Configuration/LocalSigning.local.json'


def load_profile(path=CONFIG):
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError('Invalid personal signing profile')
    if data.get('version') != 1 or not isinstance(data.get('identitySHA1'), str) or not re.fullmatch(r'[A-Fa-f0-9]{40}', data['identitySHA1']):
        raise ValueError('Invalid personal signing profile; refusing ad-hoc fallback')
    if not isinstance(data.get('certificateSHA256'), str) or not re.fullmatch(r'[A-Fa-f0-9]{64}', data['certificateSHA256']):
        raise ValueError('Missing certificate pin; refusing ad-hoc fallback')
    keychain = data.get('keychain')
    if not isinstance(keychain, str) or not Path(keychain).is_absolute() or not Path(keychain).is_file():
        raise ValueError('Personal signing keychain unavailable; refusing ad-hoc fallback')
    data['identitySHA1'] = data['identitySHA1'].upper()
    return data


def select_identity(profile, environment):
    explicit = environment.get('VEY_LOCAL_SIGNING_IDENTITY')
    if profile:
        pinned = profile['identitySHA1']
        if explicit and explicit.upper() != pinned:
            raise ValueError('Personal identity is pinned. Reconfigure explicitly instead of changing signer.')
        return pinned
    return explicit or '-'


def requirement(identifier, fingerprint):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', identifier):
        raise ValueError('Invalid bundle identifier')
    if not re.fullmatch(r'[A-Fa-f0-9]{40}', fingerprint):
        raise ValueError('Invalid certificate fingerprint')
    return f'identifier "{identifier}" and certificate leaf = H"{fingerprint.lower()}"'


def sign(app, profile_path=CONFIG):
    profile = load_profile(profile_path)
    identity = select_identity(profile, os.environ)
    command = ['/usr/bin/codesign', '--force', '--sign', identity, '--timestamp=none',
               '--entitlements', str(ROOT / 'Configuration/Veylume.entitlements')]
    if profile:
        command += ['--keychain', profile['keychain']]
    subprocess.run(command + [str(app)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    if profile:
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict',
                        '-R=' + requirement('local.Veylume.dev', identity), str(app)], check=True)
        with tempfile.TemporaryDirectory(prefix='Veylume-cert-check-') as directory:
            prefix = Path(directory) / 'certificate'
            subprocess.run(['/usr/bin/codesign', '-d', '--extract-certificates=' + str(prefix), str(app)], check=True, capture_output=True)
            if hashlib.sha256(Path(str(prefix) + '0').read_bytes()).hexdigest() != profile['certificateSHA256'].lower():
                raise ValueError('Signed certificate does not match the configured SHA-256 pin')
    print('Personal certificate signature verified' if profile else 'Development signature verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    try:
        sign(args.app)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
