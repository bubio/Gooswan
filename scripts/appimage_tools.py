#!/usr/bin/env python3
"""Fetch checksum-pinned official AppImage tools into the project-local cache."""
import hashlib
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
ASSETS = (
    ('appimagetool-1.9.1-x86_64.AppImage',
     'https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage',
     'ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0'),
    ('runtime-20251108-x86_64',
     'https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64',
     '2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d'),
)


def tools():
    cache = ROOT / '.tools/appimage'
    cache.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, url, checksum in ASSETS:
        path = cache / name
        if not path.exists():
            partial = path.with_suffix('.download')
            subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--connect-timeout', '15', '--max-time', '300', '--output', str(partial), url], check=True)
            if hashlib.sha256(partial.read_bytes()).hexdigest() != checksum:
                partial.unlink()
                raise ValueError(f'SHA-256 mismatch: {name}')
            partial.replace(path)
        if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise ValueError(f'SHA-256 mismatch: {path}; delete it and retry')
        path.chmod(0o755)
        paths.append(path)
    return paths


if __name__ == '__main__':
    for path in tools():
        print(path)
