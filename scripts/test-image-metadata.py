import importlib.util
from pathlib import Path
import struct
import unittest
import zlib

spec = importlib.util.spec_from_file_location('clean_image_metadata', Path(__file__).with_name('clean-image-metadata.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


class ImageMetadataTests(unittest.TestCase):
    def test_keeps_pixel_and_profile_chunks_byte_for_byte(self):
        critical = chunk(b'IHDR', b'header') + chunk(b'iCCP', b'profile') + chunk(b'IDAT', b'unchanged pixels') + chunk(b'IEND', b'')
        png = module.PNG + chunk(b'tEXt', b'Software\0fixture') + critical
        self.assertEqual(module.clean_png(png), module.PNG + critical)

    def test_refuses_orientation_that_would_change_appearance(self):
        # Explicit IFD: one SHORT orientation value of 6, stored inline.
        exif = b'II' + struct.pack('<HIH', 42, 8, 1) + struct.pack('<HHIH', 274, 3, 1, 6) + b'\0\0' + b'\0\0\0\0'
        png = module.PNG + chunk(b'eXIf', exif) + chunk(b'IEND', b'')
        with self.assertRaises(ValueError): module.clean_png(png)

    def test_rebuilds_icon_container_lengths_without_changing_pixels(self):
        pixels = chunk(b'IDAT', b'pixels') + chunk(b'IEND', b'')
        png = module.PNG + chunk(b'iTXt', b'metadata') + pixels
        icon = b'icns' + struct.pack('>I', len(png) + 16) + b'ic10' + struct.pack('>I', len(png) + 8) + png
        cleaned = module.clean_icns(icon)
        self.assertEqual(struct.unpack_from('>I', cleaned, 4)[0], len(cleaned))
        self.assertEqual(cleaned[16:], module.PNG + pixels)

    def test_rejects_truncated_or_extra_data(self):
        for data in [module.PNG, module.PNG + b'bad', module.PNG + chunk(b'IEND', b'') + b'extra']:
            with self.assertRaises(ValueError): module.clean_png(data)


if __name__ == '__main__': unittest.main()
