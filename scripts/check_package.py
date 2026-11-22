#!/usr/bin/env python3
"""Verify native release ZIPs outside the checkout, optionally install Linux packages."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

from package_common import ROOT, WRAPPER_FILES


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


def check_embedded_assets(data):
    for name in ('assets/fonts/MPLUS1p-Regular.ttf', 'assets/icons/gooswan.bmp'):
        assert (ROOT / name).read_bytes() in data, f'Missing embedded {name}'


def run(binary, cwd, smoke, appimage=False):
    env = dict(os.environ, GOOSWAN_CONFIG_DIR=str(cwd / 'config'), SDL_AUDIODRIVER='dummy')
    if appimage:
        env['APPIMAGE_EXTRACT_AND_RUN'] = '1'
    for flag in ('--help', '--self-test', '--link-self-test', *(('--ui-smoke',) if smoke else ())):
        result = subprocess.run([str(binary), flag], cwd=cwd, env=env, capture_output=True, text=True, timeout=120)
        print(result.stdout, end='')
        if result.returncode:
            raise RuntimeError(f'{flag}: exit {result.returncode}\n{result.stderr}')
        if flag == '--self-test':
            assert ', 0 failed' in result.stdout, result.stdout


def check(archive_path, platform, arch, smoke=False, install=False):
    with tempfile.TemporaryDirectory(prefix='gooswan package ') as temp:
        root = Path(temp)
        extract(archive_path, root)
        folder = root / 'Gooswan'
        for name in WRAPPER_FILES:
            assert (folder / name).is_file(), name
        payloads = [p for p in folder.iterdir() if p.name != 'gooswan-link.exe' and p.suffix in ('.app', '.exe', '.deb', '.rpm', '.AppImage')]
        assert len(payloads) == 1, 'Expected exactly one application payload'
        payload, = payloads
        expected = {payload.name, 'README.md', 'THIRD_PARTY_NOTICES.md', 'licenses', 'docs'}
        if platform == 'windows':
            expected.add('gooswan-link.exe')
        assert {p.name for p in folder.iterdir()} == expected, 'Unexpected distribution layout'
        # Move the application away from the wrapper docs and the source checkout.
        standalone = root / 'standalone app'
        standalone.mkdir()
        moved = standalone / payload.name
        shutil.move(str(payload), moved)
        payload = moved
        if platform == 'windows':
            shutil.move(folder / 'gooswan-link.exe', standalone / 'gooswan-link.exe')
        if platform == 'macos':
            from check_package_macos import check_architecture, check_payload
            binary = check_payload(payload)
            data = binary.read_bytes()
            check_architecture(data, arch)
        elif platform == 'windows':
            from check_package_windows import check_architecture, check_payload
            binary = check_payload(payload)
            data = binary.read_bytes()
            check_architecture(data)
        else:
            from check_package_linux import check_architecture, check_payload, uninstall
            binary = check_payload(payload, root, install)
            data = binary.read_bytes()
            check_architecture(data)
        check_embedded_assets(data)
        # For AppImage, exercise the real runtime as well as inspect the extracted ELF.
        appimage = payload.suffix == '.AppImage'
        run(payload if appimage else binary, root, smoke, appimage)
        if install:
            uninstall(payload)
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
