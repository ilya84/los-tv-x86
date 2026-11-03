#!/bin/sh
# Применить патч-стек los-tv к синхронизированному дереву LineageOS.
#
#   ./scripts/apply-patches.sh /path/to/los-tv-x86
#
# Проекты, в которых уже есть коммит с темой "los-tv:", пропускаются
# (это актуально, если дерево устройства и bootable/aaropa взяты из наших
# форков, а не из upstream).
set -e

ROOT=${1:-.}
HERE=$(cd "$(dirname "$0")/.." && pwd)
SERIES="$HERE/patches/series"

[ -f "$SERIES" ] || { echo "нет $SERIES" >&2; exit 1; }

while IFS="$(printf '\t')" read -r proj patch; do
    [ -n "$proj" ] || continue
    if [ ! -d "$ROOT/$proj" ]; then
        echo "skip $proj (нет каталога)"
        continue
    fi
    if git -C "$ROOT/$proj" log -1 --format=%s 2>/dev/null | grep -q '^los-tv:'; then
        echo "skip $proj (уже los-tv)"
        continue
    fi
    echo "== $proj"
    git -C "$ROOT/$proj" am -3 "$HERE/$patch"
done < "$SERIES"

echo "готово"
