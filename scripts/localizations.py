#!/usr/bin/env python3
"""Sync native resources from RU/EN literals and edited ES/FR String Catalog copy.
Missing adaptations fail the build instead of silently shipping English fallback.
"""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = ('en', 'ru', 'es', 'fr')
pattern = re.compile(r'I18n\.(?:tr|format)\("((?:\\.|[^"\\])*)",\s*"((?:\\.|[^"\\])*)"')


def rendered_files():
    translations = {}
    for path in (ROOT / 'Veylume/Kit').rglob('*.swift'):
        for ru, en in pattern.findall(path.read_text()):
            ru = json.loads('"' + ru + '"'); en = json.loads('"' + en + '"')
            translations[en] = ru
    catalogue_path = ROOT / 'Configuration/Localizable.xcstrings'
    previous = json.loads(catalogue_path.read_text())['strings']
    catalogue = dict(sourceLanguage='en', strings={}, version='1.0')
    values = {language: {} for language in LANGUAGES}
    missing = []
    for en, ru in sorted(translations.items()):
        for language in LANGUAGES:
            value = en if language == 'en' else ru if language == 'ru' else previous.get(en, {}).get('localizations', {}).get(language, {}).get('stringUnit', {}).get('value')
            if not isinstance(value, str) or not value.strip():
                missing.append(f'{language}: {en}'); continue
            values[language][en] = value
        catalogue['strings'][en] = dict(localizations={language: dict(stringUnit=dict(state='translated', value=values[language].get(en, ''))) for language in LANGUAGES})
    if missing: raise ValueError('Missing language adaptations:\n' + '\n'.join(missing))
    output = {catalogue_path: json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n'}
    for language in LANGUAGES:
        lines = [json.dumps(key, ensure_ascii=False) + ' = ' + json.dumps(value, ensure_ascii=False) + ';' for key, value in values[language].items()]
        output[ROOT / f'Veylume/Kit/Resources/{language}.lproj/Localizable.strings'] = '\n'.join(lines) + '\n'
    return output, len(translations)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    try:
        output, count = rendered_files()
        for path, text in output.items():
            if arguments.check:
                if not path.exists() or path.read_text() != text: raise ValueError('Localization resource is out of sync: ' + str(path.relative_to(ROOT)))
            else:
                path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)
        print(f'{count} adapted strings × {len(LANGUAGES)} languages verified' if arguments.check else f'{count} adapted strings × {len(LANGUAGES)} languages exported')
    except ValueError as error: raise SystemExit(str(error))
