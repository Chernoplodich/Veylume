import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {'en', 'ru', 'es', 'fr'}
FORMAT = re.compile(r'%(?:\d+\$)?[-+#0 ]*\d*(?:\.\d+)?(?:hh|h|ll|l|L|z|j|t)?[diuoxXfFeEgGaAcsp@]')


class LocalizationCoverageTests(unittest.TestCase):
    def test_every_catalogue_entry_has_all_four_languages(self):
        entries = json.loads((ROOT / 'Configuration/Localizable.xcstrings').read_text())['strings']
        self.assertGreater(len(entries), 300)
        for key, entry in entries.items():
            self.assertEqual(set(entry['localizations']), LANGUAGES, key)
            for language, value in entry['localizations'].items():
                self.assertTrue(value['stringUnit']['value'].strip(), (language, key))
                self.assertEqual(value['stringUnit']['state'], 'translated')

    def test_adaptations_preserve_format_arguments_and_do_not_leak_russian(self):
        entries = json.loads((ROOT / 'Configuration/Localizable.xcstrings').read_text())['strings']
        for key, entry in entries.items():
            for language, value in entry['localizations'].items():
                text = value['stringUnit']['value']
                self.assertEqual(FORMAT.findall(text), FORMAT.findall(key), (language, key))
                if language in {'es', 'fr'}: self.assertIsNone(re.search('[А-Яа-яЁё]', text), (language, key))

    def test_help_and_system_permission_explanations_ship_in_each_language(self):
        for language in LANGUAGES:
            help_text = (ROOT / f'Veylume/Kit/Resources/Help-{language}.md').read_text()
            self.assertGreater(len(help_text), 1000)
            self.assertIn('Cohere', help_text)
            system = (ROOT / f'Configuration/{language}.lproj/InfoPlist.strings').read_text()
            self.assertIn('NSMicrophoneUsageDescription', system)
            self.assertIn('Veylume', system)


if __name__ == '__main__': unittest.main()
