#!/usr/bin/env bash
# bootstrap-tree.sh — подготовить свежесинхронизированное дерево los-tv к сборке.
#
# Запускать после `repo init && repo sync`, из клона los-tv-x86:
#   ./scripts/bootstrap-tree.sh ~/android/los-tv-23
#
# Скрипт идемпотентен: повторный запуск ничего не ломает и удобен после
# `m clean` (он заново создаёт симлинки meson/glslangValidator).
#
# Что делает:
#   1) применяет patches/series (scripts/apply-patches.sh);
#   2) скачивает недостающие prebuilt APK с проверкой sha256;
#   3) проверяет/докачивает initrd_lib и install.sfs (aaropa download.sh);
#   4) патчит install.sfs нашим оверлеем (installer/overlay);
#   5) подготавливает meson >= 1.4 и glslangValidator >= 12.2;
#   6) создаёт симлинки в out/host/linux-x86/bin.
#
# Опции:
#   --check              только проверить, ничего не менять/не скачивать
#   --no-prebuilts       не скачивать APK
#   --no-install-sfs     не патчить install.sfs
#   --no-tools           не ставить meson/glslang (считать, что они есть)
#   --allow-other-base   разрешить другую базу install.sfs
#   --install-deps       поставить недостающие Debian/Ubuntu-пакеты через sudo
#
# Переменные: TREE, LOS_TV_TOOLS (по умолчанию $HOME/android/tools),
#             JOBS (по умолчанию nproc), AAROPA_SOURCE (по умолчанию bliss).
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TREE="${TREE:-$HOME/android/los-tv-23}"
TOOLS="${LOS_TV_TOOLS:-$HOME/android/tools}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
AAROPA_SOURCE="${AAROPA_SOURCE:-bliss}"
EXPECTED_SFS_BASE="5786133db5f5bbc5b45c090482057e57"

CHECK=0
FETCH_PREBUILTS=1
PATCH_SFS=1
SETUP_TOOLS=1
ALLOW_OTHER_BASE=0
INSTALL_DEPS=0

log()  { printf '\n== %s\n' "$*"; }
ok()   { printf '  ok  %s\n' "$*"; }
warn() { printf '  !!  %s\n' "$*" >&2; }
die()  { printf 'СТОП: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --no-prebuilts) FETCH_PREBUILTS=0 ;;
        --no-install-sfs) PATCH_SFS=0 ;;
        --no-tools) SETUP_TOOLS=0 ;;
        --allow-other-base) ALLOW_OTHER_BASE=1 ;;
        --install-deps) INSTALL_DEPS=1 ;;
        -h|--help) usage ;;
        -*) die "unknown option: $1 (см. --help)" ;;
        *) TREE=$1 ;;
    esac
    shift
done

[ -f "$TREE/build/envsetup.sh" ] || die "не похоже на Android-дерево: $TREE"
[ -d "$TREE/device/generic/x86_64_tv" ] || die "нет device/generic/x86_64_tv в $TREE"
[ -d "$TREE/bootable/aaropa" ] || die "нет bootable/aaropa в $TREE"

# --- 0. Проверка хостовых команд -----------------------------------------
log "0. Хостовые зависимости"
need=(git curl python3 unzip zip mksquashfs unsquashfs fakeroot xorriso 7z
      sha256sum md5sum tar awk sed find)
missing=()
for c in "${need[@]}"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ "${#missing[@]}" -gt 0 ]; then
    printf '  нет: %s\n' "${missing[*]}"
    if [ "$INSTALL_DEPS" = "1" ]; then
        command -v sudo >/dev/null 2>&1 || die "нет sudo; поставьте пакеты вручную"
        sudo apt-get update
        sudo apt-get install -y git curl ca-certificates python3 unzip zip rsync bc \
            ccache flex bison g++ make cmake openjdk-17-jdk-headless \
            squashfs-tools fakeroot xorriso p7zip-full
    else
        die "поставьте недостающие пакеты (Debian/Ubuntu: --install-deps)"
    fi
fi
ok "базовые команды на месте"

# --- 1. Патчи -------------------------------------------------------------
log "1. Патчи los-tv"
if [ "$CHECK" = "1" ]; then
    warn "--check: apply-patches.sh не запускаю (он меняет дерево)"
else
    bash "$HERE/scripts/apply-patches.sh" "$TREE"
fi

# --- 2. Prebuilt APK ------------------------------------------------------
log "2. Prebuilt APK"
if [ "$FETCH_PREBUILTS" = "1" ]; then
    LOCK="$HERE/scripts/prebuilts.lock"
    BASE="$TREE/device/generic/x86_64_tv/prebuilt"
    [ -f "$LOCK" ] || die "нет $LOCK"
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/los-tv-prebuilts.XXXXXX")
    trap 'rm -rf "$TMPD"' EXIT
    while IFS=$'\t' read -r rel sha url; do
        case "$rel" in ''|\#*) continue ;; esac
        dest="$BASE/$rel"
        if [ -f "$dest" ]; then
            got=$(sha256sum "$dest" | awk '{print $1}')
            if [ "$got" = "$sha" ]; then
                ok "$rel (sha256 ok)"
                continue
            fi
            if [ "$CHECK" = "1" ]; then
                warn "$rel: sha256 не совпадает (нужен другой файл?)"
                continue
            fi
            die "$rel: sha256 не совпадает; удалите файл, чтобы скачать заново"
        fi
        if [ "$CHECK" = "1" ]; then
            warn "$rel: отсутствует"
            continue
        fi
        mkdir -p "$(dirname "$dest")"
        mkdir -p "$(dirname "$TMPD/$rel")"
        printf '  ..  качаю %s\n' "$rel"
        curl -L --fail --retry 3 --connect-timeout 20 --max-time 600 \
            -o "$TMPD/$rel" "$url" || die "не скачался $url"
        got=$(sha256sum "$TMPD/$rel" | awk '{print $1}')
        [ "$got" = "$sha" ] || die "$rel: sha256 после скачивания не совпал"
        mv "$TMPD/$rel" "$dest"
        ok "$rel (скачан)"
    done < "$LOCK"
else
    warn "--no-prebuilts: пропускаю"
fi

# --- 3. Aaropa: initrd_lib + install.sfs ---------------------------------
log "3. Aaropa (initrd_lib, install.sfs)"
AAROPA="$TREE/bootable/aaropa"
have_initrd=0
if [ -d "$AAROPA/initrd_lib" ] && find "$AAROPA/initrd_lib" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    have_initrd=1
fi
if [ "$have_initrd" = "1" ] && [ -s "$AAROPA/iso/install.sfs" ]; then
    ok "initrd_lib и install.sfs уже есть"
else
    if [ "$CHECK" = "1" ]; then
        warn "нет initrd_lib или iso/install.sfs; нужен bootable/aaropa/download.sh"
    else
        ( cd "$TREE" && AAROPA_SOURCE="$AAROPA_SOURCE" bash bootable/aaropa/download.sh ) \
            || die "aaropa download.sh завершился с ошибкой"
        [ -s "$AAROPA/iso/install.sfs" ] || die "после download.sh нет iso/install.sfs"
        ok "aaropa assets скачаны"
    fi
fi

if [ "$PATCH_SFS" = "1" ] && [ -s "$AAROPA/iso/install.sfs" ]; then
    PATCH="$HERE/scripts/patch-install-sfs.sh"
    [ -f "$PATCH" ] || PATCH="$HERE/installer/patch-install-sfs.sh"
    [ -f "$PATCH" ] || die "не найден patch-install-sfs.sh"
    cur=$(md5sum "$AAROPA/iso/install.sfs" | awk '{print $1}')
    marked=$(sed -n 's/.*md5=\([0-9a-f]\{32\}\).*/\1/p' "$AAROPA/install.sfs.patched" 2>/dev/null | head -1 || true)
    if [ -n "$marked" ] && [ "$cur" = "$marked" ]; then
        ok "install.sfs уже пропатчен ($cur)"
        MODE=check SFS="$AAROPA/iso/install.sfs" MARKER="$AAROPA/install.sfs.patched" \
            OVERLAY="$HERE/installer/overlay" TREE="$TREE" bash "$PATCH" >/dev/null \
            || die "install.sfs пропатчен, но проверка оверлея не прошла"
    elif [ "$cur" = "$EXPECTED_SFS_BASE" ]; then
        if [ "$CHECK" = "1" ]; then
            warn "install.sfs — чистая база, нужен MODE=apply"
        else
            MODE=apply SFS="$AAROPA/iso/install.sfs" MARKER="$AAROPA/install.sfs.patched" \
                OVERLAY="$HERE/installer/overlay" TREE="$TREE" BASE_MD5="$EXPECTED_SFS_BASE" \
                bash "$PATCH" || die "не удалось пропатчить install.sfs"
            ok "install.sfs пропатчен"
        fi
    elif [ "$ALLOW_OTHER_BASE" = "1" ]; then
        if [ "$CHECK" = "1" ]; then
            warn "install.sfs — другая база ($cur); --allow-other-base"
        else
            MODE=apply SFS="$AAROPA/iso/install.sfs" MARKER="$AAROPA/install.sfs.patched" \
                OVERLAY="$HERE/installer/overlay" TREE="$TREE" BASE_MD5="$cur" \
                ALLOW_OTHER_BASE=1 bash "$PATCH" || die "не удалось пропатчить install.sfs"
            ok "install.sfs пропатчен (другая база $cur)"
        fi
    else
        die "install.sfs base=$cur, ожидалась $EXPECTED_SFS_BASE; используйте --allow-other-base"
    fi
else
    warn "--no-install-sfs: install.sfs не патчу"
fi

# --- 4. meson / glslangValidator -----------------------------------------
log "4. meson и glslangValidator"
BIN="$TREE/out/host/linux-x86/bin"
version_ge() { [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }
meson_version() { "$1" --version 2>/dev/null | head -n1; }
glslang_version() { "$1" --version 2>/dev/null | sed -n 's/.*: *\([0-9][0-9.]*\).*/\1/p' | head -n1; }

ensure_meson() {
    local cand=""
    if [ -x "$BIN/meson" ]; then
        cand="$BIN/meson"
    fi
    if [ -z "$cand" ] && command -v meson >/dev/null 2>&1; then
        cand=$(command -v meson)
    fi
    if [ -n "$cand" ] && version_ge "$(meson_version "$cand")" "1.4.0"; then
        if [ "$cand" != "$BIN/meson" ]; then
            mkdir -p "$BIN"
            [ "$CHECK" = "1" ] || ln -sf "$cand" "$BIN/meson"
        fi
        ok "meson $(meson_version "$cand")"
        return
    fi
    if [ "$CHECK" = "1" ]; then
        warn "meson < 1.4 или отсутствует"
        return
    fi
    log "   ставлю meson 1.8.5 в $TOOLS"
    mkdir -p "$TOOLS"
    local dir="$TOOLS/meson-1.8.5" tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/meson.XXXXXX")
    curl -L --fail --retry 3 --connect-timeout 20 \
        -o "$tmp/meson.tar.gz" \
        https://github.com/mesonbuild/meson/releases/download/1.8.5/meson-1.8.5.tar.gz \
        || die "не скачался meson"
    rm -rf "$dir"
    mkdir -p "$dir"
    tar -xzf "$tmp/meson.tar.gz" -C "$dir" --strip-components=1
    cat > "$dir/meson" <<'SH'
#!/bin/bash
exec python3 "$(dirname "$0")/meson.py" "$@"
SH
    chmod +x "$dir/meson"
    rm -rf "$tmp"
    mkdir -p "$BIN"
    ln -sf "$dir/meson" "$BIN/meson"
    ok "meson $(meson_version "$BIN/meson")"
}

ensure_glslang() {
    local cand=""
    if [ -x "$BIN/glslangValidator" ]; then
        cand="$BIN/glslangValidator"
    fi
    if [ -z "$cand" ] && command -v glslangValidator >/dev/null 2>&1; then
        cand=$(command -v glslangValidator)
    fi
    if [ -n "$cand" ] && version_ge "$(glslang_version "$cand")" "12.2"; then
        if [ "$cand" != "$BIN/glslangValidator" ]; then
            mkdir -p "$BIN"
            [ "$CHECK" = "1" ] || ln -sf "$cand" "$BIN/glslangValidator"
        fi
        ok "glslangValidator $(glslang_version "$cand")"
        return
    fi
    if [ "$CHECK" = "1" ]; then
        warn "glslangValidator < 12.2 или отсутствует"
        return
    fi
    command -v cmake >/dev/null 2>&1 || die "для сборки glslang нужен cmake"
    command -v g++ >/dev/null 2>&1 || die "для сборки glslang нужен g++"
    log "   собираю glslang 14.3.0 в $TOOLS"
    mkdir -p "$TOOLS"
    local src="$TOOLS/glslang-14.3.0-src" build="$TOOLS/glslang-14.3.0-build"
    if [ ! -d "$src/.git" ]; then
        rm -rf "$src"
        git clone --depth 1 --branch 14.3.0 \
            https://github.com/KhronosGroup/glslang.git "$src" \
            || die "не склонировался glslang"
    fi
    cmake -S "$src" -B "$build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        >/dev/null || die "cmake configure glslang не прошёл"
    cmake --build "$build" --target glslangValidator -j"$JOBS" \
        || die "сборка glslang не прошла"
    mkdir -p "$BIN"
    ln -sf "$build/StandAlone/glslangValidator" "$BIN/glslangValidator"
    ok "glslangValidator $(glslang_version "$BIN/glslangValidator")"
}

if [ "$SETUP_TOOLS" = "1" ]; then
    ensure_meson
    ensure_glslang
else
    warn "--no-tools: пропускаю meson/glslang"
fi

# --- 5. Итог --------------------------------------------------------------
log "Готово"
echo "Дерево: $TREE"
echo "Дальше: cd $TREE && source build/envsetup.sh && lunch lineage_x86_64_tv trunk_staging userdebug && m iso_img"
echo "Подробности — data/2026-11-12-build-ota-recon.txt"
