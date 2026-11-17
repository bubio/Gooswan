#!/usr/bin/env python3
"""Regenerate committed OS icons on macOS using sips (no Python dependencies)."""
from pathlib import Path
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
icons = root / 'assets/icons'
with tempfile.TemporaryDirectory() as temp:
    images = {}
    for size in (16, 32, 48, 64, 128, 256, 512, 1024):
        path = Path(temp) / f'{size}.png'
        subprocess.run(['sips', '-z', str(size), str(size), str(icons / 'AppIcon.png'), '--out', str(path)], check=True, stdout=subprocess.DEVNULL)
        images[size] = path.read_bytes()
    (icons / 'gooswan.png').write_bytes(images[256])
    subprocess.run(['sips', '-s', 'format', 'bmp', str(icons / 'gooswan.png'), '--out', str(icons / 'gooswan.bmp')], check=True, stdout=subprocess.DEVNULL)
    chunks = []
    for size, kind in ((16, b'icp4'), (32, b'icp5'), (64, b'icp6'), (128, b'ic07'), (256, b'ic08'), (512, b'ic09'), (1024, b'ic10')):
        data = images[size]
        chunks.append(kind + struct.pack('>I', len(data) + 8) + data)
    data = b''.join(chunks)
    (icons / 'Gooswan.icns').write_bytes(b'icns' + struct.pack('>I', len(data) + 8) + data)
    sizes = (16, 32, 48, 64, 128, 256)
    offset = 6 + 16 * len(sizes)
    entries = []
    for size in sizes:
        data = images[size]
        entries.append(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 24, len(data), offset))
        offset += len(data)
    (icons / 'Gooswan.ico').write_bytes(struct.pack('<HHH', 0, 1, len(sizes)) + b''.join(entries) + b''.join(images[size] for size in sizes))
