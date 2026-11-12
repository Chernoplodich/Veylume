import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import importlib.util
import hashlib
import base64
from types import SimpleNamespace
from local_signing import load_profile, requirement, select_identity

spec = importlib.util.spec_from_file_location('personal_setup', Path(__file__).with_name('setup-local-signing.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class LocalSigningTests(unittest.TestCase):
    def test_explicit_adoption_pins_selected_certificate_and_preserves_old_profile(self):
        certificate = b'public-certificate-fixture'
        fingerprint = hashlib.sha1(certificate).hexdigest().upper()
        pem = b'-----BEGIN CERTIFICATE-----\n' + base64.b64encode(certificate) + b'\n-----END CERTIFICATE-----\n'
        with tempfile.TemporaryDirectory() as directory:
            keychain = Path(directory) / 'fixture.keychain-db'; keychain.touch()
            profile = Path(directory) / 'LocalSigning.local.json'
            old = dict(version=1, identitySHA1='A'*40, certificateSHA256='B'*64, keychain=str(keychain))
            profile.write_text(json.dumps(old))
            def run(arguments):
                return SimpleNamespace(stdout=(fingerprint.encode() if 'find-identity' in arguments else pem))
            with patch.object(setup, 'run', side_effect=run), patch.object(setup, 'verify') as verify:
                setup.adopt_existing(profile, fingerprint, keychain)
                verify.assert_called_once()
            selected = load_profile(profile)
            self.assertEqual(selected['identitySHA1'], fingerprint)
            self.assertEqual(selected['certificateSHA256'], hashlib.sha256(certificate).hexdigest())
            backups = list(Path(directory).glob('LocalSigning-previous-*.local.json'))
            self.assertEqual(len(backups), 1); self.assertEqual(json.loads(backups[0].read_text()), old)

    def test_explicit_adoption_never_generates_a_missing_key_or_overwrites_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            keychain = Path(directory) / 'fixture.keychain-db'; keychain.touch()
            profile = Path(directory) / 'LocalSigning.local.json'
            with patch.object(setup, 'run', return_value=SimpleNamespace(stdout=b'')), patch.object(setup, 'verify') as verify:
                with self.assertRaises(ValueError): setup.adopt_existing(profile, 'A'*40, keychain)
                verify.assert_not_called()
            self.assertFalse(profile.exists())
    def test_missing_profile_keeps_explicit_legacy_development_path(self):
        self.assertEqual(select_identity(None, {}), '-')
        self.assertEqual(select_identity(None, {'VEY_LOCAL_SIGNING_IDENTITY': 'existing identity'}), 'existing identity')

    def test_configured_identity_cannot_silently_return_to_adhoc_or_rotate(self):
        profile = {'identitySHA1': 'A' * 40}
        self.assertEqual(select_identity(profile, {}), 'A' * 40)
        for value in ['-', 'B' * 40, 'other identity']:
            with self.assertRaises(ValueError): select_identity(profile, {'VEY_LOCAL_SIGNING_IDENTITY': value})

    def test_missing_keychain_and_malformed_profile_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'profile.json'
            self.assertIsNone(load_profile(path))
            for profile in [{'version': 1, 'identitySHA1': 'A' * 40, 'certificateSHA256': 'B' * 64, 'keychain': '/missing/Veylume-signing.keychain-db'},
                            {'version': 1, 'identitySHA1': '-'}, {'version': 9, 'identitySHA1': 'A' * 40},
                            {'version': 1, 'identitySHA1': 123}, [], None]:
                path.write_text(json.dumps(profile))
                with self.assertRaises(ValueError): load_profile(path)

    def test_profile_pins_certificate_and_requires_absolute_keychain_path(self):
        with tempfile.TemporaryDirectory() as directory:
            keychain = Path(directory) / 'fixture.keychain-db'; keychain.touch()
            profile = {'version': 1, 'identitySHA1': 'a' * 40, 'certificateSHA256': 'b' * 64, 'keychain': str(keychain)}
            path = Path(directory) / 'profile.json'; path.write_text(json.dumps(profile))
            self.assertEqual(load_profile(path)['identitySHA1'], 'A' * 40)
            profile['keychain'] = 'relative.keychain-db'; path.write_text(json.dumps(profile))
            with self.assertRaises(ValueError): load_profile(path)

    def test_requirement_does_not_accept_identifier_only_or_injected_expression(self):
        value = requirement('local.Veylume.dev', 'A' * 40)
        self.assertIn('certificate leaf', value)
        for identifier in ['local.Veylume.dev" or true', '', '../app']:
            with self.assertRaises(ValueError): requirement(identifier, 'A' * 40)
        with self.assertRaises(ValueError): requirement('local.Veylume.dev', '-')


if __name__ == '__main__': unittest.main()
