#!/bin/sh
# Перегенерировать patches/ из веток los-tv рабочего дерева.
# Запускать на сборочной VM, где лежит ./patches этого репозитория.
#
#   ./scripts/export-patches.sh [путь-к-дереву]
set -e

TREE=${1:-$HOME/android/los-tv-23}
HERE=$(cd "$(dirname "$0")/.." && pwd)

PROJECTS="
bootable/aaropa
bootable/recovery
build/soong
build/release
system/core
frameworks/base
packages/apps/TvSettings
device/lineage/sepolicy
packages/modules/Bluetooth
packages/providers/ContactsProvider
system/apex
frameworks/av
external/stagefright-plugins
external/skia
external/mesa3d
external/drmfb-composer
external/XMP-Toolkit-SDK
external/google-highway
packages/modules/StatsD
system/extras
device/generic/x86_64_tv
system/sepolicy
device/google/atv
hardware/interfaces
"

rm -rf "$HERE/patches"
mkdir -p "$HERE/patches"
: > "$HERE/patches/series"

for p in $PROJECTS; do
    [ -d "$TREE/$p" ] || { echo "skip $p"; continue; }
    out="$HERE/patches/$p"
    mkdir -p "$out"
    git -C "$TREE/$p" format-patch -1 --no-signature -o "$out" los-tv >/dev/null
    f=$(ls "$out"/*.patch | head -1)
    printf '%s\t%s\n' "$p" "${f#$HERE/}" >> "$HERE/patches/series"
    echo "ok $p"
done

echo "patches обновлены"
