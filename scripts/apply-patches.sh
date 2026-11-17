#!/bin/sh
# Применить патч-стек los-tv к синхронизированному дереву LineageOS.
#
#   ./scripts/apply-patches.sh /path/to/los-tv-tree
#
# Строки series сгруппированы по проекту. Для каждого проекта:
#   * у каждого патча читается строка `From <hash>` из mail-заголовка;
#   * если hash нулевой, такого коммита нет в проекте или он НЕ предок
#     HEAD — патч применяется;
#   * если коммит уже есть в истории HEAD — пропускается ТОЛЬКО этот
#     патч (например, device tree из публичной ветки уже содержит 0001,
#     но 0002–0006 всё равно применяются);
#   * все оставшиеся патчи проекта применяются одним `git am -3`, чтобы
#     второй патч проекта не конфликтовал сам с собой.
#
# Никакого project-level skip по наличию любого `los-tv:` коммита нет:
# иначе device-tree 0002–0006 терялись бы на публичном дереве.
set -e

ROOT=${1:-.}
HERE=$(cd "$(dirname "$0")/.." && pwd)
SERIES="$HERE/patches/series"

[ -f "$SERIES" ] || { echo "нет $SERIES" >&2; exit 1; }

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT HUP INT TERM

# Уникальные проекты в порядке первого появления в series.
awk -F '\t' 'NF >= 2 && $1 != "" && $1 !~ /^#/ { if (!seen[$1]++) print $1 }' \
    "$SERIES" > "$LIST"

while IFS= read -r proj; do
    [ -n "$proj" ] || continue
    if [ ! -d "$ROOT/$proj" ]; then
        echo "skip $proj (нет каталога)"
        continue
    fi

    if [ -d "$ROOT/$proj/.git/rebase-apply" ]; then
        echo "СТОП: в $proj уже идёт git am (rebase-apply); завершите или прервите его" >&2
        exit 1
    fi

    patches=""
    count=0
    already=0

    while IFS="$(printf '\t')" read -r p patch; do
        [ "$p" = "$proj" ] || continue
        [ -n "$patch" ] || continue

        path="$HERE/$patch"
        if [ ! -f "$path" ]; then
            echo "СТОП: нет файла $path" >&2
            exit 1
        fi

        hash=$(sed -n 's/^From \([0-9a-f]\{40\}\).*/\1/p' "$path" | head -n 1)
        if [ -n "$hash" ] && [ "$hash" != "0000000000000000000000000000000000000000" ]; then
            if git -C "$ROOT/$proj" cat-file -e "$hash^{commit}" 2>/dev/null &&
               git -C "$ROOT/$proj" merge-base --is-ancestor "$hash" HEAD 2>/dev/null; then
                echo "  skip $(basename "$path") (коммит $(printf '%.12s' "$hash") уже в HEAD)"
                already=$((already + 1))
                continue
            fi
        fi

        # Повторный bootstrap: git am создаёт новый коммит, поэтому исходный
        # From-хеш после применения уже не предок HEAD.  Если патч уже
        # применён, обратный apply проходит (per-patch, не project-level).
        if git -C "$ROOT/$proj" apply -R --check "$path" 2>/dev/null; then
            echo "  skip $(basename "$path") (патч уже применён)"
            already=$((already + 1))
            continue
        fi

        # Fallback для патчей, поверх которых уже легли следующие патчи
        # проекта: обратный apply не проходит, сверяем точный subject
        # (уже без [PATCH]).  Длинный subject в mail-файле свёрнут на
        # несколько строк с ведущим пробелом — разворачиваем.
        subject=$(awk '
            /^Subject:/ {
                s = $0
                sub(/^Subject: /, "", s)
                sub(/^\[PATCH[^]]*\] /, "", s)
                while ((getline line) > 0) {
                    if (line ~ /^[ \t]/) { sub(/^[ \t]+/, " ", line); s = s line }
                    else break
                }
                print s
                exit
            }
        ' "$path" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ -n "$subject" ] &&
           git -C "$ROOT/$proj" log --format=%s -n 5000 HEAD 2>/dev/null | grep -Fxq "$subject"; then
            echo "  skip $(basename "$path") (коммит с тем же subject уже в HEAD)"
            already=$((already + 1))
            continue
        fi

        patches="$patches $path"
        count=$((count + 1))
    done < "$SERIES"

    if [ "$count" -eq 0 ]; then
        echo "== $proj: все $already патч(ей) уже в истории"
        continue
    fi

    echo "== $proj ($count к применению, $already уже в HEAD)"
    # shellcheck disable=SC2086
    git -C "$ROOT/$proj" am -3 $patches
done < "$LIST"

echo "готово"
