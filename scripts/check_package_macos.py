"""Validate a relocated macOS app bundle."""
import plistlib
import struct
import subprocess

from package_common import ROOT, WRAPPER_FILES, version


def check_architecture(data, arch):
    assert data[:4] == b'\xcf\xfa\xed\xfe', 'Expected a thin 64-bit Mach-O'
    expected = {'arm64': 0x100000c, 'x86_64': 0x1000007}
    assert struct.unpack_from('<I', data, 4)[0] == expected[arch], 'Wrong macOS architecture'


def check_payload(payload):
    binary = payload / 'Contents/MacOS/Gooswan'
    resources = payload / 'Contents/Resources'
    info = plistlib.loads((payload / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleExecutable'] == binary.name
    assert info['CFBundleShortVersionString'] == version()
    assert (resources / info['CFBundleIconFile']).is_file()
    subprocess.run(['swift', '-module-cache-path', str(ROOT / '.goose/swift-module-cache'),
                    str(ROOT / 'scripts/check_icons.swift'),
                    str(resources / info['CFBundleIconFile']), str(ROOT / 'assets/icons/AppIcon.png')], check=True)
    for name in WRAPPER_FILES:
        assert (resources / name).is_file(), name
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(payload)], check=True)
    linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    for line in linked.splitlines()[1:]:
        assert line.strip().startswith(('/usr/lib/', '/System/Library/')), f'Non-system dylib: {line}'
    return binary
