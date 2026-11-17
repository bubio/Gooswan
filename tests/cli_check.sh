#!/bin/sh
# CLI-only paths must exit without initializing graphics or settings.
set -eu
cd "$(dirname "$0")/.."
GOOSWAN_CONFIG_DIR=$(mktemp -d)
export GOOSWAN_CONFIG_DIR
trap 'rm -rf "$GOOSWAN_CONFIG_DIR"' EXIT
for option in --help -h; do
    out=$(./app/gooswan "$option")
    printf '%s\n' "$out" | grep -q '^Usage: gooswan '
    printf '%s\n' "$out" | grep -q -- '--help'
    if [ "$option" = --help ]; then
        help_out=$out
    else
        [ "$out" = "$help_out" ]
    fi
done
if out=$(./app/gooswan --unknown-option 2>&1); then
    echo "FAIL: unknown option succeeded" >&2
    exit 1
fi
printf '%s\n' "$out" | grep -q '^Unknown option: --unknown-option'
[ -z "$(ls -A "$GOOSWAN_CONFIG_DIR")" ]
echo "CLI help and unknown option: pass"
