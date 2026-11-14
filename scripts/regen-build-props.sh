#!/bin/bash
# regen-build-props.sh — force regeneration of every partition build.prop.
#
# Why: Soong's build_prop modules declare out/build_date.txt as an order-only
# dependency, so changing the build date/number does not dirty their outputs.
# On incremental builds product/system_ext (and sometimes vendor/odm) keep the
# previous ro.build.version.incremental. Removing the generated files forces
# the next `m target-files-package` (or `m systemimage`) to regenerate them.
#
# Usage (on the build VM):
#   bash ~/los-tv-project/scripts/regen-build-props.sh
#   TREE=~/android/los-tv-23 PRODUCT_OUT=~/android/los-tv-23/out/target/product/x86_64_tv \
#       bash ~/los-tv-project/scripts/regen-build-props.sh
#
# make-ota.sh calls this automatically; set SKIP_BUILD_PROP_REGEN=1 to bypass.

set -u

TREE=${TREE:-$HOME/android/los-tv-23}
PRODUCT_OUT=${PRODUCT_OUT:-$TREE/out/target/product/x86_64_tv}
SOONG_INTERMEDIATES="$TREE/out/soong/.intermediates/build/soong"

parts=(system product system_ext vendor odm vendor_dlkm odm_dlkm system_dlkm ramdisk)
removed=0

for part in "${parts[@]}"; do
  case "$part" in
    system)
      installed="$PRODUCT_OUT/system/build.prop"
      ;;
    vendor)
      installed="$PRODUCT_OUT/system/vendor/build.prop"
      ;;
    ramdisk)
      installed="$PRODUCT_OUT/ramdisk/system/etc/ramdisk/build.prop"
      ;;
    *)
      installed="$PRODUCT_OUT/system/$part/etc/build.prop"
      ;;
  esac

  intermediate="$SOONG_INTERMEDIATES/$part-build.prop/android_common/build.prop"

  for f in "$installed" "$intermediate"; do
    if [ -e "$f" ]; then
      rm -f "$f" || {
        echo "!! не удалось удалить $f" >&2
        exit 1
      }
      removed=$((removed + 1))
    fi
  done
done

# x86 system.mk creates a merged top-level build.prop used by the system image.
rm -f "$PRODUCT_OUT/build.prop" && removed=$((removed + 1))

echo "build.prop: удалено $removed сгенерированных файлов; они будут пересозданы следующей сборкой"
