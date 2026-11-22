#!/bin/sh
# Check the core on its own (scripts/check_core.sh) and lint every entry
# point (scripts/lint.sh: no goose check warnings), then build the
# harness (tools/sst) and the frontend (app/gooswan). The same script
# runs on Linux, macOS and Windows (Git Bash).
# With --test, also run the full regression battery. Expects the
# project-local Goose compiler (downloaded on first use).
set -e
cd "$(dirname "$0")/.."
# Match Swanium's deployment floor instead of inheriting the build host's SDK.
if [ "$(uname -s)" = Darwin ]; then
    export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.5}"
fi
sh ./scripts/check_core.sh
sh ./scripts/lint.sh
sh ./scripts/goose.sh build tools/sst.goose
sh ./scripts/goose.sh build tools/audio_test.goose
sh ./scripts/goose.sh build app/gooswan.goose
(
    cd app/link
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) CGO_ENABLED=0 go build -trimpath -ldflags="-H windowsgui" -o ../gooswan-link.exe ;;
        *) CGO_ENABLED=0 go build -trimpath -o ../gooswan-link ;;
    esac
    if [ "$1" = "--test" ]; then go test ./...; fi
)
if [ "$1" = "--test" ]; then sh ./scripts/run_tests.sh; fi
