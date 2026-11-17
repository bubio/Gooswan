#!/bin/sh
# Native release ZIPs in dist/releases/; Linux produces deb/rpm/AppImage ZIPs.
# Run on the same OS as the input binary.
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <binary> macos|windows|linux <arch>" >&2
    exit 2
fi
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) exec python scripts/package_app.py "$@" ;;
    *) exec python3 scripts/package_app.py "$@" ;;
esac
