#!/bin/bash
# Продолжение прерванной полной сборки iso_img с ТЕМ ЖЕ окружением soong.
# Запуск: setsid nohup ~/run-iso-full.sh > ~/iso-full.log 2>&1 < /dev/null &
set -u
. /home/kacnep/iso-build-env.sh
cd /home/kacnep/android/los-tv-23 || exit 1
/home/kacnep/android/los-tv-23/build/soong/bin/m iso_img
rc=$?
echo "#### iso-full finished rc=$rc at $(date -Is) ####"
