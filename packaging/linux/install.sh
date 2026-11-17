#!/bin/sh
# Install this portable package for the current user; no sudo required.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
base=${XDG_DATA_HOME:-$HOME/.local/share}
mkdir -p "$HOME/.local/lib/gooswan" "$HOME/.local/bin" "$base/applications" "$base/icons/hicolor/256x256/apps"
cp -R gooswan assets docs README.md THIRD_PARTY_NOTICES.md "$HOME/.local/lib/gooswan/"
ln -sf "$HOME/.local/lib/gooswan/gooswan" "$HOME/.local/bin/gooswan"
cp assets/icons/gooswan.png "$base/icons/hicolor/256x256/apps/gooswan.png"
# Desktop launchers need an absolute executable, independent of the GUI's PATH.
python3 - "$HOME/.local/lib/gooswan/gooswan" "$base/applications/gooswan.desktop" <<'PY'
from pathlib import Path
import sys
path = sys.argv[1]
# Desktop Entry string escaping, followed by Exec quoted-argument escaping.
for char in ('\\', '"', '`', '$'):
    path = path.replace(char, '\\' + char)
path = path.replace('\\', '\\\\').replace('%', '%%')
source = Path('gooswan.desktop').read_text()
Path(sys.argv[2]).write_text(source.replace('Exec=gooswan', f'Exec="{path}"'))
PY
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$base/applications"; fi
echo "Installed Gooswan. Add $HOME/.local/bin to PATH for command-line use."
