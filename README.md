# LOS-TV x86 — LineageOS 23.2 для x86_64 ТВ-приставок

** AI-assisted and/or generated **

Экспериментальная сборка Android TV (LineageOS 23.2 / Android 16) для
x86_64-приставок (ориентированная на использование непосредственно на железе)
с загрузкой через GRUB, A/B-слотами, установкой с ISO и обновлениями по сети.
База — только открытые компоненты; проприетарные Widevine L3, NDK
translation и Play Store ставятся отдельным add-on’ом с recovery.

An experimental Android TV (LineageOS 23.2 / Android 16) build for x86_64
TV boxes: GRUB boot, A/B slots, Calamares ISO installer, a recovery-based
add-on for Widevine L3 / NDK translation / Play Store, and full OTA updates
over HTTPS with the LineageOS Updater.

## Что умеет

- **ISO-установщик** (Calamares) на базе x86-android порта, установка на
  внутренний диск с A/B-слотами (`system_a/b.img`, kernel/initrd/recovery).
- **GRUB-меню**: основной пункт, Recovery (в т.ч. «Установить проприетарные
  компоненты»), ручной выбор слота, разрешение экрана, kmsg-лог; заголовок
  отражает запрошенный режим («(to Recovery)», «(to SideLoad)»), таймаут
  сокращается до 5 секунд.
- **База**: microG GmsCore, F-Droid, Jellyfin TV, VLC.
- **SELinux Enforcing** на обоих стендах (AMD/radeon и Intel): медиа-тракт,
  Widevine L3, Wink/Jellyfin (видео+звук), Bluetooth, boot animation.
- **Play Store (TV) + microG**: проверены запуск и вход. UX-особенность:
  после входа Play Store может вернуться на экран «Войти» — перезапустите
  его; для закачки нужен `appops set com.android.vending ACTIVATE_VPN allow`.
- **Add-on из recovery**: Widevine L3 (ChromeOS hatch), NDK translation
  (google_apis), Play Store/YouTube TV из APK пользователя. Payload-архив
  для повторной установки, режим «только APK», автовосстановление после
  полного OTA (sideload и сетевая установка).
- **Плитка «Проприетарные компоненты»**: объяснение, QR-ссылки, `LINKS.txt`,
  фоновая загрузка образов (foreground-сервис, докачка, sha256), запуск
  установки, скрытие/возврат плитки.
- **Видео на AMD/radeon**: `c2.ffmpeg.h264` + VA-API (без VPP/DRM-PRIME),
  H.264 до 720p; на Intel включается штатный путь (все правки под
  `*radeon*`, проверено на Gigabyte E3000N, паяный AMD E2).
- **OTA**: полный A/B OTA в неактивный слот; после установки add-on
  восстанавливает компоненты на месте в активный слот. LineageOS Updater
  работает через HTTPS-JSON, поддерживает расписание (daily/weekly/monthly),
  опциональную автоустановку и автоперезагрузку, уведомления и `RebootActivity`.
- **Звук по RTP**: нативный сендер `AudioRecord(REMOTE_SUBMIX)` → UDP/L16
  на audiohub; управление из TV Settings (switch, host/port, статистика).

## Обновления

Текущая release-сборка 23.2 — `1794960573` (2026-11-18):

- OTA: <https://atv.kacnep.ru/ota/lineage_x86_64_tv-ota-full-1794960573.zip>
- JSON для Updater: <https://atv.kacnep.ru/x86_64_tv.json>
- ISO: <https://atv.kacnep.ru/iso/lineage-23.2-20261118-UNOFFICIAL-x86_64_tv.iso>

OTA подписана собственными `release-keys` (CN `los-tv-x86`), payload
`initrd,kernel,ramdisk-recovery,system`, сервер отдаёт `Range: bytes`.
Установка: TV Settings → Система → Обновления системы, либо
`adb reboot sideload` + `adb sideload <zip>`. Caddy отдаёт файлы
`/ota/*` с `immutable`, поэтому каждая сборка публикуется под уникальным
именем `...-<incremental>.zip`.

Security patch — `2026-11-01`. `system.img` — 6,0 ГБ (фактический образ
5 999 996 928 Б, запас ~2,26 ГБ внутри ext4). Recovery по умолчанию
permissive (`system/core/init/selinux.cpp`: `IsRecoveryMode()`), normal
boot остаётся Enforcing; installer дополнительно передаёт
`androidboot.selinux=permissive` для recovery-пунктов GRUB.

## Железо (в данный момент)

| Стенд | Железо | Роль | Сборка |
|---|---|---|---|
| `intel` | ASRock H81M-E, Intel Haswell | production, постоянная эксплуатация | `_a` `1794703929`, release-keys |
| `e3000n` | Gigabyte E3000N, AMD Kabini | тестовый стенд | `_b` `1794960573`, release-keys |

Оба — x86_64, Android 16 / SDK 36, `userdebug`, `ro.debuggable=0`,
SELinux Enforcing, 720p. Проверка правок — сначала на `e3000n`, затем на
`intel`. `e3000n` `_a` — `1794919314` boot-only fallback (RTP error);
рабочий откат `1794800321` сохранён вне слотов.

## Загрузка

GRUB (UEFI и BIOS), разделы `esp`, `cdrom` (boot + data), `system_a/b`,
`misc`, A/B. Образы слотов и initrd/recovery лежат на `cdrom`; переключение
слота — через `android.cfg` и bootctl HAL.

## Репозитории

| Что | Где |
|---|---|
| Дерево устройства | `device/generic/x86_64_tv` (форк BlissOS x86_64_tablet) |
| Initrd/установщик | `bootable/aaropa` |
| Манифест | `lineage_bass_android`, ветка/тег `los-tv-x86-23.2` (upstream LineageOS; старая `lineage-23.2` сохранена) |
| Патчи к остальным проектам | `patches/` + `scripts/apply-patches.sh`; release-тег helper `los-tv-x86-23.2` |
| Оверлей Calamares | `installer/` |

## Статус и ограничения

- Сборка **userdebug**, SELinux **Enforcing** проверен на `e3000n`
  (AMD, 2026-11-18) и Intel H81M (2026-11-07); текущие сборки —
  release-keys, `ro.build.tags=release-keys`; security patch `2026-11-01`.
- Шифрование данных не настроено. Recovery работает permissive
  (исключение только для recovery; normal boot — Enforcing).
- `system.img` — 6,0 ГБ (фактический образ 5 999 996 928 Б, content
  margin ~2,26 ГБ; file-vs-slot ~3 КиБ по конструкции образа).
- Обязательность SSE4.2 не подтверждена окончательно; поддержка другого
  железа — в работе.
- После OTA возможен рассинхрон WMS↔InputDispatcher (ANR «no focused
  window» на первом key); в текущих сборках есть workaround через
  `display-fixups.sh` (`wm size ±1`), полноценный фикс в WMS — в работе.
- Long-running YouTube TV на ARM-трансляторе исчерпывает 4-МиБ code pool
  за ~28–55 ч; обход — периодический restart приложения.
- Delta OTA для устройств с add-on не поддерживается (add-on меняет
  `/system`, source hash не совпадает); публикуется full OTA.
- Play Store, YouTube TV, образы ChromeOS/google_apis **не публикуются**:
  их скачивает пользователь (ссылки в приложении/`LINKS.txt`).
- Два ТВ разведены портами RTP (5004/5006); каждый сендер имеет один SSRC.

## Лицензии

Код — Apache-2.0/иные лицензии соответствующих проектов AOSP/LineageOS.
Дерево устройства наследует BlissOS/aaropa (атрибуция сохранена). ZXing
core — Apache-2.0. Сторонние APK (F-Droid, microG, Jellyfin, VLC) не входят
в git; см. `prebuilt/README.md`.

## Быстрый старт

См. [BUILD.md](BUILD.md) и [CHANGELOG.md](CHANGELOG.md).
