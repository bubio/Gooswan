#!/usr/bin/env python3
"""Build native release ZIPs with a shared Gooswan/ layout."""
import argparse
from pathlib import Path

from package_common import version

TARGETS = {'linux': ('amd64',), 'windows': ('x86_64',), 'macos': ('arm64', 'x86_64')}


def package(binary, platform, arch):
    if arch not in TARGETS[platform]:
        raise ValueError(f'Unsupported target: {platform}-{arch}')
    release = version()
    if platform == 'linux':
        from package_linux import package_linux
        return package_linux(binary, release)
    if platform == 'macos':
        from package_macos import package_macos
        return package_macos(binary, release, arch)
    from windows_gui import package_windows
    return package_windows(binary, release, arch)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('platform', choices=TARGETS)
    parser.add_argument('arch')
    args = parser.parse_args()
    package(args.binary.resolve(), args.platform, args.arch)
