#!/bin/sh
# Project-local Goose. Update the version and all checksums together.
# Downloads only on first use; never falls back to a compiler on PATH.
set -eu
goose_version=v2026.4
project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# Keep compiler caches local too, unless the caller explicitly chooses a cache.
export GOOSE_HOME="${GOOSE_HOME:-$project_root/.goose}"
case "$(uname -s)/$(uname -m)" in
    Linux/x86_64)
        asset=linux-x64.tar.gz
        checksum=559ad7572df89fcd1273512d8679528bcdf876c252ec1f31608d3808b24125b3 ;;
    Darwin/arm64)
        asset=macos-arm64.tar.gz
        checksum=8ef0b5a864a719bd095b8376bed069d0edc77a0ce8f3cb9d59fdf87291a3a922 ;;
    Darwin/x86_64)
        asset=macos-x64.tar.gz
        checksum=471beefd5787ff96b68c1a059ac4de0973a86a540efda9f2b084b540b5d73db0 ;;
    MINGW*/x86_64|MSYS*/x86_64|CYGWIN*/x86_64)
        asset=windows-x64.zip
        checksum=87ceb0ff2394e0ac4154b6c6b865c084cadbf236558cc956b114f37d6e619cdb ;;
    *) echo "Unsupported Goose platform: $(uname -s)/$(uname -m)" >&2; exit 1 ;;
esac
archive="goose-${goose_version}-${asset}"
case "$asset" in
    *.zip) release_dir=${archive%.zip}; compiler=goose.exe ;;
    *) release_dir=${archive%.tar.gz}; compiler=goose ;;
esac
toolchain_root="$project_root/.tools/goose/$goose_version"
install_dir="$toolchain_root/$release_dir"
if [ ! -x "$install_dir/$compiler" ]; then
    mkdir -p "$toolchain_root"
    staging=$(mktemp -d "$toolchain_root/.download.XXXXXX")
    trap 'rm -rf "$staging"' EXIT
    trap 'exit 1' HUP INT TERM
    echo "Downloading Goose $goose_version ($asset)..." >&2
    curl --fail --location --retry 3 --connect-timeout 15 --max-time 300 \
        --output "$staging/$archive" \
        "https://github.com/aardappel/goose/releases/download/$goose_version/$archive"
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$staging/$archive")
    else
        actual=$(shasum -a 256 "$staging/$archive")
    fi
    actual=${actual%% *}
    if [ "$actual" != "$checksum" ]; then
        echo "Goose checksum mismatch: expected $checksum, got $actual" >&2
        exit 1
    fi
    case "$asset" in
        *.zip) unzip -q "$staging/$archive" -d "$staging" ;;
        *) tar -xzf "$staging/$archive" -C "$staging" ;;
    esac
    if [ ! -x "$staging/$release_dir/$compiler" ]; then
        echo "Goose archive does not contain $release_dir/$compiler" >&2
        exit 1
    fi
    mv "$staging/$release_dir" "$install_dir"
    rm -rf "$staging"
    trap - EXIT HUP INT TERM
fi
exec "$install_dir/$compiler" "$@"
