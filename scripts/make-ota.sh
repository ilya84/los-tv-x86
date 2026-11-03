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

set -o pipefail

TREE=${TREE:-$HOME/android/los-tv-23}
LUNCH_TARGET=lineage_x86_64_tv
LUNCH_VARIANT=trunk_staging
LUNCH_TYPE=userdebug

cd "$TREE"

export TOP="$TREE"
source build/envsetup.sh >/dev/null 2>&1
lunch "$LUNCH_TARGET" "$LUNCH_VARIANT" "$LUNCH_TYPE" || { echo "!! lunch failed"; exit 1; }

echo "### 1/3 target-files"
m target-files-package || { echo "!! target-files failed"; exit 1; }

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

"$TREE/out/host/linux-x86/bin/ota_from_target_files" -v \
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
