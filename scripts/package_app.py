#!/usr/bin/env python3
"""Package the native build on its host OS; ZIP contents are relocatable."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def package(binary, platform, arch):
    version = (ROOT / 'VERSION').read_text().strip()
    # Fail early on a malformed release version, including XML/path characters.
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('VERSION must contain major.minor.patch')
    output = ROOT / f'gooswan-{platform}-{arch}.zip'
    with tempfile.TemporaryDirectory() as temp:
        stage = Path(temp)
        if platform == 'macos':
            app = stage / 'Gooswan.app'
            executable = app / 'Contents/MacOS/Gooswan'
            resources = app / 'Contents/Resources'
            minimum = subprocess.check_output(['vtool', '-show-build', str(binary)], text=True)
            minimum = next(line.split()[1] for line in minimum.splitlines() if line.strip().startswith('minos '))
            executable.parent.mkdir(parents=True)
            resources.mkdir(parents=True)
            shutil.copy2(binary, executable)
            shutil.copy2(ROOT / 'assets/icons/Gooswan.icns', resources)
            info = dict(CFBundleName='Gooswan', CFBundleDisplayName='Gooswan',
                        CFBundleExecutable='Gooswan', CFBundleIdentifier='bubio.gooswan',
                        CFBundlePackageType='APPL', CFBundleInfoDictionaryVersion='6.0',
                        CFBundleShortVersionString=version, CFBundleVersion=version,
                        CFBundleIconFile='Gooswan.icns', LSMinimumSystemVersion=minimum,
                        NSHighResolutionCapable=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        else:
            resources = stage / 'Gooswan'
            resources.mkdir()
            executable = resources / ('Gooswan.exe' if platform == 'windows' else 'gooswan')
            shutil.copy2(binary, executable)
            if platform == 'windows':
                from windows_gui import prepare
                prepare(executable, ROOT / 'assets/icons/Gooswan.ico')
            else:
                for name in ('gooswan.desktop', 'install.sh'):
                    shutil.copy2(ROOT / 'packaging/linux' / name, resources)
                (resources / 'install.sh').chmod(0o755)
        executable.chmod(0o755)
        for name in ('README.md', 'THIRD_PARTY_NOTICES.md'):
            shutil.copy2(ROOT / name, resources)
        (resources / 'docs').mkdir()
        for name in ('user-guide.md', 'development.md'):
            shutil.copy2(ROOT / 'docs' / name, resources / 'docs' / name)
        shutil.copytree(ROOT / 'assets/fonts', resources / 'assets/fonts')
        (resources / 'assets/icons').mkdir()
        for name in ('gooswan.png', 'gooswan.bmp'):
            shutil.copy2(ROOT / 'assets/icons' / name, resources / 'assets/icons' / name)
        if platform == 'macos':
            subprocess.run(['plutil', '-lint', str(app / 'Contents/Info.plist')], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
            # ditto preserves the signed app bundle's metadata and file modes.
            output.unlink(missing_ok=True)
            subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(output)], check=True)
            local = ROOT / 'dist/Gooswan.app'
            local.parent.mkdir(exist_ok=True)
            if local.exists():
                shutil.rmtree(local)
            shutil.copytree(app, local)
        else:
            with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(stage.rglob('*')):
                    if path.is_file():
                        archive.write(path, path.relative_to(stage))
    print(output)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('platform', choices=('macos', 'windows', 'linux'))
    parser.add_argument('arch')
    args = parser.parse_args()
    package(args.binary.resolve(), args.platform, args.arch)
