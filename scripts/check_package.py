#!/usr/bin/env python3
"""Verify and run a packaged app after extracting outside the checkout."""
import argparse
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile


def check(archive_path, platform, smoke=False):
    with tempfile.TemporaryDirectory(prefix='gooswan package ') as temp:
        root = Path(temp)
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(root)
            # zipfile doesn't restore Unix execute permissions.
            for entry in archive.infolist():
                mode = entry.external_attr >> 16
                if mode and not entry.is_dir():
                    (root / entry.filename).chmod(mode & 0o777)
        if platform == 'macos':
            app = root / 'Gooswan.app'
            binary = app / 'Contents/MacOS/Gooswan'
            resources = app / 'Contents/Resources'
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            assert info['CFBundleExecutable'] == binary.name
            assert (resources / info['CFBundleIconFile']).is_file()
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        else:
            resources = root / 'Gooswan'
            binary = resources / ('Gooswan.exe' if platform == 'windows' else 'gooswan')
            if platform == 'windows':
                data = binary.read_bytes()
                pe = struct.unpack_from('<I', data, 0x3c)[0]
                assert struct.unpack_from('<H', data, pe + 24 + 68)[0] == 2, 'Not a GUI executable'
                # Verify that the Windows loader can find the embedded group icon.
                import ctypes
                from ctypes import wintypes
                api = ctypes.WinDLL('kernel32', use_last_error=True)
                api.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
                api.LoadLibraryExW.restype = wintypes.HMODULE
                api.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
                api.FindResourceW.restype = ctypes.c_void_p
                api.FreeLibrary.argtypes = [wintypes.HMODULE]
                module = api.LoadLibraryExW(str(binary), None, 2)
                assert module, 'Could not load packaged executable'
                try:
                    assert api.FindResourceW(module, 1, 14), 'Missing embedded icon'
                finally:
                    api.FreeLibrary(module)
            else:
                assert 'Terminal=false' in (resources / 'gooswan.desktop').read_text()
                assert (resources / 'install.sh').is_file()
        for name in ('README.md', 'THIRD_PARTY_NOTICES.md', 'assets/fonts/MPLUS1p-Regular.ttf', 'assets/fonts/OFL.txt', 'assets/icons/gooswan.bmp', 'assets/icons/gooswan.png'):
            assert (resources / name).is_file(), name
        env = dict(os.environ, GOOSWAN_CONFIG_DIR=str(root / 'config'), SDL_AUDIODRIVER='dummy')
        for flag in ('--help', '--self-test'):
            result = subprocess.run([str(binary), flag], cwd=root, env=env, capture_output=True, text=True, timeout=120)
            print(result.stdout, end='')
            if result.returncode:
                raise RuntimeError(f'{flag}: exit {result.returncode}\n{result.stderr}')
            if flag == '--self-test':
                assert ', 0 failed' in result.stdout, result.stdout
        if platform == 'linux':
            # Validate the desktop-menu installation with a home containing spaces.
            home = root / 'install home'
            home.mkdir()
            data = home / 'desktop data'
            install_env = dict(env, HOME=str(home), XDG_DATA_HOME=str(data))
            subprocess.run(['sh', str(resources / 'install.sh')], cwd=root, env=install_env, check=True, timeout=60)
            installed = home / '.local/lib/gooswan'
            launcher = home / '.local/bin/gooswan'
            assert launcher.resolve() == (installed / 'gooswan').resolve()
            assert (installed / 'assets/fonts/MPLUS1p-Regular.ttf').is_file()
            assert f'Exec="{installed}/gooswan"' in (data / 'applications/gooswan.desktop').read_text()
            binary = launcher
        if smoke:
            subprocess.run([str(binary), '--ui-smoke'], cwd=root, env=env, check=True, timeout=120)
        print(f'Package verified: {archive_path}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('platform', choices=('macos', 'windows', 'linux'))
    parser.add_argument('--smoke', action='store_true')
    args = parser.parse_args()
    check(args.archive.resolve(), args.platform, args.smoke)
