#!/usr/bin/env python3
"""Reject a raised minimum OS or legacy linked-SDK metadata before staging."""
import re
import subprocess
import sys


def version(value):
    parts = tuple(int(x) for x in value.split('.'))
    return parts + (0,) * (3 - len(parts))


def validate(output, expected_sdk):
    records = re.findall(r'\bcmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (\w+)\s+minos ([\d.]+)\s+sdk ([\d.]+)', output)
    if not records:
        raise ValueError('Missing LC_BUILD_VERSION')
    for platform, minimum, sdk in records:
        if platform != 'MACOS' or version(minimum) != version('14.0') or version(sdk) != version(expected_sdk):
            raise ValueError(f'Unexpected build metadata: {platform}, min {minimum}, SDK {sdk}; expected macOS 14 / SDK {expected_sdk}')
    return len(records)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: check-macos-build.py EXECUTABLE SDK_VERSION')
    result = subprocess.run(['xcrun', 'vtool', '-show-build', sys.argv[1]], check=True, capture_output=True, text=True)
    count = validate(result.stdout, sys.argv[2])
    print(f'Checked {count} macOS build record(s): minimum 14.0, SDK {sys.argv[2]}')
