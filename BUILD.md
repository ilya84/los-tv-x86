# Сборка

## Что нужно

- Linux x86_64 (проверено на Ubuntu 24.04), 16+ ГБ RAM, 300+ ГБ диска.
- Пакеты для AOSP (openjdk, clang, ninja, bc, rsync, zip, unzip, ccache…),
  `repo` в PATH.
- Для установщика: `unsquashfs`/`mksquashfs`, `7z`, `fakeroot`.
- Дерево LineageOS 23.2 (Android 16). Чистая сборка — 8–11 часов,
  инкрементальная — минуты.

## 1. Манифест и исходники

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

## 2. Патчи к остальным проектам

```sh
./scripts/apply-patches.sh ~/android/los-tv-x86
```

Скрипт читает `patches/series` и применяет `git am -3` к проектам
(`frameworks/base`, `system/core`, `bootable/recovery`, `build/soong`,
`frameworks/av`, `external/*`, `TvSettings`, sepolicy, Bluetooth и т.д.).
Если проект уже содержит наш коммит `los-tv: …`, он пропускается.

Патчи для `device/generic/x86_64_tv` и `bootable/aaropa` в серии есть, но
при использовании наших форков они не нужны — скрипт их пропустит.

## 3. Сторонние APK

В git их нет (см. `.gitignore`, `device/generic/x86_64_tv/prebuilt/README.md`).
Положите в `device/generic/x86_64_tv/prebuilt/`:

- `F-Droid.apk` — https://f-droid.org/F-Droid.apk
- `microG-GmsCore.apk` — https://github.com/microg/GmsCore/releases
  (0.3.17.252432, sha256 `e5e6cba078bdec812b5450599350e5c1a12c8b7438da5bf77123af170f8c1a35`)
- `user/JellyfinTV.apk` — F-Droid, 0.19.10 (191099), sha256
  `8510a517c99927076082917f41bf306dd7a2546c59d492dd11bde18d6e2e4628`
- `user/VLC-x86_64.apk` — VideoLAN, 3.7.1 x86_64, sha256
  `4646633ede40c4784c5584087cffc5c60cc45b16966ae0b36cedd784d7c4a11e`

Play Store в базовый образ не входит; его APK пользователь кладёт в
`/sdcard/los-tv-proprietary` и ставит через add-on.

## 4. Сборка ISO

```sh
cd ~/android/los-tv-x86
source build/envsetup.sh
lunch lineage_x86_64_tv trunk_staging userdebug
m iso_img
```

Результат: `out/target/product/x86_64_tv/lineage-*-x86_64_tv.iso`.

`scripts/run-iso-full.sh` — пример запуска в фоне с логом (пути поправьте).

Замечание: `install.sfs` (Calamares) собирается отдельно и пачвается
оверлеем из `installer/` (`scripts/patch-install-sfs.sh`, режим
`MODE=apply`). Перед `m iso_img` он должен лежать в
`bootable/aaropa/iso/install.sfs`.

## 5. Сборка OTA

```sh
bash scripts/make-ota.sh
```

Скрипт собирает `target-files-package`, генерирует полный A/B OTA
(`out/target/product/x86_64_tv/lineage_x86_64_tv-ota-full.zip`), проверяет
размер initrd (16 МиБ) и печатает хэши. Установка — `adb reboot sideload` +
`adb sideload zip`.

После OTA add-on восстанавливает компоненты автоматически: приложение
`addon-autorestore` создаёт маркер, GRUB грузит recovery, установщик ставит
компоненты на месте в активный слот (1–3 минуты).

## 6. Установка

1. Записать ISO на USB (`dd`/Rufus).
2. Загрузиться с USB, установить на диск (Calamares).
3. Первая загрузка: база (microG, F-Droid, Jellyfin, VLC).
4. Для платного DRM/Play Store: положить APK в `/sdcard/los-tv-proprietary`
   и выбрать в GRUB `Recovery → Установить проприетарные компоненты`
   (или открыть плитку в Android).

## Ограничения

- userdebug, SELinux Enforcing (проверено на e3000n 2026-11-05; Intel — следующий шаг);
- без шифрования данных;
- обязательность SSE4.2 не подтверждена (в работе);
- видео-путь для radeon: H.264 ≤ 720p через `c2.ffmpeg.h264`+VA-API.
