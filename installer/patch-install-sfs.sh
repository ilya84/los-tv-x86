#!/bin/bash
# patch-install-sfs.sh — применяет los-tv оверлей к инсталлятору Calamares
# (bootable/aaropa/iso/install.sfs). Запускать НА СБОРОЧНОЙ VM (нужны
# unsquashfs/mksquashfs). По умолчанию только проверяет (MODE=check).
#
#   MODE=check  — что за файл сейчас в дереве, что изменит оверлей
#   MODE=apply  — бэкап оригинала, unsquashfs → оверлей → mksquashfs → проверки
#
# Переменные:
#   SFS      — путь к install.sfs (по умолчанию дерево на VM)
#   OVERLAY  — каталог оверлея (по умолчанию /tmp/opencode/installer-overlay)
#   BASE_MD5 — md5 исходного install.sfs (защита от наложения на другую версию)
#   FORCE=1  — перепатчить, даже если маркер уже есть
#   ALLOW_OTHER_BASE=1 — разрешить другую базовую версию
#
# Что меняет (см. data/2026-10-22-installer-calamares-analysis.txt):
#   * make-ab.conf: initrd 20 → 16 МиБ (фиксированный initrd шага 45);
#   * welcome.conf: requiredStorage 4.0 → 24.0 ГиБ (A/B-раскладка);
#   * 10_blissos: Recovery (+ignore_first_eth), выбор слота, меню разрешения,
#     tvres-переменные и set default=0;
#   * bootcfg/main.py: копирует tvres.cfg/tvres-menu.cfg/kmsglog-menu.cfg
#     в /boot/grub цели; если страницы options нет — в cmdline `quiet`;
#   * gen-img/gen-fstab: без страницы dataimg создаётся каталог data (не .img);
#   * settings.conf: убраны страницы «Additional options» и data.img;
#   * usr/share/calamares/los-tv/: tvres + kmsglog-menu.cfg;
#   * 10_blissos: галочка kmsg-лога в Advanced (default on, grubenv);
#   * usr/bin/aaropa-calamares: убран zenity-диалог выбора загрузчика
#     (GRUB/rEFInd/None); всегда GRUB, efiBootLoader принудительно "grub";
#   * удалены rEFInd (etc/refind.d, usr/share/refind, refind-* в /usr/sbin,
#     refind-conf/refind-postconf) и no-bootloader — неподдерживаемые ветки.
set -uo pipefail

MODE="${MODE:-check}"
SFS="${SFS:-$HOME/android/los-tv-23/bootable/aaropa/iso/install.sfs}"
OVERLAY="${OVERLAY:-/tmp/opencode/installer-overlay}"
BASE_MD5="${BASE_MD5:-4ef2af1cb15edcf08efd3f1392f47581}"
FORCE="${FORCE:-0}"
ALLOW_OTHER_BASE="${ALLOW_OTHER_BASE:-0}"
MARKER="${MARKER:-$HOME/android/los-tv-23/bootable/aaropa/install.sfs.patched}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/install-sfs-backup}"

FAIL=0
hdr() { echo; echo "=== $1 ==="; }
ok()  { echo "  ok  $1"; }
bad() { echo "  !!  $1"; FAIL=$((FAIL+1)); }
die() { echo "СТОП: $1"; exit 2; }

# py_check — проверка синтаксиса python без создания __pycache__ (иначе он
# попадёт в оверлей и в образ при cp -a), плюс поиск неопределённых глобальных
# имён (symtable): py_compile ловит синтаксис, но не NameError вроде
# забытого sys_prefix (инцидент 2026-10-26: установка падала на bootcfg).
py_check() {
  python3 - "$1" <<'PY'
import builtins
import symtable
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()
compile(src, path, "exec")

st = symtable.symtable(src, path, "exec")
top = set(st.get_identifiers())
bad = []

def walk(tbl):
    for sym in tbl.get_symbols():
        name = sym.get_name()
        if (sym.is_global() and sym.is_referenced()
                and name not in top and not hasattr(builtins, name)):
            bad.append((tbl.get_name(), name))
    for child in tbl.get_children():
        walk(child)

walk(st)
if bad:
    for scope, name in bad:
        print("undefined global: %s (in %s)" % (name, scope), file=sys.stderr)
    sys.exit(1)
PY
}

[ -f "$SFS" ] || die "нет $SFS"
[ -d "$OVERLAY" ] || die "нет каталога оверлея $OVERLAY"

# Корневые пути внутри оверлея (для проверки/списка).
FILES=(
  "etc/calamares/scripts/10_blissos"
  "etc/calamares/modules/make-ab.conf"
  "etc/calamares/modules/bootcfg.conf"
  "usr/lib/x86_64-linux-gnu/calamares/modules/bootcfg/main.py"
  "usr/lib/x86_64-linux-gnu/calamares/modules/gen-img/main.py"
  "usr/lib/x86_64-linux-gnu/calamares/modules/gen-fstab/main.py"
  "etc/calamares/settings.conf"
  "usr/share/calamares/los-tv/tvres.cfg"
  "usr/share/calamares/los-tv/tvres-menu.cfg"
  "usr/share/calamares/los-tv/kmsglog-menu.cfg"
  "usr/local/bin/los-tv-loghttp"
  "etc/xdg/autostart/los-tv-loghttp.desktop"
  "usr/bin/aaropa-calamares"
)

# Удаляем из образа неподдерживаемые загрузчики: враппер aaropa-calamares
# больше не предлагает rEFInd/None (см. оверлей), а сами файлы rEFInd и
# скрипты no-bootloader/refind-* не нужны и только путают.
DELETE=(
  "etc/refind.d"
  "usr/share/refind"
  "usr/sbin/mvrefind"
  "usr/sbin/refind-install"
  "usr/sbin/refind-mkdefault"
  "usr/sbin/refind-sb-healthcheck"
  "etc/calamares/scripts/refind-conf"
  "usr/share/calamares/scripts/refind-postconf"
  "usr/share/calamares/scripts/no-bootloader"
)

hdr "0. Текущий install.sfs"
cur=$(md5sum "$SFS" | cut -d' ' -f1)
echo "  файл:  $SFS"
echo "  размер: $(stat -c%s "$SFS") Б"
echo "  md5:   $cur"
if [ -f "$MARKER" ]; then
  echo "  маркер: $(cat "$MARKER")"
fi
marked_md5=$(sed -n 's/.*md5=\([0-9a-f]\{32\}\).*/\1/p' "$MARKER" 2>/dev/null | head -1)
if [ "$cur" = "$BASE_MD5" ]; then
  ok "это известный исходный install.sfs"
elif [ -n "$marked_md5" ] && [ "$cur" = "$marked_md5" ]; then
  ok "файл уже пропатчен (md5 совпадает с маркером)"
else
  echo "  ВНИМАНИЕ: md5 не совпадает ни с базовым $BASE_MD5, ни с маркером (другая версия?)"
fi

hdr "1. Оверлей: файлы и синтаксис"
for f in "${FILES[@]}"; do
  if [ -f "$OVERLAY/$f" ]; then
    ok "$f $(stat -c%s "$OVERLAY/$f") Б md5 $(md5sum "$OVERLAY/$f" | cut -d' ' -f1)"
  else
    bad "нет $OVERLAY/$f"
  fi
done
bash -n "$OVERLAY/etc/calamares/scripts/10_blissos" 2>/dev/null \
  && ok "10_blissos: bash -n" || bad "10_blissos: синтаксис"
[ -x "$OVERLAY/etc/calamares/scripts/10_blissos" ] \
  && ok "10_blissos: исполняемый" || bad "10_blissos: нет +x (grub-mkconfig пропустит скрипт!)"
[ -x "$OVERLAY/usr/local/bin/los-tv-loghttp" ] \
  && ok "los-tv-loghttp: исполняемый" || bad "los-tv-loghttp: нет +x"
sh -n "$OVERLAY/usr/local/bin/los-tv-loghttp" 2>/dev/null \
  && ok "los-tv-loghttp: sh -n" || bad "los-tv-loghttp: синтаксис"
[ -x "$OVERLAY/usr/bin/aaropa-calamares" ] \
  && ok "aaropa-calamares: исполняемый" || bad "aaropa-calamares: нет +x"
sh -n "$OVERLAY/usr/bin/aaropa-calamares" 2>/dev/null \
  && ok "aaropa-calamares: sh -n" || bad "aaropa-calamares: синтаксис"
grep -q -- "--radiolist" "$OVERLAY/usr/bin/aaropa-calamares" \
  && bad "aaropa-calamares: остался диалог выбора загрузчика" \
  || ok "aaropa-calamares: диалог выбора убран"
grep -q "export BOOTLOADER=grub" "$OVERLAY/usr/bin/aaropa-calamares" \
  && ok "aaropa-calamares: принудительный GRUB" || bad "aaropa-calamares: нет BOOTLOADER=grub"
py_check "$OVERLAY/usr/lib/x86_64-linux-gnu/calamares/modules/bootcfg/main.py" 2>/dev/null \
  && ok "bootcfg/main.py: синтаксис + глобальные имена" || bad "bootcfg/main.py: синтаксис/имена"
py_check "$OVERLAY/usr/lib/x86_64-linux-gnu/calamares/modules/gen-img/main.py" 2>/dev/null \
  && ok "gen-img/main.py: синтаксис + глобальные имена" || bad "gen-img/main.py: синтаксис/имена"
grep -q '"disabled": True' "$OVERLAY/usr/lib/x86_64-linux-gnu/calamares/modules/gen-img/main.py" \
  && ok "gen-img: без страницы dataimg создаёт каталог data" || bad "gen-img: нет fallback dataimg"
py_check "$OVERLAY/usr/lib/x86_64-linux-gnu/calamares/modules/gen-fstab/main.py" 2>/dev/null \
  && ok "gen-fstab/main.py: синтаксис + глобальные имена" || bad "gen-fstab/main.py: синтаксис/имена"
grep -q '"disabled": True' "$OVERLAY/usr/lib/x86_64-linux-gnu/calamares/modules/gen-fstab/main.py" \
  && ok "gen-fstab: fstab.android с каталогом data" || bad "gen-fstab: нет fallback dataimg"
if find "$OVERLAY" \( -name __pycache__ -o -name '*.pyc' \) | grep -q .; then
  bad "в оверлее есть __pycache__/*.pyc (попадут в образ)"
fi

hdr "2. Что сейчас внутри install.sfs (до правки)"
for f in "${FILES[@]}"; do
  if unsquashfs -cat "$SFS" "/$f" >/tmp/sfs-cur.$$ 2>/dev/null; then
    echo "  $f → md5 $(md5sum /tmp/sfs-cur.$$ | cut -d' ' -f1)"
  else
    echo "  $f → НЕТ в образе"
  fi
done
rm -f /tmp/sfs-cur.$$
unsquashfs -cat "$SFS" "/etc/calamares/modules/welcome.conf" 2>/dev/null \
  | grep -E "requiredStorage:" | sed 's/^/  welcome.conf: /'

if [ "$MODE" != "apply" ]; then
  echo
  echo "Режим check: ничего не менял. Для применения: MODE=apply bash $0"
  exit $((FAIL > 0))
fi

hdr "3. Проверки перед применением"
if [ -f "$MARKER" ] && [ "$FORCE" != "1" ]; then
  die "маркер уже есть (файл патчился). Перепатчить: FORCE=1"
fi
if [ "$cur" != "$BASE_MD5" ] && [ "$ALLOW_OTHER_BASE" != "1" ]; then
  die "базовый md5 другой ($cur). Если это осознанно: ALLOW_OTHER_BASE=1"
fi
[ "$FAIL" -eq 0 ] || die "оверлей/проверки не прошли"

hdr "4. Бэкап оригинала"
mkdir -p "$BACKUP_DIR"
BK="$BACKUP_DIR/install.sfs.base-${cur:0:12}"
if [ -f "$BK" ]; then
  ok "бэкап уже есть: $BK"
else
  cp -p "$SFS" "$BK" && ok "бэкап: $BK" || die "не удалось сделать бэкап"
fi
echo "$cur  $SFS" > "$BACKUP_DIR/install.sfs.base.md5"

hdr "5. Распаковка и оверлей"
TMP="$(mktemp -d /tmp/opencode/sfs-patch.XXXXXX)" || die "mktemp"
trap 'rm -rf "$TMP"' EXIT
# umask 000 — иначе unsquashfs срежет групповые/мировые биты записи у файлов
# вроде /tmp/trusted.gpg.d/* (в оригинале 0666).
( umask 000; unsquashfs -q -d "$TMP" "$SFS" >/dev/null 2>&1 ) || die "unsquashfs не смог распаковать"
ok "распаковано в $TMP ($(du -sh "$TMP" | cut -f1))"

# unsquashfs без root сбрасывает setuid/setgid/sticky (например,
# usr/lib/dbus-1.0/dbus-daemon-launch-helper). Восстанавливаем по листингу
# оригинала; uid/gid затем выставит fakeroot перед mksquashfs (см. шаг 7).
unsquashfs -ll "$SFS" 2>/dev/null | awk '$1 ~ /[sStT]/ {print $1, $NF}' \
  | while read -r mode path; do
      rel=${path#squashfs-root/}
      [ -e "$TMP/$rel" ] || continue
      case "${mode:3:1}" in s|S) chmod u+s "$TMP/$rel" ;; esac
      case "${mode:6:1}" in s|S) chmod g+s "$TMP/$rel" ;; esac
      case "${mode:9:1}" in t|T) chmod +t "$TMP/$rel" ;; esac
      echo "  восстановлен режим $mode $rel"
    done

cp -a "$OVERLAY"/. "$TMP"/ || die "копирование оверлея не удалось"
ok "оверлей скопирован"

# Удаление неподдерживаемых загрузчиков (rEFInd/None) из распакованного дерева.
# -L нужен для битых симлинков (refind-install -> удалённый usr/share/refind).
for p in "${DELETE[@]}"; do
  if [ -e "$TMP/$p" ] || [ -L "$TMP/$p" ]; then
    rm -rf "$TMP/$p" && ok "удалено: $p"
  fi
done

# welcome.conf: точечная правка (файл большой, оверлеить целиком не хотим).
WELCOME="$TMP/etc/calamares/modules/welcome.conf"
if [ -f "$WELCOME" ]; then
  sed -i -E 's/^([[:space:]]*requiredStorage:[[:space:]]*)4\.0[[:space:]]*$/\124.0/' "$WELCOME"
  if grep -qE 'requiredStorage:[[:space:]]*24\.0' "$WELCOME"; then
    ok "welcome.conf: requiredStorage 24.0"
  else
    bad "welcome.conf: не нашёл requiredStorage 4.0 (проверьте вручную)"
  fi
else
  bad "нет welcome.conf"
fi

hdr "6. Проверка распакованного дерева"
for f in "${FILES[@]}"; do
  a=$(md5sum "$OVERLAY/$f" | cut -d' ' -f1)
  b=$(md5sum "$TMP/$f" 2>/dev/null | cut -d' ' -f1)
  [ "$a" = "$b" ] && ok "$f" || bad "$f: md5 $b != $a"
done
bash -n "$TMP/etc/calamares/scripts/10_blissos" && ok "10_blissos в дереве: bash -n" || bad "10_blissos в дереве: синтаксис"
[ -x "$TMP/etc/calamares/scripts/10_blissos" ] && ok "10_blissos в дереве: исполняемый" || bad "10_blissos в дереве: нет +x"
[ -x "$TMP/usr/local/bin/los-tv-loghttp" ] && ok "los-tv-loghttp в дереве: исполняемый" || bad "los-tv-loghttp в дереве: нет +x"
sh -n "$TMP/usr/local/bin/los-tv-loghttp" && ok "los-tv-loghttp в дереве: sh -n" || bad "los-tv-loghttp в дереве: синтаксис"
py_check "$TMP/usr/lib/x86_64-linux-gnu/calamares/modules/bootcfg/main.py" \
  && ok "bootcfg в дереве: py_compile" || bad "bootcfg в дереве: синтаксис"
[ "$FAIL" -eq 0 ] || die "проверки распакованного дерева не прошли"

hdr "7. Перепаковка squashfs (zstd, 128K, с сохранением владельцев)"
NEW="$SFS.new"
rm -f "$NEW"
command -v fakeroot >/dev/null 2>&1 || die "нужен fakeroot: без него нельзя сохранить gid messagebus у dbus-daemon-launch-helper"
HELPER="$TMP/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
# ВАЖНО (регрессия 2026-10-25): mksquashfs -all-root делал helper root:root.
# Он должен остаться root:messagebus (gid 101) с режимом 4754, иначе
# dbus-daemon (пользователь messagebus) не может его запустить, KPMcore
# получает 0 устройств и Calamares пишет "There are no partitions to install on."
# fakeroot позволяет выставить uid/gid на время mksquashfs без root.
fakeroot sh -c "
  chown -R 0:0 '$TMP' &&
  chown 0:101 '$HELPER' &&
  chmod 4754 '$HELPER' &&
  mksquashfs '$TMP' '$NEW' -noappend -comp zstd -b 131072 -no-progress -quiet
" || die "mksquashfs (fakeroot) не удался"
ok "новый образ: $(stat -c%s "$NEW") Б"

hdr "8. Проверка нового образа"
for f in "${FILES[@]}"; do
  a=$(md5sum "$OVERLAY/$f" | cut -d' ' -f1)
  b=$(unsquashfs -cat "$NEW" "/$f" 2>/dev/null | md5sum | cut -d' ' -f1)
  [ "$a" = "$b" ] && ok "$f" || bad "$f: в образе md5 $b"
done
unsquashfs -cat "$NEW" "/etc/calamares/modules/welcome.conf" 2>/dev/null \
  | grep -qE 'requiredStorage:[[:space:]]*24\.0' && ok "welcome.conf: 24.0" || bad "welcome.conf в образе"
unsquashfs -cat "$NEW" "/etc/calamares/scripts/10_blissos" 2>/dev/null | grep -q "Slot selection (manual)" \
  && ok "10_blissos: наши пункты на месте" || bad "10_blissos: пунктов нет"
unsquashfs -cat "$NEW" "/etc/calamares/scripts/10_blissos" 2>/dev/null | grep -q "androidboot.los_tv_kmsglog" \
  && ok "10_blissos: kmsg-лог в cmdline" || bad "10_blissos: нет kmsg-лога"
if unsquashfs -cat "$NEW" "/etc/calamares/settings.conf" 2>/dev/null \
     | grep -Eq '^[[:space:]]*-[[:space:]]*(options|dataimg)[[:space:]]*$'; then
  bad "settings.conf: страницы options/dataimg не убраны"
else
  ok "settings.conf: options/dataimg убраны"
fi
unsquashfs -cat "$NEW" "/usr/lib/x86_64-linux-gnu/calamares/modules/gen-img/main.py" 2>/dev/null \
  | grep -q '"disabled": True' && ok "gen-img в образе: fallback dataimg" || bad "gen-img в образе: нет fallback"
unsquashfs -cat "$NEW" "/usr/lib/x86_64-linux-gnu/calamares/modules/gen-fstab/main.py" 2>/dev/null \
  | grep -q '"disabled": True' && ok "gen-fstab в образе: fallback dataimg" || bad "gen-fstab в образе: нет fallback"
unsquashfs -cat "$NEW" "/usr/bin/aaropa-calamares" 2>/dev/null | grep -q "export BOOTLOADER=grub" \
  && ok "aaropa-calamares в образе: GRUB принудительно" || bad "aaropa-calamares в образе: нет BOOTLOADER=grub"
unsquashfs -cat "$NEW" "/usr/bin/aaropa-calamares" 2>/dev/null | grep -q -- "--radiolist" \
  && bad "aaropa-calamares в образе: остался диалог" || ok "aaropa-calamares в образе: диалога нет"
am=$(unsquashfs -ll "$NEW" 2>/dev/null | awk '$NF == "squashfs-root/usr/bin/aaropa-calamares" {print $1}')
case "$am" in
  -rwx*) ok "aaropa-calamares в образе: исполняемый ($am)" ;;
  *)     bad "aaropa-calamares в образе: режим $am (нужен rwx)" ;;
esac
# Листинг в файл: с `set -o pipefail` связка `unsquashfs | grep -q` даёт
# SIGPIPE (grep выходит раньше), и проверка ложно считает путь отсутствующим.
unsquashfs -l "$NEW" 2>/dev/null > "/tmp/sfs-list.$$"
left=0
for p in "${DELETE[@]}"; do
  if grep -qE "^squashfs-root/${p}(/|$)" "/tmp/sfs-list.$$"; then
    bad "в образе остался удалённый путь: $p"
    left=1
  fi
done
rm -f "/tmp/sfs-list.$$"
[ "$left" = 0 ] && ok "rEFInd/None удалены из образа (${#DELETE[@]} путей)"
m=$(unsquashfs -ll "$NEW" 2>/dev/null | awk '$NF == "squashfs-root/etc/calamares/scripts/10_blissos" {print $1}')
case "$m" in
  -rwx*) ok "10_blissos в образе: исполняемый ($m)" ;;
  *)     bad "10_blissos в образе: режим $m (нужен rwx)" ;;
esac
# Критично для Calamares: helper должен остаться root:messagebus (0/101, 4754),
# иначе D-Bus не запустит его и KPMcore снова увидит 0 устройств.
hl=$(unsquashfs -lln "$NEW" 2>/dev/null | awk '$NF == "squashfs-root/usr/lib/dbus-1.0/dbus-daemon-launch-helper" {print $1, $2}')
case "$hl" in
  "-rwsr-xr-- 0/101") ok "dbus-daemon-launch-helper: $hl" ;;
  *) bad "dbus-daemon-launch-helper: '$hl' (ожидалось '-rwsr-xr-- 0/101')" ;;
esac
# Метаданные (режим/uid/gid) существующих файлов не должны меняться; в diff
# допустимы только добавленные строки ("> ..."). Удалённые намеренно пути
# (DELETE) исключаем из оригинального листинга, иначе они выглядят как "<".
unsquashfs -lln "$SFS" 2>/dev/null | awk '{print $1, $2, $NF}' | sort > "/tmp/sfs-meta-orig.$$"
unsquashfs -lln "$NEW" 2>/dev/null | awk '{print $1, $2, $NF}' | sort > "/tmp/sfs-meta-new.$$"
printf '%s\n' "${DELETE[@]}" > "/tmp/sfs-del.$$"
awk 'NR==FNR { del[$0]=1; next } {
  p=$NF; sub(/^squashfs-root\//, "", p)
  for (d in del) {
    if (p == d || index(p, d "/") == 1) next
  }
  print
}' "/tmp/sfs-del.$$" "/tmp/sfs-meta-orig.$$" > "/tmp/sfs-meta-orig-f.$$"
if diff "/tmp/sfs-meta-orig-f.$$" "/tmp/sfs-meta-new.$$" | grep -q '^<'; then
  bad "метаданные существующих файлов изменились:"
  diff "/tmp/sfs-meta-orig-f.$$" "/tmp/sfs-meta-new.$$" | grep '^[<>]' | sed 's/^/      /' | head -20
else
  ok "метаданные существующих файлов не изменились (DELETE учтены)"
fi
rm -f "/tmp/sfs-meta-orig.$$" "/tmp/sfs-meta-new.$$" "/tmp/sfs-meta-orig-f.$$" "/tmp/sfs-del.$$"
# Особые биты (setuid/setgid/sticky) должны совпасть с оригиналом: без root
# unsquashfs их сбрасывает, мы восстанавливаем вручную.
unsquashfs -ll "$SFS" 2>/dev/null | awk '$1 ~ /[sStT]/ {print $1, $NF}' | sort > "/tmp/sfs-spec-orig.$$"
unsquashfs -ll "$NEW" 2>/dev/null | awk '$1 ~ /[sStT]/ {print $1, $NF}' | sort > "/tmp/sfs-spec-new.$$"
if diff -q "/tmp/sfs-spec-orig.$$" "/tmp/sfs-spec-new.$$" >/dev/null; then
  ok "особые биты совпадают ($(wc -l < "/tmp/sfs-spec-orig.$$") шт.)"
else
  bad "особые биты отличаются от оригинала:"
  diff "/tmp/sfs-spec-orig.$$" "/tmp/sfs-spec-new.$$" | sed 's/^/      /'
fi
rm -f "/tmp/sfs-spec-orig.$$" "/tmp/sfs-spec-new.$$"
[ "$FAIL" -eq 0 ] || { rm -f "$NEW"; die "новый образ не прошёл проверки"; }

hdr "9. Установка на место"
new_md5=$(md5sum "$NEW" | cut -d' ' -f1)
mv -f "$NEW" "$SFS" || die "не удалось заменить install.sfs"
printf 'los-tv patched %s  md5=%s  base=%s  overlay=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$new_md5" "$cur" "$(cd "$OVERLAY" && find . -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)" \
  > "$MARKER"
chmod 644 "$SFS"
ok "готово: $SFS"
echo "  размер: $(stat -c%s "$SFS") Б"
echo "  md5:    $new_md5"
echo "  маркер: $MARKER"
echo "  бэкап:  $BK"
echo
echo "Дальше: пересобрать ISO (install.sfs попадает в него копированием iso/)."
