#!/usr/bin/env python3
"""Require all six exact release filenames and generate SHA256SUMS."""
import argparse
import hashlib
from pathlib import Path
from package_app import version


def collect(directory, tag=None):
    release = version()
    if tag is not None and tag not in (release, 'v' + release):
        raise ValueError(f'Release tag {tag!r} does not match VERSION {release!r}')
    expected = {f'gooswan-{release}-{target}.zip' for target in (
        'linux-x86_64-deb', 'linux-x86_64-rpm', 'linux-x86_64-appimage',
        'windows-x86_64', 'macos-x86_64', 'macos-arm64')}
    paths = sorted(directory.rglob('*.zip'))
    if len(paths) != 6 or {p.name for p in paths} != expected:
        raise ValueError(f'Expected six release ZIPs: {sorted(expected)}; found: {[p.name for p in paths]}')
    sums = directory / 'SHA256SUMS'
    sums.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in paths))
    print(sums)
    return paths + [sums]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--tag')
    args = parser.parse_args()
    collect(args.directory, args.tag)
