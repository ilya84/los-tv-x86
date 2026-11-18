# Сборка

Проверено 2026-11-18 на Debian 12 (`lineage-build`, `kacnep@192.168.5.162`).
Текущие стенды: `intel` (H81M-E, `_a` `1794703929`, security `2025-11-05`) —
production, `e3000n` (AMD E2, `_b` `1794960573`, security `2026-11-01`;
`_a` `1794919314` — boot-only fallback) — тестовый. Оба на release-keys,
SELinux Enforcing. Release-конфиг 23.2 — **`bp4a`**; security patch —
**`2026-11-01`** (upstream `vendor/lineage` `1a4ed79a`, локальный pin
`2026-10-01` удалён из series). Release-дерево — чистое
`~/android/los-tv-23-clean` (`@los-23-tv-clean`).

## 0. Быстрый старт

```sh
# 1. Вспомогательный репозиторий (патчи, qcom-манифест, bootstrap)
git clone https://github.com/ilya84/los-tv-x86 ~/los-tv-x86

# 2. Дерево + qcom-исключение ДО первого sync
mkdir -p ~/android/los-tv-23-clean && cd ~/android/los-tv-23-clean
repo init -u https://github.com/ilya84/lineage_bass_android.git -b los-tv-x86-23.2
mkdir -p .repo/local_manifests
cp ~/los-tv-x86/manifest/05-remove-qcom.xml .repo/local_manifests/
repo sync -j8

# 3. Подготовить дерево одним скриптом
~/los-tv-x86/scripts/bootstrap-tree.sh ~/android/los-tv-23-clean

# 4. Собрать ISO
source build/envsetup.sh
lunch lineage_x86_64_tv bp4a userdebug
m iso_img
```

`los-tv-x86-23.2` — release-ветка/тег манифеста (upstream LineageOS +
`05-modified.xml`). Ветка `lineage-23.2` остаётся исторической; на неё
`repo init` даст старый manifest без upstream-переключения. Если ветка
ещё не опубликована, используйте локальный `~/manifests-23.2` или
`manifest.xml` из release bundle.

`manifest/05-remove-qcom.xml` — 23.2-специфичный список из 42 qcom-проектов
(94 пути). Для 24.0 его нужно перегенерировать: имена/пути могут измениться.

`bootstrap-tree.sh` идемпотентен: после `m clean` достаточно повторить его.
`--check` — только проверить, `--install-deps` — доустановить Debian-пакеты.

Для воспроизводимой сборки после первого bootstrap и первого `lunch`
выставляйте `SKIP_AG_DOWNLOADS=true`: иначе `device/generic/x86_64_tv/vendorsetup.sh`
при каждом `lunch` запускает `download_ids.sh`/`download_toolchain.sh`/
`download_sof-firmware.sh`/`download_wireless-regdb.sh` и может менять
tracked-файлы (`ids/pci.ids`, `ids/usb.ids`) и состав prebuilts из сети.

```sh
export SKIP_AG_DOWNLOADS=true
```

На уже пропатченном дереве **не запускать `repo sync`** — он перетирает
локальные коммиты и патчи.

## 1. Что нужно

- Linux x86_64 (Debian 12 / Ubuntu 24.04), 16+ ГБ RAM, 300+ ГБ диска.
- AOSP-пакеты: `openjdk`, `clang`, `ninja`, `bc`, `rsync`, `zip`, `unzip`,
  `ccache`, `flex`, `bison`, `g++`, `make`, `python3`, `curl`, `git`;
  `repo` в `PATH`.
- Для установщика: `unsquashfs`/`mksquashfs`, `7z`, `fakeroot`, `xorriso`.
- Дерево LineageOS 23.2 (Android 16). Чистая сборка — 8–11 часов,
  инкрементальная — минуты.

## 2. Манифест и исходники

```sh
mkdir -p ~/android/los-tv-23-clean && cd ~/android/los-tv-23-clean
repo init -u https://github.com/ilya84/lineage_bass_android.git -b los-tv-x86-23.2
mkdir -p .repo/local_manifests
cp ~/los-tv-x86/manifest/05-remove-qcom.xml .repo/local_manifests/
repo sync -j8
```

`05-remove-qcom.xml` убирает ARM-платформенные qcom HAL’ы, которые не
нужны x86-ТВ; без него чистый sync притащит их обратно. Результат
release-манифеста: **1123 проекта, qcom = 0**. Для 24.0 список надо
перегенерировать.

Manifest release-дерева: `default`/тег `los-tv-x86-23.2` (локальный
`~/manifests-23.2` — `e6ec738`, 3 коммита впереди
`origin/default` `03e103d`). 20 изменённых LineageOS-проектов
переведены на remote `lineage-upstream` (`android-x86/05-modified.xml`),
остальные — `los-tv-x86`/`ilya84`/`ag-github`; drmfb — `ag-github`.
Полный resolved manifest — в release bundle (`manifest.xml`,
`repo manifest -r`).

В манифесте (`android-x86/04-custom.xml`) наши проекты:

- `device/generic/x86_64_tv` — дерево устройства (форк BlissOS x86_64_tablet);
- `bootable/aaropa` — initrd и установщик;
- `external/libburn`, `external/libisofs`, `external/libisoburn` — сборка ISO.

> Если используете свои форки — поправьте `remote`/`name` в
> `04-custom.xml` (или положите свой local manifest в `.repo/local_manifests`).

## 3. Bootstrap чистого дерева (рекомендуется)

```sh
[ -d ~/los-tv-x86 ] || git clone https://github.com/ilya84/los-tv-x86 ~/los-tv-x86
~/los-tv-x86/scripts/bootstrap-tree.sh ~/android/los-tv-23-clean
```

Скрипт:

1. применяет `patches/series` (per-patch skip: если `From <hash>` уже
   является предком HEAD, пропускается только этот патч; остальные
   применяются одним `git am -3`);
2. скачивает недостающие APK по `scripts/prebuilts.lock` с проверкой sha256;
3. проверяет/докачивает `bootable/aaropa/initrd_lib` и `iso/install.sfs`
   через `download.sh`;
4. патчит `install.sfs` оверлеем из `installer/overlay`;
5. ставит meson 1.8.5 и glslang 14.3.0, если системных версий недостаточно;
6. создаёт симлинки `out/host/linux-x86/bin/meson` и
   `glslangValidator`.

`patches/series` включает `kernel/x86/zenith` — memfd-ashmem shim и
`CONFIG_KSU` off. Без шима Android 16 userspace не открывает `/dev/ashmem`,
и система не загружается; если патч ядра не применился, сборку не запускать.

Скрипт ничего не делает разрушительного; повторный запуск безопасен.

## 4. Ручной путь (если не используется bootstrap)

```sh
./scripts/apply-patches.sh ~/android/los-tv-23-clean
```

Скрипт читает `patches/series` и применяет `git am -3` к `frameworks/base`,
`system/core`, `bootable/recovery`, `build/soong`, `frameworks/av`,
`external/*`, `TvSettings`, sepolicy, Bluetooth и т.д. Пропуск —
per-patch: если коммит `From <hash>` уже в HEAD, пропускается только он;
project-level skip по `los-tv:` удалён. `patches/series` — 56 строк,
`vendor/lineage` pin отсутствует (upstream `2026-11-01`).
Патчи для `device/generic/x86_64_tv` и `bootable/aaropa` в серии есть, но
при использовании наших форков не нужны.

Сторонние APK (в git их нет; bootstrap качает сам):

- `F-Droid.apk` — <https://f-droid.org/repo/org.fdroid.fdroid_2000051.apk>
- `microG-GmsCore.apk` — microG 0.3.17.252432,
  sha256 `e5e6cba078bdec812b5450599350e5c1a12c8b7438da5bf77123af170f8c1a35`
- `user/JellyfinTV.apk` — F-Droid 0.19.10 (191099),
  sha256 `8510a517c99927076082917f41bf306dd7a2546c59d492dd11bde18d6e2e4628`
- `user/VLC-x86_64.apk` — VideoLAN 3.7.1 x86_64,
  sha256 `4646633ede40c4784c5584087cffc5c60cc45b16966ae0b36cedd784d7c4a11e`

Play Store в базовый образ не входит; его APK пользователь кладёт в
`/sdcard/los-tv-proprietary` и ставит через add-on.

## 5. Сборка ISO

```sh
cd ~/android/los-tv-23-clean
source build/envsetup.sh
export SKIP_AG_DOWNLOADS=true
lunch lineage_x86_64_tv bp4a userdebug
get_build_var PLATFORM_SECURITY_PATCH      # 2026-11-01
LOS_TV_OTA_URI=https://atv.kacnep.ru/x86_64_tv.json m systemimage
LOS_TV_OTA_URI=https://atv.kacnep.ru/x86_64_tv.json m iso_img
```

Результат: `out/target/product/x86_64_tv/lineage-23.2-*-x86_64_tv.iso`
(ISO-инсталлятор с GRUB/Calamares; имя возвращено к историческому
LineageOS-формату вместо upstream `bass-lineout-*`). Перед `m iso_img`
проверьте top-level `system.img` — он должен быть 6 ГБ и содержать
`ro.build.version.incremental=1794960573`, security `2026-11-01`,
`ro.build.tags=release-keys`; иначе `m systemimage` обязателен.

`install.sfs` (Calamares) собирается отдельно и патчится оверлеем из
`installer/` (`installer/patch-install-sfs.sh`, режим `MODE=apply`). Перед
`m iso_img` он должен лежать в `bootable/aaropa/iso/install.sfs`.
Bootstrap (раздел 3) делает это сам; после `m clean` достаточно повторить
bootstrap — он вернёт симлинки `out/host/linux-x86/bin/meson` и
`glslangValidator`.

Финальный `install.sfs` (helper `b5a8b76`/тег `los-tv-x86-23.2`):
`md5 0367c129de084573354300fed35cf5e2`, permissive во всех
recovery/auto-addon пунктах `10_blissos`; `make-ab.conf` — system 8192,
initrd 16, recovery 64 МиБ. Recovery permissive обеспечивается
`system/core` patch `0004` (`IsRecoveryMode()`) + recovery `0003`/`0004`;
normal boot остаётся Enforcing.

## 6. Сборка full OTA

```sh
TREE=/home/kacnep/android/los-tv-23-clean \
LOS_TV_OTA_URI=https://atv.kacnep.ru/x86_64_tv.json \
SKIP_AG_DOWNLOADS=true \
  bash ~/los-tv-x86/scripts/make-ota.sh
```

Скрипт собирает `target-files-package`, генерирует полный A/B OTA
(`out/target/product/x86_64_tv/lineage_x86_64_tv-ota-full.zip`), проверяет
размер initrd (16 МиБ) и печатает хэши. Установка — `adb reboot sideload` +
`adb sideload zip` либо через Updater по воздуху (см. §7). `TREE=`
обязателен, если скрипт запускается из другого дерева/каталога.

Release-конфиг скрипт берёт из `vendor/lineage/vars/aosp_target_release`
(сейчас `bp4a`); переопределение — `LUNCH_VARIANT=trunk_staging`. Без
`SKIP_AG_DOWNLOADS=true` `vendorsetup.sh` при `lunch` может обновить
`ids/pci.ids`/`ids/usb.ids` и prebuilts из сети, поэтому для релизной
сборки используйте `SKIP_AG_DOWNLOADS=true`. Текущая release-сборка
23.2 — `1794960573` (security `2026-11-01`); опубликованная до неё —
`1794703929`. Тестовые bp4a `1794711917`/`1794919314` не публиковались.

Перед сборкой `make-ota.sh` вызывает `scripts/regen-build-props.sh`: он
удаляет сгенерированные build.prop всех разделов (system/product/
system_ext/vendor/odm/...) и Soong-intermediates, потому что Soong
объявляет `out/build_date.txt` order-only зависимостью и на инкрементальной
сборке оставляет старый `ro.build.version.incremental`. После сборки
`make-ota.sh` сверяет incremental по всем найденным build.prop. Обход:
`SKIP_BUILD_PROP_REGEN=1`.

Прямой `m otapackage` не использовать: он даёт
`lineage_x86_64_tv-ota.zip`, а не `-ota-full.zip`, и упирается в отсутствие
`META/dynamic_partitions_info.txt` у статических разделов; скрипт обходит
это через `--extracted_input_target_files`.

После OTA add-on восстанавливает компоненты автоматически: приложение
`addon-autorestore` создаёт маркер, GRUB грузит recovery, установщик ставит
компоненты на месте в активный слот (1–3 минуты).

## 7. Сетевой OTA

В образе есть LineageOS Updater, `update_engine` и A/B; пункт
«Обновление системы» открывается из TV Settings. В официальных сборках
запечён `lineage.updater.uri=https://atv.kacnep.ru/x86_64_tv.json`;
проверка и установка работают по HTTPS, сервер отдаёт `Range: bytes`.

Сборка с URL (свой сервер или локальный тест):

```make
ifneq ($(LOS_TV_OTA_URI),)
PRODUCT_PROPERTY_OVERRIDES += lineage.updater.uri=$(LOS_TV_OTA_URI)
endif
```

```sh
LOS_TV_OTA_URI=https://atv.kacnep.ru/x86_64_tv.json m iso_img
```

Генератор JSON из OTA:

```sh
./scripts/make-ota-index.py \
  --url-prefix https://atv.kacnep.ru/ota \
  --out /srv/ota/x86_64_tv.json \
  out/target/product/x86_64_tv/lineage_x86_64_tv-ota-full.zip
```

Сервер должен отдавать JSON и OTA по HTTPS с поддержкой `Range` (nginx/Caddy).
`datetime` должен быть новее текущего `ro.build.date.utc`, `type` — совпадать
с `ro.lineage.releasetype` (`UNOFFICIAL`). Схема JSON — в
`packages/apps/Updater/README.md`. Текущий сервер: `atv.kacnep.ru`, Caddy →
`/srv/ota`, файлы `/ota/*` и `/iso/*` с `immutable`.

В настройках Updater есть расписание (daily/weekly/monthly, минуты шагом 5,
catch-up ~12 минут) и категория «Автоматическая установка»: автоустановка
новой сборки после периодической проверки и, опционально, автоматическая
перезагрузка после `UPDATED_NEED_REBOOT`. Обе опции по умолчанию выключены;
без периодической проверки автоустановка недоступна. На metered-сети и при
низком заряде автоустановка пропускается.

При публикации давайте OTA уникальное имя (`...-<incremental>.zip`) и
обновляйте JSON: Caddy/nginx для `/ota/*` обычно ставят `immutable`, и
перезапись того же URL может оставить у клиента старый файл. После
публикации проверьте `200`, `Content-Length` и `Range: bytes=0-99` → `206`.

Если собираете с собственными ключами (`vendor/lineage-priv/keys`), в
`keys.mk` нужна строка:

```make
PRODUCT_MAINLINE_BLUETOOTH_SEPOLICY_DEV_CERTIFICATES := vendor/lineage-priv/keys
```

Иначе для `com.android.bt` `build/make/core/config.mk` возьмёт AOSP-ключ
`build/make/target/product/security/bluetooth.x509.pem`,
`plat_mac_permissions.xml` не совпадёт с подписью Bluetooth.apk, и
`com.android.bluetooth` не запустится (`seinfo=default`, zygote abort).

Официальные сборки подписаны собственными `release-keys` (CN `los-tv-x86`),
`otacerts` содержит `releasekey.x509.pem`. `testkey` используется только
для перехода со старых сборок (`OTA_KEY=.../testkey`).

## 8. Своя подпись (userdebug)

`userdebug` и подпись не связаны: можно оставить отладочную сборку и
подписывать её своими ключами. Ключи хранятся вне git, в
`vendor/lineage-priv/keys/` (LineageOS автоматически подхватывает
`vendor/lineage-priv/keys/keys.mk`).

```sh
mkdir -p vendor/lineage-priv/keys
cd vendor/lineage-priv/keys
for k in releasekey platform shared media networkstack bluetooth nfc sdk_sandbox; do
  ../../../development/tools/make_key "$k" \
    '/C=RU/O=los-tv/OU=Android/CN=los-tv/emailAddress=admin@kacnep.ru'
done
chmod 600 ./*.pk8
cat > keys.mk <<'EOF'
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
EOF
```

`make_key` спросит пароль (можно пустой) и создаст `.pk8` + `.x509.pem`.
Приватные ключи обязательно сохранить в надёжном месте: потеря =
невозможность выпускать обновления.

Сборка остаётся userdebug:

```sh
source build/envsetup.sh
lunch lineage_x86_64_tv bp4a userdebug
m iso_img
```

`make-ota.sh` сам выберет `releasekey`, если он есть; для перехода со
старого `testkey` первый OTA нужно подписать старым ключом:

```sh
OTA_KEY=$PWD/build/make/target/product/security/testkey bash scripts/make-ota.sh
```

После установки такого переходного OTA на устройстве появится новый
`otacerts`, и следующие OTA можно подписывать уже `releasekey`. Если
раздавать новый ISO/slot-образ напрямую — переходный OTA не нужен.

Ориентиры по времени: генерация ключей — 5–10 минут; первый
инкрементальный rebuild из-за смены сертификатов — обычно 1–3 часа;
полный clean — 8–11 часов; пересборка OTA — 10–20 минут.

## 9. Установка

1. Записать ISO на USB (`dd`/Rufus).
2. Загрузиться с USB, установить на диск (Calamares).
3. Первая загрузка: база (microG, F-Droid, Jellyfin, VLC).
4. Для платного DRM/Play Store: положить APK в `/sdcard/los-tv-proprietary`
   и выбрать в GRUB `Recovery → Установить проприетарные компоненты`
   (или открыть плитку в Android).

## 10. Текущее состояние и ограничения

Проверено 2026-11-18:

- `intel` — production, `_a` build `1794703929` (release-keys,
  security `2025-11-05`), Enforcing, RTP 5004, add-on и YouTube 7.31.301,
  BT-пульт. Production ещё не переведён на bp4a; не трогать в freeze.
- `e3000n` — тестовый стенд, `_b` build `1794960573` (bp4a,
  security `2026-11-01`), active; `_a` `1794919314` — boot-only fallback
  (RTP error). Enforcing, RTP 5006, add-on auto, BT/пульт, recovery
  sideload проверены. Рабочий `_b` `1794800321` сохранён вне слотов.
- Release 23.2: OTA `1794960573` (1 758 217 372 Б, md5
  `bcf8c3a099c18a29d924047a8c9612a4`, sha256
  `f90f78fe…a55d`), security `2026-11-01`, releasekey, Enforcing;
  ISO `lineage-23.2-20261118-UNOFFICIAL-x86_64_tv.iso` (см. release
  bundle и `RELEASE.md`). Публикация — после `PUBLISH`.
- Оба стенда: userdebug, SELinux Enforcing, release-keys, без шифрования
  данных; `system.img` — 6,0 ГБ (content margin ~2,26 ГБ).
- Recovery permissive (system/core `0004` + recovery `0003`/`0004`);
  normal boot Enforcing. Installer передаёт
  `androidboot.selinux=permissive` для recovery-пунктов.
- Чистая установка ISO: **hardware e3000n PASS 2026-11-19** —
  Calamares, GPT/слоты/GRUB, первый boot, `_a` clean + `_b` add-on,
  Enforcing, recovery permissive, RTP 5006/тон, BT, add-on. QEMU/OVMF
  для Android boot не показателен (виртуальный GPU: `avc denied`
  graphics.allocator, system_server без `activity`).
- Обязательность SSE4.2 не подтверждена (в работе).
- Видео-путь для radeon: H.264 ≤ 720p через `c2.ffmpeg.h264` + VA-API.
- WMS↔InputDispatcher focus desync после OTA на bp4a `1794711917`
  не воспроизвёлся на стабильном boot; первый boot после OTA ещё
  требует отдельной проверки. Workaround `wm size ±1` в сборке остаётся.
- Delta OTA для add-on-устройств не поддерживается — публикуйте full.
- Security 23.2 — `2026-11-01` (upstream `vendor/lineage` `1a4ed79a`);
  pin `2026-10-01` удалён. `trunk_staging` (`2025-11-05`) не использовать.
- `ro.build.fingerprint` остаётся `google/fugu/fugu:8.0.0` (унаследовано);
  `user`-сборка и аудит release-флагов — отдельная задача.
- microG — prebuilt `/system/app/MicroGGmsCore` в базовом образе, не
  add-on; add-on ставит Play Store/YouTube/Widevine/NDK.

`recovery$SLOT.img` на x86-схеме — это padded `ramdisk-recovery.img`
(gzip cpio), а не `recovery.img`; иначе recovery уходит в kernel panic.
