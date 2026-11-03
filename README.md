# LOS-TV x86 — LineageOS 23.2 для x86_64 ТВ-приставок

Экспериментальная сборка Android TV (LineageOS 23.2 / Android 16) для
x86_64-приставок с загрузкой через GRUB, A/B-слотами и установкой с ISO.
База — только открытые компоненты; проприетарные Widevine L3, NDK
translation и Play Store ставятся отдельным add-on’ом с recovery.

An experimental Android TV (LineageOS 23.2 / Android 16) build for x86_64
TV boxes: GRUB boot, A/B slots, Calamares ISO installer and a recovery-based
add-on for Widevine L3 / NDK translation / Play Store.

## Что умеет

- **ISO-установщик** (Calamares) на базе x86-android порта, установка на
  внутренний диск с A/B-слотами (`system_a/b.img`, kernel/initrd/recovery).
- **GRUB-меню**: основной пункт, Recovery (в т.ч. «Установить проприетарные
  компоненты»), ручной выбор слота, разрешение экрана, kmsg-лог; заголовок
  отражает запрошенный режим («(to Recovery)», «(to SideLoad)») и таймаут
  сокращается до 5 секунд.
- **База**: microG GmsCore, F-Droid, Jellyfin TV, VLC; Play Store/YouTube TV
  в базовый образ не входят.
- **Add-on из recovery**: Widevine L3 (ChromeOS hatch), NDK translation
  (google_apis), Play Store/YouTube TV из APK пользователя. Payload-архив
  для повторной установки, режим «только APK», автовосстановление после
  полного OTA.
- **Плитка «Проприетарные компоненты»**: объяснение, QR-ссылки, `LINKS.txt`,
  фоновая загрузка образов (foreground-сервис, докачка, sha256), запуск
  установки, скрытие/возврат плитки.
- **Видео на AMD/radeon**: `c2.ffmpeg.h264` + VA-API (без VPP/DRM-PRIME),
  H.264 до 720p; на Intel включается штатный путь (все правки под
  `*radeon*`).
- **OTA**: полный OTA в неактивный слот; после установки add-on
  восстанавливает компоненты на месте в активный слот.

## Железо

- E3000N (AMD Kabini, radeon) — основной тестовый стенд.
- ASRock H81M-E (Intel Haswell) — проверка, что правки не ломают Intel.
- Загрузка: GRUB (UEFI и BIOS), разделы `esp`, `cdrom` (boot + data),
  `system_a/b`, `misc`, A/B.

## Репозитории

| Что | Где |
|---|---|
| Дерево устройства | `device/generic/x86_64_tv` (форк BlissOS x86_64_tablet) |
| Initrd/установщик | `bootable/aaropa` |
| Манифест | `lineage_bass_android` (ветка `lineage-23.2`) |
| Патчи к остальным проектам | `patches/` + `scripts/apply-patches.sh` |
| Оверлей Calamares | `installer/` |

## Статус и ограничения

- Сборка **userdebug**, SELinux сейчас **permissive** (переход на enforcing —
  отдельный этап).
- Шифрование данных не настроено.
- Уровень патчей безопасности — на момент синхронизации LineageOS 23.2.
- Обязательность SSE4.2 и поддержка другого железа — в работе.
- Play Store, YouTube TV, образы ChromeOS/google_apis **не публикуются**:
  их скачивает пользователь (ссылки в приложении/`LINKS.txt`).

## Лицензии

Код — Apache-2.0/иные лицензии соответствующих проектов AOSP/LineageOS.
Дерево устройства наследует BlissOS/aaropa (атрибуция сохранена). ZXing
core — Apache-2.0. Сторонние APK (F-Droid, microG, Jellyfin, VLC) не входят
в git; см. `prebuilt/README.md`.

## Быстрый старт

См. [BUILD.md](BUILD.md) и [CHANGELOG.md](CHANGELOG.md).
