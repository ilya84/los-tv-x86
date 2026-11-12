# Сборка

Проверено 2026-11-13 на Debian 12 (`build-vm`, `kacnep@192.168.5.162`).
Текущие стенды: `intel` (H81M-E) — production, `e3000n` (AMD E2) — тестовый.

## 0. Быстрый старт

```sh
# 1. Синхронизировать дерево
mkdir -p ~/android && cd ~/android
repo init -u https://github.com/ilya84/lineage_bass_android.git -b lineage-23.2
repo sync -j8

# 2. Подготовить дерево одним скриптом
git clone https://github.com/ilya84/los-tv-x86 ~/los-tv-x86
~/los-tv-x86/scripts/bootstrap-tree.sh ~/android/los-tv-23

# 3. Собрать ISO
cd ~/android/los-tv-23
source build/envsetup.sh
lunch lineage_x86_64_tv trunk_staging userdebug
m iso_img
```

`bootstrap-tree.sh` идемпотентен: после `m clean` достаточно повторить его.
`--check` — только проверить, `--install-deps` — доустановить Debian-пакеты.
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
mkdir -p ~/android && cd ~/android
repo init -u https://github.com/ilya84/lineage_bass_android.git -b lineage-23.2
repo sync -j8
```

В манифесте (`android-x86/04-custom.xml`) наши проекты:

- `device/generic/x86_64_tv` — дерево устройства (форк BlissOS x86_64_tablet);
- `bootable/aaropa` — initrd и установщик;
- `external/libburn`, `external/libisofs`, `external/libisoburn` — сборка ISO.

> Если используете свои форки — поправьте `remote`/`name` в
> `04-custom.xml` (или положите свой local manifest в `.repo/local_manifests`).

## 3. Bootstrap чистого дерева (рекомендуется)

```sh
git clone https://github.com/ilya84/los-tv-x86 ~/los-tv-x86
~/los-tv-x86/scripts/bootstrap-tree.sh ~/android/los-tv-23
```

Скрипт:

1. применяет `patches/series` (пропускает проекты, где уже есть коммит
   `los-tv:`);
2. скачивает недостающие APK по `scripts/prebuilts.lock` с проверкой sha256;
3. проверяет/докачивает `bootable/aaropa/initrd_lib` и `iso/install.sfs`
   через `download.sh`;
4. патчит `install.sfs` оверлеем из `installer/overlay`;
5. ставит meson 1.8.5 и glslang 14.3.0, если системных версий недостаточно;
6. создаёт симлинки `out/host/linux-x86/bin/meson` и
   `glslangValidator`.

Скрипт ничего не делает разрушительного; повторный запуск безопасен.

## 4. Ручной путь (если не используется bootstrap)

```sh
./scripts/apply-patches.sh ~/android/los-tv-23
```

Скрипт читает `patches/series` и применяет `git am -3` к `frameworks/base`,
`system/core`, `bootable/recovery`, `build/soong`, `frameworks/av`,
`external/*`, `TvSettings`, sepolicy, Bluetooth и т.д. Если проект уже
содержит коммит `los-tv: …`, он пропускается. Патчи для
`device/generic/x86_64_tv` и `bootable/aaropa` в серии есть, но при
использовании наших форков не нужны.

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
cd ~/android/los-tv-23
source build/envsetup.sh
lunch lineage_x86_64_tv trunk_staging userdebug
m iso_img
```

Результат: `out/target/product/x86_64_tv/lineage-23.2-*-x86_64_tv.iso`
(ISO-инсталлятор с GRUB/Calamares; имя возвращено к историческому
LineageOS-формату вместо upstream `bass-lineout-*`).

`install.sfs` (Calamares) собирается отдельно и патчится оверлеем из
`installer/` (`installer/patch-install-sfs.sh`, режим `MODE=apply`). Перед
`m iso_img` он должен лежать в `bootable/aaropa/iso/install.sfs`.
Bootstrap (раздел 3) делает это сам; после `m clean` достаточно повторить
bootstrap — он вернёт симлинки `out/host/linux-x86/bin/meson` и
`glslangValidator`.

## 6. Сборка full OTA

```sh
bash scripts/make-ota.sh
```

Скрипт собирает `target-files-package`, генерирует полный A/B OTA
(`out/target/product/x86_64_tv/lineage_x86_64_tv-ota-full.zip`), проверяет
размер initrd (16 МиБ) и печатает хэши. Установка — `adb reboot sideload` +
`adb sideload zip`.

Прямой `m otapackage` не использовать: он даёт
`lineage_x86_64_tv-ota.zip`, а не `-ota-full.zip`, и упирается в отсутствие
`META/dynamic_partitions_info.txt` у статических разделов; скрипт обходит
это через `--extracted_input_target_files`.

После OTA add-on восстанавливает компоненты автоматически: приложение
`addon-autorestore` создаёт маркер, GRUB грузит recovery, установщик ставит
компоненты на месте в активный слот (1–3 минуты).

## 7. Сетевой OTA (опционально)

В образе уже есть LineageOS Updater, `update_engine` и A/B; пункт
«Обновление системы» открывается из TV Settings. Для своего сервера нужен
HTTPS с JSON и системное свойство `lineage.updater.uri`; по умолчанию
используется официальный сервер LineageOS, где сборок `x86_64_tv` нет.

Сборка с URL:

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
`packages/apps/Updater/README.md`.

> Безопасность: текущая OTA подписана публичным `testkey`. Для раздачи в
> интернет нужны собственные release-ключи и пересборка `otacerts`.

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
lunch lineage_x86_64_tv trunk_staging userdebug
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

Проверено 2026-11-13:

- `intel` — production, слот `_a`, build `1794305356` (testkey);
- текущий артефакт с release-keys: `system.img` md5
  `fceb9ed99c440a239969156cc5bebcd7`, build `1794522175`;
- ISO 2026-11-13 — `lineage-23.2-20261112-UNOFFICIAL-x86_64_tv.iso`,
  md5 `6ffbee1ce7d3d250291b46aae3aad0f9`;
- OTA 2026-11-10 — md5 `643b5f4049ebd5bab25988d1ed322f35` (testkey);
- `e3000n` — тестовый стенд, `_a` build `1794522175` (release-keys),
  `_b` — старый `1793842837` test-keys для отката;
- userdebug, SELinux Enforcing; без шифрования данных;
- обязательность SSE4.2 не подтверждена (в работе);
- видео-путь для radeon: H.264 ≤ 720p через `c2.ffmpeg.h264` + VA-API.

`recovery$SLOT.img` на x86-схеме — это padded `ramdisk-recovery.img`
(gzip cpio), а не `recovery.img`; иначе recovery уходит в kernel panic.
