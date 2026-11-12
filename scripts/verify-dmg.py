#!/usr/bin/env python3
"""Verify the actual read-only packaged app, not just the source bundle."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile


def verify(image, source):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
    mount = Path(tempfile.mkdtemp(prefix='Veylume-package-check-'))
    attached = False
    try:
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                        '-mountpoint', str(mount), str(image)], check=True, stdout=subprocess.DEVNULL)
        attached = True
        packaged = mount / 'Veylume.app'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(packaged)], check=True)
        digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
        for relative in ['Contents/MacOS/Veylume', 'Contents/Info.plist',
                         'Contents/Resources/AppIcon.icns', 'Contents/_CodeSignature/CodeResources']:
            if digest(packaged / relative) != digest(source / relative):
                raise ValueError('Packaged bundle differs from the verified source')
        if os.readlink(mount / 'Applications') != '/Applications':
            raise ValueError('Applications shortcut is invalid')
        if not (mount / 'Read me.txt').is_file(): raise ValueError('Install instructions are missing')
        spec = importlib.util.spec_from_file_location('metadata', Path(__file__).with_name('clean-image-metadata.py'))
        cleaner = importlib.util.module_from_spec(spec); spec.loader.exec_module(cleaner)
        for name in ['.VolumeIcon.icns', '.background.png']:
            path = mount / name
            if path.is_file() and cleaner.clean_bytes(path.read_bytes(), path.suffix) != path.read_bytes():
                raise ValueError('Descriptive image metadata remains in the installer')
        own_home = str(Path.home()).encode()
        for path in mount.rglob('*'):
            if path.is_file() and not path.is_symlink() and own_home in path.read_bytes():
                raise ValueError('A private builder path remains in the installer')
        metadata = plistlib.loads((packaged / 'Contents/Info.plist').read_bytes())
        return {'build': metadata['CFBundleVersion'], 'packagedSignatureValid': True,
                'packagedMatchesSource': True, 'readOnlyVerified': True,
                'privateBuilderPathsFound': False, 'installerImageMetadataClean': True}
    finally:
        # Never recursively remove a mountpoint. A failed detach leaves it in
        # place and fails verification; only an empty directory is removed.
        if attached: subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)
        mount.rmdir()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path); parser.add_argument('source', type=Path)
    arguments = parser.parse_args()
    try: print(json.dumps(verify(arguments.image.resolve(), arguments.source.resolve())))
    except (ValueError, OSError, subprocess.CalledProcessError):
        raise SystemExit('DMG verification failed; this image must not be distributed.')
