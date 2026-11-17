#!/bin/sh
# Package a built gooswan binary (gooswan, or gooswan.exe on Windows)
# into the distribution zip gooswan-<platform>-<arch>.zip: the binary
# README.md, notices and the bundled GUI font.
set -e
cd "$(dirname "$0")/.."
bin=$1
platform=$2
arch=$3
name=$(basename "$bin")
tmp=$(mktemp -d)
cp "$bin" "$tmp/$name"
chmod +x "$tmp/$name"
cp README.md "$tmp/README.md"
cp THIRD_PARTY_NOTICES.md "$tmp/THIRD_PARTY_NOTICES.md"
mkdir -p "$tmp/assets/fonts"
cp assets/fonts/MPLUS1p-Regular.ttf assets/fonts/OFL.txt "$tmp/assets/fonts/"
(cd "$tmp" && zip -q -r -X "gooswan-$platform-$arch.zip" "$name" README.md THIRD_PARTY_NOTICES.md assets)
mv "$tmp/gooswan-$platform-$arch.zip" .
rm -rf "$tmp"
echo "gooswan-$platform-$arch.zip"
