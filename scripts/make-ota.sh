#!/bin/bash
# make-ota.sh — собрать полный A/B OTA-пакет для lineage_x86_64_tv.
#
# Запускать НА VM (kacnep@192.168.5.162), из любого каталога:
#   bash ~/los-tv-project/scripts/make-ota.sh        # или скопировать туда
#
# Что делает:
#   1) m target-files-package (инкрементально; пересобирает ext4 system.img);
#   2) при необходимости собирает хост-инструмент ota_from_target_files;
#   3) генерирует ПОЛНЫЙ OTA (без -i), подпись — штатный testkey;
#   4) печатает размер/хэши и проверяет целостность.
#
# Дерево не правится. Обход грабли с dynamic_partitions_info.txt:
# у статических разделов этого файла нет, а инструмент при virtual_ab_cow_version=3
# сам понижает версию до 2 и лезет в несуществующий файл. Даём ему info_dict
# из распакованной копии target-files с virtual_ab_cow_version=2.
#
# Подробный разбор: data/2026-10-19-ota-full-build.txt
# step45: добавлена проверка фиксированного размера initrd (16 МиБ).
# 2026-11-14: перед сборкой удаляются все сгенерированные build.prop
# (system/product/system_ext/vendor/odm/...), иначе Soong оставляет старый
# incremental; после сборки значения сверяются по всем разделам.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

TREE=${TREE:-$HOME/android/los-tv-23}
PRODUCT_OUT="$TREE/out/target/product/x86_64_tv"
LUNCH_TARGET=lineage_x86_64_tv
LUNCH_VARIANT=trunk_staging
LUNCH_TYPE=userdebug

verify_build_props() {
  local out="$1"
  local ref_file="$out/system/build.prop"
  local ref rc=0 f val

  if [ ! -f "$ref_file" ]; then
    echo "!! нет $ref_file" >&2
    return 1
  fi

  ref=$(grep -m1 -E '^ro\.([a-z_]+\.)?build\.version\.incremental=' "$ref_file" \
    | cut -d= -f2-)
  if [ -z "$ref" ]; then
    echo "!! не найден ro.build.version.incremental в $ref_file" >&2
    return 1
  fi

  for f in \
    "$out/system/build.prop" \
    "$out/system/product/etc/build.prop" \
    "$out/system/system_ext/etc/build.prop"; do
    if [ ! -f "$f" ]; then
      echo "!! нет $f" >&2
      rc=1
    fi
  done

  while IFS= read -r f; do
    val=$(grep -m1 -E '^ro\.([a-z_]+\.)?build\.version\.incremental=' "$f" \
      | cut -d= -f2-)
    if [ -n "$val" ] && [ "$val" != "$ref" ]; then
      echo "!! $f: incremental=$val, ожидалось $ref" >&2
      rc=1
    fi
  done < <(find "$out/system" -name build.prop -type f | sort)

  [ "$rc" -eq 0 ] && echo "build.prop: все разделы согласованы (incremental=$ref)"
  return "$rc"
}

cd "$TREE"

export TOP="$TREE"
source build/envsetup.sh >/dev/null 2>&1
lunch "$LUNCH_TARGET" "$LUNCH_VARIANT" "$LUNCH_TYPE" || { echo "!! lunch failed"; exit 1; }

if [ "${SKIP_BUILD_PROP_REGEN:-0}" != "1" ]; then
  echo "### 0/3 build.prop: форсированная перегенерация"
  TREE="$TREE" PRODUCT_OUT="$PRODUCT_OUT" \
    bash "$SCRIPT_DIR/regen-build-props.sh" || { echo "!! build.prop regen failed"; exit 1; }
fi

echo "### 1/3 target-files"
m target-files-package || { echo "!! target-files failed"; exit 1; }
verify_build_props "$PRODUCT_OUT" || { echo "!! build.prop mismatch"; exit 1; }
if ! grep -q '^lineage.updater.uri=' "$PRODUCT_OUT/system/build.prop"; then
  echo "!! ВНИМАНИЕ: lineage.updater.uri не задан; Updater будет использовать"
  echo "!! официальный сервер LineageOS. Для atv.kacnep.ru передайте"
  echo "!! LOS_TV_OTA_URI=https://atv.kacnep.ru/x86_64_tv.json."
fi

TF="$TREE/out/target/product/x86_64_tv/obj/PACKAGING/target_files_intermediates/${LUNCH_TARGET}-target_files.zip"
OTA="$TREE/out/target/product/x86_64_tv/${LUNCH_TARGET}-ota-full.zip"
[ -f "$TF" ] || { echo "!! нет target-files: $TF"; exit 1; }

echo "### 2/3 хост-инструмент"
if [ ! -x "$TREE/out/host/linux-x86/bin/ota_from_target_files" ]; then
  m ota_from_target_files || { echo "!! ota tool failed"; exit 1; }
fi

echo "### 3/3 OTA"
WORK=$(mktemp -d /tmp/tf-ota.XXXXXX)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

unzip -q "$TF" -d "$WORK"
sed -i 's/^virtual_ab_cow_version=.*/virtual_ab_cow_version=2/' "$WORK/META/misc_info.txt"
grep -q '^virtual_ab_cow_version=2$' "$WORK/META/misc_info.txt"

# los-tv step45: initrd должен быть фиксированного размера 16 МиБ
# (INITRD_FIXED_SIZE в bootable/aaropa/Android.mk), чтобы payload-раздел
# initrd всегда влезал в /mnt/cdrom/initrd_{a,b}.img на устройстве.
ISZ=$(stat -c%s "$WORK/RADIO/initrd.img" 2>/dev/null || echo 0)
if [ "$ISZ" != "16777216" ]; then
  echo "!! RADIO/initrd.img = $ISZ байт, ожидалось 16777216 (16 МиБ, step45)."
  echo "!! Пересоберите: m initrdimage && m target-files-package"
  exit 1
fi
echo "initrd: RADIO/initrd.img = $ISZ байт (16 МиБ, OK)"

# Подпись OTA. По умолчанию: releasekey из vendor/lineage-priv/keys, если он
# есть; иначе штатный testkey. Для перехода со старого testkey на новые ключи
# первый OTA нужно подписать старым ключом:
#   OTA_KEY=$TREE/build/make/target/product/security/testkey bash make-ota.sh
OTA_KEY="${OTA_KEY:-auto}"
if [ "$OTA_KEY" = "auto" ]; then
  if [ -f "$TREE/vendor/lineage-priv/keys/releasekey.pk8" ]; then
    OTA_KEY="$TREE/vendor/lineage-priv/keys/releasekey"
  else
    OTA_KEY="$TREE/build/make/target/product/security/testkey"
  fi
fi
[ -f "$OTA_KEY.pk8" ] || { echo "!! нет ключа OTA: $OTA_KEY.pk8"; exit 1; }
echo "OTA key: $OTA_KEY"

"$TREE/out/host/linux-x86/bin/ota_from_target_files" -v -k "$OTA_KEY" \
  --extracted_input_target_files "$WORK" \
  "$TF" "$OTA"

rm -rf "$WORK"
trap - EXIT

echo "### готово"
ls -l "$OTA"
md5sum "$OTA"
sha256sum "$OTA"
if unzip -t "$OTA" >/dev/null 2>&1; then echo "zip: OK"; else echo "!! zip: FAIL"; exit 1; fi

# разделы в payload (имена в protobuf идут вплотную к служебным байтам,
# поэтому ищем без привязки к началу строки)
{ unzip -p "$OTA" payload.bin 2>/dev/null | head -c 200000 | strings -n 3 |
  grep -oE 'initrd|kernel|ramdisk-recovery|system' | sort -u; } || true
