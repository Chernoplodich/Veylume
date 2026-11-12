#!/usr/bin/env python3
"""Remove descriptive metadata without decoding or changing image pixels."""
import argparse
from pathlib import Path
import struct

PNG = b'\x89PNG\r\n\x1a\n'
DESCRIPTIVE = {b'eXIf', b'tEXt', b'iTXt', b'zTXt'}


def orientation(data):
    if data.startswith(b'Exif\0\0'): data = data[6:]
    if len(data) < 8 or data[:2] not in (b'II', b'MM'): return 1
    endian = '<' if data[:2] == b'II' else '>'
    offset = struct.unpack_from(endian + 'I', data, 4)[0]
    if offset + 2 > len(data): raise ValueError('Invalid EXIF directory')
    count = struct.unpack_from(endian + 'H', data, offset)[0]
    for at in range(offset + 2, offset + 2 + count * 12, 12):
        if at + 12 > len(data): raise ValueError('Truncated EXIF entry')
        tag, kind, length = struct.unpack_from(endian + 'HHI', data, at)
        if tag == 274:
            if kind != 3 or length != 1: raise ValueError('Unsupported EXIF orientation')
            return struct.unpack_from(endian + 'H', data, at + 8)[0]
    return 1


def clean_png(data):
    if not data.startswith(PNG): raise ValueError('Not a PNG')
    result = bytearray(PNG); at = len(PNG); ended = False
    while at < len(data):
        if at + 12 > len(data): raise ValueError('Truncated PNG chunk')
        length = struct.unpack_from('>I', data, at)[0]
        end = at + 12 + length
        if end > len(data): raise ValueError('Truncated PNG data')
        kind = data[at + 4:at + 8]
        if kind == b'eXIf' and orientation(data[at + 8:end - 4]) != 1:
            raise ValueError('Bake image orientation before removing EXIF')
        if kind not in DESCRIPTIVE: result.extend(data[at:end])
        at = end
        if kind == b'IEND':
            ended = True
            if at != len(data): raise ValueError('Unexpected data after PNG')
    if not ended: raise ValueError('Missing PNG end')
    return bytes(result)


def clean_icns(data):
    if len(data) < 8 or data[:4] != b'icns' or struct.unpack_from('>I', data, 4)[0] != len(data):
        raise ValueError('Invalid ICNS')
    result = bytearray(); at = 8
    while at < len(data):
        if at + 8 > len(data): raise ValueError('Truncated ICNS chunk')
        kind, length = data[at:at + 4], struct.unpack_from('>I', data, at + 4)[0]
        if length < 8 or at + length > len(data): raise ValueError('Invalid ICNS chunk length')
        payload = data[at + 8:at + length]
        if payload.startswith(PNG): payload = clean_png(payload)
        result.extend(kind + struct.pack('>I', len(payload) + 8) + payload)
        at += length
    return b'icns' + struct.pack('>I', len(result) + 8) + bytes(result)


def clean_bytes(data, suffix):
    return clean_png(data) if suffix.lower() == '.png' else clean_icns(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args(); changed = 0
    for path in args.directory.rglob('*'):
        if not path.is_file() or path.is_symlink() or path.suffix.lower() not in ('.png', '.icns'): continue
        original = path.read_bytes(); cleaned = clean_bytes(original, path.suffix)
        if cleaned != original: path.write_bytes(cleaned); changed += 1
    print(f'Image metadata cleaned in {changed} file(s); pixel and color-profile chunks preserved')


if __name__ == '__main__': main()
