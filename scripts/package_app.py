#!/usr/bin/env python3
"""Build six native release ZIPs, each with the same Gooswan/ layout."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
RELEASES = ROOT / 'dist/releases'
TARGETS = {'linux': ('amd64',), 'windows': ('x86_64',), 'macos': ('arm64', 'x86_64')}


def version():
    value = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value):
        raise ValueError('VERSION must contain major.minor.patch')
    return value


def copy_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def documents(folder):
    for name in ('README.md', 'THIRD_PARTY_NOTICES.md', 'docs/user-guide.md'):
        copy_file(ROOT / name, folder / name)
    copy_file(ROOT / 'assets/fonts/OFL.txt', folder / 'licenses/OFL.txt')


def archive(stage, output, macos=False):
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    if macos:
        # ditto preserves the signed app's metadata and Unix file modes.
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(stage / 'Gooswan'), str(output)], check=True)
    else:
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as target:
            for path in sorted(stage.rglob('*')):
                if path.is_file():
                    target.write(path, path.relative_to(stage))
    print(output)
    return output


def package(binary, platform, arch):
    if arch not in TARGETS[platform]:
        raise ValueError(f'Unsupported target: {platform}-{arch}')
    release = version()
    if platform == 'linux':
        from package_linux import package_linux
        return package_linux(binary, release)
    output = RELEASES / f'gooswan-{release}-{platform}-{arch}.zip'
    with tempfile.TemporaryDirectory(prefix='gooswan-package-') as temp:
        stage = Path(temp)
        folder = stage / 'Gooswan'
        documents(folder)
        if platform == 'macos':
            app = folder / 'Gooswan.app'
            executable = app / 'Contents/MacOS/Gooswan'
            resources = app / 'Contents/Resources'
            minimum = subprocess.check_output(['vtool', '-show-build', str(binary)], text=True)
            minimum = next(line.split()[1] for line in minimum.splitlines() if line.strip().startswith('minos '))
            copy_file(binary, executable)
            copy_file(ROOT / 'assets/icons/Gooswan.icns', resources / 'Gooswan.icns')
            documents(resources)
            info = dict(CFBundleName='Gooswan', CFBundleDisplayName='Gooswan',
                        CFBundleExecutable='Gooswan', CFBundleIdentifier='bubio.gooswan',
                        CFBundlePackageType='APPL', CFBundleInfoDictionaryVersion='6.0',
                        CFBundleShortVersionString=release, CFBundleVersion=release,
                        CFBundleIconFile='Gooswan.icns', LSMinimumSystemVersion=minimum,
                        NSHighResolutionCapable=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            executable.chmod(0o755)
            subprocess.run(['plutil', '-lint', str(app / 'Contents/Info.plist')], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
            # Keep the original local launch path current as well as the
            # architecture-specific output; otherwise Finder can show a stale app.
            for local in (ROOT / f'dist/macos-{arch}/Gooswan.app', ROOT / 'dist/Gooswan.app'):
                local.parent.mkdir(parents=True, exist_ok=True)
                if local.exists():
                    shutil.rmtree(local)
                shutil.copytree(app, local)
                local.touch()
        else:
            executable = folder / 'Gooswan.exe'
            copy_file(binary, executable)
            from windows_gui import prepare
            prepare(executable, ROOT / 'assets/icons/Gooswan.ico', release)
            executable.chmod(0o755)
        return [archive(stage, output, macos=platform == 'macos')]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('platform', choices=TARGETS)
    parser.add_argument('arch')
    args = parser.parse_args()
    package(args.binary.resolve(), args.platform, args.arch)
