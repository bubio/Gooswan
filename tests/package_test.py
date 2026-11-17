#!/usr/bin/env python3
"""Release contract checks that run without platform packaging tools."""
from pathlib import Path
import os
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from package_app import archive, documents, version
from release_assets import collect
from windows_gui import version_resource


class ReleaseTest(unittest.TestCase):
    def test_wrapper_layout_and_executable_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stage = root / 'stage'
            folder = stage / 'Gooswan'
            documents(folder)
            binary = folder / 'Gooswan.AppImage'
            binary.write_bytes(b'application')
            binary.chmod(0o755)
            output = archive(stage, root / 'output.zip')
            with zipfile.ZipFile(output) as result:
                self.assertEqual(set(result.namelist()), {
                    'Gooswan/Gooswan.AppImage', 'Gooswan/README.md',
                    'Gooswan/THIRD_PARTY_NOTICES.md', 'Gooswan/docs/user-guide.md',
                    'Gooswan/licenses/OFL.txt'})
                if os.name != 'nt':
                    self.assertEqual(result.getinfo('Gooswan/Gooswan.AppImage').external_attr >> 16 & 0o777, 0o755)

    def test_release_set_rejects_missing_duplicate_stale_and_wrong_tag(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            targets = ('linux-x86_64-deb', 'linux-x86_64-rpm', 'linux-x86_64-appimage',
                       'windows-x86_64', 'macos-x86_64', 'macos-arm64')
            for target in targets:
                (root / f'gooswan-{version()}-{target}.zip').write_bytes(b'zip')
            self.assertEqual(len(collect(root, 'v' + version())), 7)
            self.assertEqual(len((root / 'SHA256SUMS').read_text().splitlines()), 6)
            with self.assertRaises(ValueError):
                collect(root, 'v999.0.0')
            stale = root / 'gooswan-old.zip'
            stale.touch()
            with self.assertRaises(ValueError):
                collect(root)
            stale.unlink()
            duplicate = root / 'duplicate'
            duplicate.mkdir()
            name = f'gooswan-{version()}-macos-arm64.zip'
            (duplicate / name).touch()
            with self.assertRaises(ValueError):
                collect(root)
            (duplicate / name).unlink()
            (root / name).unlink()
            with self.assertRaises(ValueError):
                collect(root)

    def test_windows_versioninfo_alignment_lengths_and_version(self):
        data = version_resource('1.2.3')
        seen = {}

        def node(start, limit):
            length, value_length, kind = struct.unpack_from('<HHH', data, start)
            end = start + length
            self.assertLessEqual(end, limit)
            cursor = start + 6
            chars = []
            while True:
                char, = struct.unpack_from('<H', data, cursor)
                cursor += 2
                if not char:
                    break
                chars.append(chr(char))
            cursor = (cursor + 3) & ~3
            size = value_length * 2 if kind else value_length
            seen[''.join(chars)] = data[cursor:cursor + size]
            cursor = (cursor + size + 3) & ~3
            while cursor < end:
                self.assertEqual(cursor % 4, 0)
                cursor = (node(cursor, end) + 3) & ~3
            return end

        self.assertEqual(node(0, len(data)), len(data))
        fixed = struct.unpack('<13I', seen['VS_VERSION_INFO'])
        self.assertEqual(fixed[:6], (0xFEEF04BD, 0x10000, 0x10002, 0x30000, 0x10002, 0x30000))
        self.assertEqual(seen['FileVersion'].decode('utf-16le'), '1.2.3\0')
        self.assertEqual(seen['Translation'], struct.pack('<HH', 0x409, 1200))


if __name__ == '__main__':
    unittest.main()
