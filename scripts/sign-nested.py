#!/usr/bin/env python3
"""Sign known local build contents from the inside out. No codesign --deep signing."""
import os
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
identity = os.environ['VEY_DEVELOPER_IDENTITY']
root = pathlib.Path(__file__).resolve().parents[1]
blacklist = {'com.apple.security.get-task-allow', 'get-task-allow', 'com.apple.security.cs.disable-library-validation', 'com.apple.security.cs.allow-jit', 'com.apple.security.cs.allow-unsigned-executable-memory'}
def sign(path, main=False):
    command = ['codesign', '--force', '--sign', identity, '--timestamp', '--options', 'runtime']
    if main:
        command += ['--entitlements', str(root/'Configuration/Veylume.entitlements')]
    else:
        check = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)], capture_output=True)
        if b'<?xml' in check.stdout:
            data = plistlib.loads(check.stdout[check.stdout.index(b'<?xml'):])
            if any(data.get(key) for key in blacklist): raise SystemExit('Unexpected runtime exception in nested code')
        command += ['--preserve-metadata=identifier,entitlements']
    subprocess.run(command+[str(path)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
paths = sorted((p for p in app.rglob('*') if not p.is_symlink()), key=lambda p: len(p.parts), reverse=True)
for path in paths:
    if path.is_file():
        with path.open('rb') as handle: head = handle.read(4)
        if head in magic: sign(path)
for path in paths:
    if path.is_dir() and path.suffix in ['.framework', '.xpc', '.app', '.bundle']:
        # SwiftPM resource bundles contain no executable code and must not be
        # mistaken for nested app code objects.
        if path.suffix != '.bundle' or any(
            p.is_file() and p.read_bytes()[:4] in magic for p in path.rglob('*')
        ): sign(path)
sign(app, main=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
