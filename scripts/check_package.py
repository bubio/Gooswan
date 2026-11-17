#!/usr/bin/env python3
"""Verify native release ZIPs outside the checkout, optionally install Linux packages."""
import argparse
import ctypes
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DOCS = ('README.md', 'THIRD_PARTY_NOTICES.md', 'docs/user-guide.md', 'licenses/OFL.txt')


def extract(archive_path, root):
    with zipfile.ZipFile(archive_path) as archive:
        for entry in archive.infolist():
            path = root / entry.filename
            if not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'Unsafe ZIP member: {entry.filename}')
        archive.extractall(root)
        for entry in archive.infolist():
            mode = entry.external_attr >> 16
            if mode and not entry.is_dir():
                (root / entry.filename).chmod(mode & 0o777)


def architecture(binary, platform, arch):
    data = binary.read_bytes()
    if platform == 'windows':
        assert data[:2] == b'MZ'
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        assert data[pe:pe + 4] == b'PE\0\0'
        assert struct.unpack_from('<H', data, pe + 4)[0] == 0x8664, 'Not Windows x64'
        assert struct.unpack_from('<H', data, pe + 24 + 68)[0] == 2, 'Not a GUI executable'
    elif platform == 'linux':
        assert data[:6] == b'\x7fELF\x02\x01'
        assert struct.unpack_from('<H', data, 18)[0] == 62, 'Not Linux x86-64'
    else:
        assert data[:4] == b'\xcf\xfa\xed\xfe', 'Expected a thin 64-bit Mach-O'
        expected = {'arm64': 0x100000c, 'x86_64': 0x1000007}
        assert struct.unpack_from('<I', data, 4)[0] == expected[arch], 'Wrong macOS architecture'
    for name in ('assets/fonts/MPLUS1p-Regular.ttf', 'assets/icons/gooswan.bmp'):
        assert (ROOT / name).read_bytes() in data, f'Missing embedded {name}'


def windows_resources(binary):
    from ctypes import wintypes
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    api.LoadLibraryExW.restype = wintypes.HMODULE
    api.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    api.FindResourceW.restype = ctypes.c_void_p
    api.FreeLibrary.argtypes = [wintypes.HMODULE]
    module = api.LoadLibraryExW(str(binary), None, 2)
    assert module, 'Could not load executable resources'
    try:
        api.SizeofResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
        api.SizeofResource.restype = wintypes.DWORD
        api.LoadResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
        api.LoadResource.restype = wintypes.HGLOBAL
        api.LockResource.argtypes = [wintypes.HGLOBAL]
        api.LockResource.restype = ctypes.c_void_p
        from windows_gui import MANIFEST, version_resource
        expected = {16: version_resource((ROOT / 'VERSION').read_text().strip()), 24: MANIFEST}
        for kind in (14, 16, 24):
            resource = api.FindResourceW(module, 1, kind)
            assert resource, f'Missing PE resource type {kind}'
            if kind in expected:
                loaded = api.LoadResource(module, resource)
                address = api.LockResource(loaded)
                assert address, f'Cannot read PE resource type {kind}'
                payload = ctypes.string_at(address, api.SizeofResource(module, resource))
                assert payload == expected[kind], f'Incorrect PE resource type {kind}'
    finally:
        api.FreeLibrary(module)
    # Reject DLLs copied from a developer machine: only OS DLL imports are allowed.
    data = binary.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    sections = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    table = pe + 24 + optional_size

    def offset(rva):
        for i in range(sections):
            size, address, raw_size, raw = struct.unpack_from('<IIII', data, table + i * 40 + 8)
            if address <= rva < address + max(size, raw_size):
                return raw + rva - address
        raise ValueError(f'Unmapped RVA {rva}')

    # PE32+ import table (directory index 1).
    imports = struct.unpack_from('<I', data, pe + 24 + 112 + 8)[0]
    if imports:
        cursor = offset(imports)
        system = {'kernel32.dll', 'user32.dll', 'gdi32.dll', 'advapi32.dll', 'shell32.dll',
                  'ole32.dll', 'oleaut32.dll', 'imm32.dll', 'version.dll', 'winmm.dll',
                  'setupapi.dll', 'cfgmgr32.dll', 'hid.dll', 'ws2_32.dll', 'ntdll.dll',
                  'ucrtbase.dll', 'msvcrt.dll', 'comdlg32.dll', 'comctl32.dll', 'shlwapi.dll',
                  'dwmapi.dll', 'dxgi.dll', 'd3d11.dll', 'd3d12.dll', 'dxguid.dll',
                  'bcrypt.dll', 'crypt32.dll', 'winhttp.dll', 'rpcrt4.dll', 'propsys.dll',
                  'avrt.dll', 'powrprof.dll', 'wintrust.dll', 'shcore.dll', 'dbghelp.dll',
                  'winspool.drv', 'dinput8.dll', 'dsound.dll', 'iphlpapi.dll', 'userenv.dll',
                  'secur32.dll', 'psapi.dll', 'opengl32.dll', 'glu32.dll', 'd3dcompiler_47.dll'}
        while any(data[cursor:cursor + 20]):
            name_rva = struct.unpack_from('<I', data, cursor + 12)[0]
            start = offset(name_rva)
            name = data[start:data.index(0, start)].decode('ascii').lower()
            assert name in system or name.startswith(('api-ms-win-', 'ext-ms-win-')), f'Non-system DLL dependency: {name}'
            cursor += 20


def run(binary, cwd, smoke, appimage=False):
    env = dict(os.environ, GOOSWAN_CONFIG_DIR=str(cwd / 'config'), SDL_AUDIODRIVER='dummy')
    if appimage:
        env['APPIMAGE_EXTRACT_AND_RUN'] = '1'
    for flag in ('--help', '--self-test', *(('--ui-smoke',) if smoke else ())):
        result = subprocess.run([str(binary), flag], cwd=cwd, env=env, capture_output=True, text=True, timeout=120)
        print(result.stdout, end='')
        if result.returncode:
            raise RuntimeError(f'{flag}: exit {result.returncode}\n{result.stderr}')
        if flag == '--self-test':
            assert ', 0 failed' in result.stdout, result.stdout


def linux_payload(payload, root, install):
    if payload.suffix == '.AppImage':
        assert not install, 'AppImage is portable; use without --install'
        subprocess.run([str(payload), '--appimage-extract'], cwd=root, check=True, stdout=subprocess.DEVNULL)
        tree = root / 'squashfs-root'
        assert (tree / 'AppRun').stat().st_mode & 0o111
        assert (tree / 'gooswan.desktop').is_file()
        assert (tree / 'gooswan.png').is_file()
        assert (tree / 'usr/share/licenses/gooswan/APPIMAGE_NOTICES.txt').is_file()
    else:
        tree = root / 'installed'
        tree.mkdir()
        if payload.suffix == '.deb':
            subprocess.run(['dpkg-deb', '-x', str(payload), str(tree)], check=True)
            if install:
                subprocess.run(['apt-get', 'install', '-y', str(payload)], check=True)
        else:
            listing = subprocess.check_output(['rpm', '-qpl', str(payload)], text=True)
            assert '/usr/bin/gooswan' in listing.splitlines()
            # rpm2cpio + cpio avoids requiring root for structural/relocation checks.
            with tempfile.TemporaryFile() as stream:
                subprocess.run(['rpm2cpio', str(payload)], stdout=stream, check=True)
                stream.seek(0)
                subprocess.run(['cpio', '-idm', '--quiet'], stdin=stream, cwd=tree, check=True)
            if install:
                subprocess.run(['dnf', 'install', '-y', str(payload)], check=True)
    desktop = tree / 'usr/share/applications/gooswan.desktop'
    assert 'Terminal=false' in desktop.read_text()
    subprocess.run(['desktop-file-validate', str(desktop)], check=True)
    for name in ('usr/share/icons/hicolor/256x256/apps/gooswan.png',
                 'usr/share/doc/gooswan/README.md', 'usr/share/doc/gooswan/THIRD_PARTY_NOTICES.md',
                 'usr/share/doc/gooswan/docs/user-guide.md', 'usr/share/licenses/gooswan/OFL.txt'):
        assert (tree / name).is_file(), name
        # Minimal distro images can intentionally suppress installed documentation.
        # Its presence in the package is checked above, independent of that policy.
        if install and not name.startswith('usr/share/doc/'):
            assert (Path('/') / name).is_file(), name
    binary = tree / 'usr/bin/gooswan'
    linked = subprocess.check_output(['ldd', str(binary)], text=True)
    assert 'not found' not in linked, linked
    if install:
        assert Path('/usr/bin/gooswan').read_bytes() == binary.read_bytes()
        binary = Path('/usr/bin/gooswan')
    return binary


def check(archive_path, platform, arch, smoke=False, install=False):
    with tempfile.TemporaryDirectory(prefix='gooswan package ') as temp:
        root = Path(temp)
        extract(archive_path, root)
        folder = root / 'Gooswan'
        for name in DOCS:
            assert (folder / name).is_file(), name
        payloads = [p for p in folder.iterdir() if p.suffix in ('.app', '.exe', '.deb', '.rpm', '.AppImage')]
        assert len(payloads) == 1, 'Expected exactly one application payload'
        payload, = payloads
        expected = {payload.name, 'README.md', 'THIRD_PARTY_NOTICES.md', 'licenses', 'docs'}
        assert {p.name for p in folder.iterdir()} == expected, 'Unexpected distribution layout'
        # Move the application away from the wrapper docs and the source checkout.
        standalone = root / 'standalone app'
        standalone.mkdir()
        moved = standalone / payload.name
        shutil.move(str(payload), moved)
        payload = moved
        if platform == 'macos':
            binary = payload / 'Contents/MacOS/Gooswan'
            resources = payload / 'Contents/Resources'
            info = plistlib.loads((payload / 'Contents/Info.plist').read_bytes())
            assert info['CFBundleExecutable'] == binary.name
            assert info['CFBundleShortVersionString'] == (ROOT / 'VERSION').read_text().strip()
            assert (resources / info['CFBundleIconFile']).is_file()
            subprocess.run(['swift', '-module-cache-path', str(ROOT / '.goose/swift-module-cache'),
                            str(ROOT / 'scripts/check_icons.swift'),
                            str(resources / info['CFBundleIconFile']), str(ROOT / 'assets/icons/AppIcon.png')], check=True)
            for name in DOCS:
                assert (resources / name).is_file(), name
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(payload)], check=True)
            linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
            for line in linked.splitlines()[1:]:
                assert line.strip().startswith(('/usr/lib/', '/System/Library/')), f'Non-system dylib: {line}'
        elif platform == 'windows':
            binary = payload
            windows_resources(binary)
        else:
            binary = linux_payload(payload, root, install)
        architecture(binary, platform, arch)
        # For AppImage, exercise the real runtime as well as inspect the extracted ELF.
        run(payload if payload.suffix == '.AppImage' else binary, root, smoke, payload.suffix == '.AppImage')
        if install:
            if payload.suffix == '.deb':
                subprocess.run(['apt-get', 'remove', '-y', 'gooswan'], check=True)
            else:
                subprocess.run(['dnf', 'remove', '-y', 'gooswan'], check=True)
            assert not Path('/usr/bin/gooswan').exists(), 'Uninstall left executable behind'
        print(f'Package verified: {archive_path}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('platform', choices=('macos', 'windows', 'linux'))
    parser.add_argument('--arch', choices=('arm64', 'x86_64'), required=True)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--install', action='store_true', help='Install/remove deb or rpm (disposable root container only)')
    args = parser.parse_args()
    if args.install and (args.platform != 'linux' or os.geteuid() != 0):
        parser.error('--install requires Linux and root in a disposable container')
    check(args.archive.resolve(), args.platform, args.arch, args.smoke, args.install)
