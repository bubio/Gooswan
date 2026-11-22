"""Shared release paths, documents, and ZIP layout."""
from pathlib import Path
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
RELEASES = ROOT / 'dist/releases'
DOCUMENTS = ('README.md', 'THIRD_PARTY_NOTICES.md', 'docs/user-guide.md')
WRAPPER_FILES = (*DOCUMENTS, 'licenses/OFL.txt')


def version():
    value = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value):
        raise ValueError('VERSION must contain major.minor.patch')
    return value


def copy_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def documents(folder):
    for name in DOCUMENTS:
        copy_file(ROOT / name, folder / name)
    copy_file(ROOT / 'assets/fonts/OFL.txt', folder / 'licenses/OFL.txt')


def archive(stage, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as target:
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                target.write(path, path.relative_to(stage))
    print(output)
    return output
