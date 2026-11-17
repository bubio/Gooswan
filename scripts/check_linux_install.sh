#!/bin/bash
# Run only in a disposable root container; CI bind-mounts the checkout read-only.
set -euo pipefail
cd "$(dirname "$0")/.."
format=${1:?Usage: check_linux_install.sh deb|rpm|appimage}
case "$format" in deb|rpm|appimage) ;; *) exit 2 ;; esac
if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y python3 desktop-file-utils mesa-vulkan-drivers
else
    dnf install -y python3 desktop-file-utils mesa-vulkan-drivers cpio
fi
export GOOSE_GFX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
shopt -s nullglob
archives=(release-assets/gooswan-*-linux-x86_64-"$format".zip)
[ "${#archives[@]}" -eq 1 ] || { echo "Expected one $format archive" >&2; exit 1; }
if [ "$format" = appimage ]; then
    # SDL's dlopen dependencies are normally provided by a desktop installation.
    if command -v apt-get >/dev/null; then
        apt-get install -y libx11-6 libxcursor1 libxi6 libxrandr2 libxkbcommon0 libwayland-client0 libasound2 libpulse0 libvulkan1
    else
        dnf install -y libX11 libXcursor libXi libXrandr libxkbcommon libwayland-client alsa-lib pulseaudio-libs vulkan-loader
    fi
    python3 scripts/check_package.py "${archives[0]}" linux --arch x86_64 --smoke
else
    python3 scripts/check_package.py "${archives[0]}" linux --arch x86_64 --smoke --install
fi
