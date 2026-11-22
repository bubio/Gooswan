"""Validate relocated Linux packages and optional install/uninstall."""
from pathlib import Path
import struct
import subprocess
import tempfile

from package_common import DOCUMENTS


def check_architecture(data):
    assert data[:6] == b'\x7fELF\x02\x01'
    assert struct.unpack_from('<H', data, 18)[0] == 62, 'Not Linux x86-64'


def check_payload(payload, root, install):
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
    documents = (f'usr/share/doc/gooswan/{name}' for name in DOCUMENTS)
    for name in ('usr/share/icons/hicolor/256x256/apps/gooswan.png',
                 *documents, 'usr/share/licenses/gooswan/OFL.txt'):
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


def uninstall(payload):
    if payload.suffix == '.deb':
        subprocess.run(['apt-get', 'remove', '-y', 'gooswan'], check=True)
    else:
        subprocess.run(['dnf', 'remove', '-y', 'gooswan'], check=True)
    assert not Path('/usr/bin/gooswan').exists(), 'Uninstall left executable behind'
