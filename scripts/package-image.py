#!/usr/bin/env python3
"""Build a DMG and normalize its Finder-only presentation metadata."""
import argparse
import importlib.util
from pathlib import Path
import tempfile
import dmgbuild
from ds_store import DSStore

ROOT = Path(__file__).resolve().parents[1]


def build(app, output, distribution):
    mounted = None

    def remember_mount(path, options):
        nonlocal mounted
        mounted = Path(path)

    def metadata_ready(event):
        if event.get('type') != 'operation::finished' or event.get('operation') != 'dsstore::create':
            return
        # Finder can retain a user's path/status bars, and older macOS versions
        # have different titlebar heights. Match the image's solid canvas beyond
        # its edges instead of allowing a white strip on those systems.
        with DSStore.open(str(mounted / '.DS_Store'), 'r+') as store:
            view = store['.']['icvp']
            view.update(backgroundColorRed=0.93, backgroundColorGreen=0.97, backgroundColorBlue=0.99)
            store['.']['icvp'] = view

    spec = importlib.util.spec_from_file_location('metadata', ROOT / 'scripts/clean-image-metadata.py')
    cleaner = importlib.util.module_from_spec(spec); spec.loader.exec_module(cleaner)
    with tempfile.TemporaryDirectory(prefix='Veylume-artwork-') as temporary:
        icon = Path(temporary) / 'VolumeIcon.icns'
        icon.write_bytes(cleaner.clean_icns((ROOT / 'Configuration/AppIcon.icns').read_bytes()))
        background = Path(temporary) / 'background.png'
        background.write_bytes(cleaner.clean_png((ROOT / 'Configuration/Artwork/DMG-background.png').read_bytes()))
        dmgbuild.build_dmg(str(output), 'Veylume', settings_file=str(ROOT / 'scripts/dmg-settings.py'),
                          defines={'app': str(app), 'root': str(ROOT), 'distribution': distribution,
                                   'icon': str(icon), 'background': str(background)},
                          settings={'create_hook': remember_mount}, callback=metadata_ready)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('distribution', choices=['development', 'release'])
    arguments = parser.parse_args()
    build(arguments.app.resolve(), arguments.output.resolve(), arguments.distribution)
