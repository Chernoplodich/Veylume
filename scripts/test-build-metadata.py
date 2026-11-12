import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).with_name('check-macos-build.py'))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


def record(minimum='14.0', sdk='27.0', platform='MACOS'):
    return f'Load command 11\n cmd LC_BUILD_VERSION\n cmdsize 32\n platform {platform}\n minos {minimum}\n sdk {sdk}\n ntools 1\n'


class BuildMetadataTests(unittest.TestCase):
    def test_accepts_current_sdk_with_older_deployment(self):
        self.assertEqual(metadata.validate(record(), '27.0.0'), 1)

    def test_rejects_toolchain_sdk_deployment_mixup(self):
        with self.assertRaises(ValueError): metadata.validate(record(sdk='14.0'), '27.0')

    def test_rejects_accidentally_raised_minimum(self):
        with self.assertRaises(ValueError): metadata.validate(record(minimum='27.0'), '27.0')

    def test_rejects_wrong_or_missing_platform(self):
        for output in ['', record(platform='IOS')]:
            with self.assertRaises(ValueError): metadata.validate(output, '27.0')

    def test_checks_every_record(self):
        self.assertEqual(metadata.validate(record() + record(), '27.0'), 2)
        with self.assertRaises(ValueError): metadata.validate(record() + record(sdk='14.0'), '27.0')


if __name__ == '__main__': unittest.main()
