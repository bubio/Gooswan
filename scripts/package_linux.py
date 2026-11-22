#!/usr/bin/env python3
"""Build deb, rpm and AppImage from one native x86-64 Linux executable.

Requires dpkg-dev, rpm, desktop-file-utils, file, and the pinned AppImage tools
installed by scripts/appimage_tools.py. SDL and application assets are embedded;
OS window/audio libraries and Vulkan drivers remain system dependencies.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from package_common import DOCUMENTS, ROOT, RELEASES, archive, copy_file, documents

# SDL dlopens these libraries, so ELF dependency scanners cannot discover them.
DEB_RUNTIME = ['libx11-6', 'libxcursor1', 'libxi6', 'libxrandr2', 'libxkbcommon0',
               'libwayland-client0', 'libasound2', 'libpulse0', 'libvulkan1']
RPM_RUNTIME = ['libX11.so.6()(64bit)', 'libXcursor.so.1()(64bit)', 'libXi.so.6()(64bit)',
               'libXrandr.so.2()(64bit)', 'libxkbcommon.so.0()(64bit)',
               'libwayland-client.so.0()(64bit)', 'libasound.so.2()(64bit)',
               'libpulse.so.0()(64bit)', 'libvulkan.so.1()(64bit)']


def install_tree(binary, tree):
    copy_file(binary, tree / 'usr/bin/gooswan')
    copy_file(binary.with_name('gooswan-link'), tree / 'usr/bin/gooswan-link')
    (tree / 'usr/bin/gooswan').chmod(0o755)
    copy_file(ROOT / 'packaging/linux/gooswan.desktop', tree / 'usr/share/applications/gooswan.desktop')
    copy_file(ROOT / 'assets/icons/gooswan.png', tree / 'usr/share/icons/hicolor/256x256/apps/gooswan.png')
    for name in DOCUMENTS:
        copy_file(ROOT / name, tree / 'usr/share/doc/gooswan' / name)
    copy_file(ROOT / 'assets/fonts/OFL.txt', tree / 'usr/share/licenses/gooswan/OFL.txt')


def deb(binary, tree, output, release, work):
    # Scan actual linked ELF libraries in addition to SDL's dlopen dependencies.
    scan = work / 'deb-scan'
    (scan / 'debian').mkdir(parents=True)
    (scan / 'debian/control').write_text('Source: gooswan\n\nPackage: gooswan\nArchitecture: amd64\nDescription: WonderSwan emulator\n')
    linked = subprocess.check_output(['dpkg-shlibdeps', '-O', '-e' + str(binary)], cwd=scan, text=True)
    depends = next(line.removeprefix('shlibs:Depends=') for line in linked.splitlines() if line.startswith('shlibs:Depends='))
    control = tree / 'DEBIAN'
    control.mkdir()
    (control / 'control').write_text(f'''Package: gooswan
Version: {release}
Section: games
Priority: optional
Architecture: amd64
Maintainer: bubio <bubio@users.noreply.github.com>
Homepage: https://github.com/bubio/Gooswan
Installed-Size: {sum(p.stat().st_size for p in tree.rglob('*') if p.is_file()) // 1024 + 1}
Depends: {', '.join(filter(None, [depends, *DEB_RUNTIME, 'ca-certificates']))}
Description: WonderSwan / WonderSwan Color emulator
 Keyboard and gamepad controls, save states, rotation and display scaling.
''')
    subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(tree), str(output)], check=True)
    shutil.rmtree(control)


def rpm(tree, output, release, work):
    top = work / 'rpmbuild'
    top.mkdir()
    spec = work / 'gooswan.spec'
    # No project license has been declared; do not assert an open-source license.
    # Bundled third-party licenses are installed in /usr/share/doc and /licenses.
    spec.write_text(f'''%global debug_package %{{nil}}
%global __os_install_post %{{nil}}
Name: gooswan
Version: {release}
Release: 1
Summary: WonderSwan / WonderSwan Color emulator
License: LicenseRef-Gooswan
URL: https://github.com/bubio/Gooswan
BuildArch: x86_64
Requires: {', '.join((*RPM_RUNTIME, 'ca-certificates'))}

%description
WonderSwan / WonderSwan Color emulator with keyboard and gamepad controls,
save states, rotation and display scaling.

%prep
%build
%install
mkdir -p "%{{buildroot}}"
cp -a "{tree}/usr" "%{{buildroot}}/"

%files
/usr/bin/gooswan
/usr/bin/gooswan-link
/usr/share/applications/gooswan.desktop
/usr/share/icons/hicolor/256x256/apps/gooswan.png
%doc /usr/share/doc/gooswan
%license /usr/share/licenses/gooswan
''')
    subprocess.run(['rpmbuild', '-bb', '--define', f'_topdir {top}', '--define', '_build_id_links none', str(spec)], check=True)
    result, = (top / 'RPMS/x86_64').glob('*.rpm')
    shutil.copy2(result, output)


def appimage(tree, output, work):
    from appimage_tools import tools
    tool, runtime = tools()
    appdir = work / 'Gooswan.AppDir'
    shutil.copytree(tree, appdir)
    copy_file(ROOT / 'packaging/linux/AppRun', appdir / 'AppRun')
    (appdir / 'AppRun').chmod(0o755)
    copy_file(ROOT / 'packaging/linux/gooswan.desktop', appdir / 'gooswan.desktop')
    copy_file(ROOT / 'assets/icons/gooswan.png', appdir / 'gooswan.png')
    copy_file(ROOT / 'packaging/linux/APPIMAGE_NOTICES.txt', appdir / 'usr/share/licenses/gooswan/APPIMAGE_NOTICES.txt')
    # FUSE is not needed on build hosts. A fixed runtime avoids implicit downloads.
    env = dict(os.environ, ARCH='x86_64', APPIMAGE_EXTRACT_AND_RUN='1', VERSION='')
    subprocess.run([str(tool), '--no-appstream', '--runtime-file', str(runtime), str(appdir), str(output)], env=env, check=True)
    output.chmod(0o755)


def package_linux(binary, release):
    with tempfile.TemporaryDirectory(prefix='gooswan-package-') as temp:
        work = Path(temp)
        tree = work / 'root'
        install_tree(binary, tree)
        subprocess.run(['desktop-file-validate', str(tree / 'usr/share/applications/gooswan.desktop')], check=True)
        outputs = []
        for kind, name, builder in (
            ('deb', f'gooswan_{release}_amd64.deb', lambda dest: deb(binary, tree, dest, release, work)),
            ('rpm', f'gooswan-{release}-1.x86_64.rpm', lambda dest: rpm(tree, dest, release, work)),
            ('appimage', 'Gooswan.AppImage', lambda dest: appimage(tree, dest, work)),
        ):
            stage = work / kind
            folder = stage / 'Gooswan'
            documents(folder)
            if kind == 'appimage':
                copy_file(ROOT / 'packaging/linux/APPIMAGE_NOTICES.txt', folder / 'licenses/APPIMAGE_NOTICES.txt')
            builder(folder / name)
            outputs.append(archive(stage, RELEASES / f'gooswan-{release}-linux-x86_64-{kind}.zip'))
        return outputs
