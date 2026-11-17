#!/bin/sh
# Check the core on its own (scripts/check_core.sh) and lint every entry
# point (scripts/lint.sh: no goose check warnings), then build the
# harness (tools/sst) and the frontend (app/gooswan). The same script
# runs on Linux, macOS and Windows (Git Bash).
# With --test, also run the full regression battery. Expects the
# project-local Goose compiler (downloaded on first use).
set -e
cd "$(dirname "$0")/.."
sh ./scripts/check_core.sh
sh ./scripts/lint.sh
sh ./scripts/goose.sh build tools/sst.goose
sh ./scripts/goose.sh build app/gooswan.goose
if [ "$1" = "--test" ]; then sh ./scripts/run_tests.sh; fi
