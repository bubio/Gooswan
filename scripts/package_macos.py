"""Build and sign a native macOS app bundle."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from package_common import ROOT, RELEASES, copy_file, documents


def package_macos(binary, release, arch):
    output = RELEASES / f'gooswan-{release}-macos-{arch}.zip'
    with tempfile.TemporaryDirectory(prefix='gooswan-package-') as temp:
        folder = Path(temp) / 'Gooswan'
        documents(folder)
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
        output.parent.mkdir(parents=True, exist_ok=True)
        output.unlink(missing_ok=True)
        # ditto preserves the signed app's metadata and Unix file modes.
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(folder), str(output)], check=True)
    print(output)
    return [output]
