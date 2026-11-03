# Changelog

История изменений проекта LOS-TV x86 относительно LineageOS 23.2 / x86-android
(BassOS/aaropa). Внутренний журнал решений — `STATE.md` в рабочем репозитории;
здесь — сводка по этапам и ссылки на коммиты.

Формат: дата — этап — что сделано.

## 2026-08 … 09 — база и загрузка

- Перенос x86_64 TV-сборки на LineageOS 23.2 (Android 16), продукт
  `lineage_x86_64_tv`, A/B-слоты (`system_a/b.img`, kernel/initrd/recovery),
  GRUB, ESP.
- `bootable/aaropa`: initrd, сборка ISO, установщик; фиксированный размер
  initrd 16 МиБ; правки `build/soong/fsgen` (плотность recovery `tv` → xhdpi).
- `system/core/init`: сохраняем devtmpfs из initrd (на медленном AMD
  ueventd не успевал пересоздать `/dev`), ранний лог на ESP.
- Дерево устройства: `device/generic/x86_64_tv` (форк BlissOS
  `x86_64_tablet`, переименование `_tablet` → `_tv`), bootctrl, fstab,
  recovery, каталоги prebuilt.

## 2026-09 … 10 — инсталлятор, recovery, OTA

- Calamares-оверлей: меню GRUB (Recovery, выбор слота, разрешение, kmsg),
  генерация `android.cfg`, `install.sfs`, патч `10_blissos`/`bootcfg`.
- `bootable/recovery`: режим `sideload_auto_reboot_on_success` для обычного
  `adb reboot sideload` (текстовый режим, без A/B-подтверждения, ребут
  только при успехе).
- Recovery по BCB из `misc.img` (initrd), `adb reboot recovery/sideload`,
  A/B-переключение, `bootctl`.
- OTA: полный A/B-пакет, обход `virtual_ab_cow_version`, проверка initrd;
  `scripts/make-ota.sh`.
- `device/lineage/sepolicy`: gmscore_app без `apk_verity_prop`.
- `system/apex`: увеличен таймаут ожидания `/dev/loop-control` (медленное
  железо).
- `TvSettings`: разрешение/дисплей/сетевые умолчания для x86 TV.

## 2026-10 — видео (AMD radeon) и Intel

- Рабочий путь: `c2.ffmpeg.h264` + VA-API, `debug.ffmpeg-codec2.hwaccel.drm=0`
  (без VPP), `pixel_format=RGBX_8888`, `rank=768`, `deinterlace=none`,
  HWC overlays, H.264 до 1280×720/30, `block-count 1–32768`.
- Отключение софт-кодеков (avc/hevc/vp9/av1) в radeon XML — YouTube/Wink
  уходят на `c2.ffmpeg.h264`.
- VPP/DRM-PRIME на `gbm_gralloc` признан тупиком (полосы, `page flip -22`,
  рестарт Runtime) и убран.
- Все правки под `*radeon*`; Intel (H81M) не затронут.
- `frameworks/av`: dav1d — потоков `cpu_count-1`; seccomp x86:
  `sched_setaffinity`.
- `external/stagefright-plugins`: c2-ffmpeg seccomp-политики для x86/x86_64.
- `external/mesa3d`, `external/skia`: `vendor_available` для virtio/rust/скмс
  модулей.
- `packages/modules/Bluetooth`: HID-таблица отчётов 64 (пульты с большим
  числом HOGP-отчётов, например Xiaomi RC).
- `packages/providers/ContactsProvider`: на TV отключена фоновая задача
  call-log (циклическая ошибка), ослаблен SQL-токенайзер.
- `frameworks/base`: `cmd notification -T` (TvExtender) для TV-уведомлений;
  русская строка диалога recovery-перезагрузки.

## 2026-10-31 … 11-01 — add-on проприетарных компонентов

- База очищена от Google: Play Store, Widevine, NDK translation и arm64 ABI
  удалены; YouTube TV/Wink/Кинопоиск убраны (ставятся пользователем).
- Add-on из recovery: Widevine L3 из ChromeOS hatch (`vendor.raw.img`,
  `system.raw.img`), NDK translation из google_apis (`lpunpack`), Play Store
  и YouTube TV из APK пользователя.
- Payload-архив `/mnt/cdrom/los-tv-proprietary.tar.gz` для повторной
  установки; md5-манифест; права каталогов 755/644.
- Режим post-OTA: установка на месте в активный слот, бэкап не трогаем;
  ручной запуск — клон активного слота в неактивный и переключение.
- `addon-autorestore` (exec, а не service) — автовосстановление после OTA;
  BCB/маркер, сброс `MODE=normal`, очистка BCB.
- `init.sh`: убрано отключение Bluetooth (вызывало цикл system_server).

## 2026-11-01 … 11-03 — UX и устойчивость

- GRUB: заголовок «(to Recovery)»/«(to SideLoad)» по маркерам, таймаут 5 с
  при целевой перезагрузке; initrd чистит маркеры.
- `los-tv-msg`: история сообщений с прокруткой, перенос длинных строк,
  заголовки `>>`, `--reset`.
- Recovery preflight: поиск файлов по нескольким каталогам, экран «файлов
  нет», маркер для Android, возврат в Android.
- Приложение `LosTvAddon`: плитка, объяснение, QR-коды и `LINKS.txt`,
  фоновая загрузка образов (foreground-сервис, докачка, sha256),
  уведомление о завершении, установка через recovery, скрытие/возврат
  плитки, затенение недоступных кнопок, D-pad-навигация.
- `privacy`: `signature-permissions` allowlist для `RECOVERY`, appops
  `MANAGE_EXTERNAL_STORAGE`, `POST_NOTIFICATIONS`; русская строка
  «Перезагрузка в recovery».
- Режим «только APK» (компоненты уже стоят): установка Play Store/YouTube TV
  в активный слот за минуту.
- **Поиск по содержимому образов**: `los-tv-gpt` (GPT, байтовые смещения
  64-бит), тип архива по содержимому, ROOT-A/super по имени, raw-образы и
  библиотеки Widevine по `find`, NDK по `libndk_translation.so` + шаблоны,
  динамический `ndk-files.txt` в payload; хеши образов больше не блокируют.
- Play Store исключён из базового образа и из git (проприетарный APK);
  сторонние APK не публикуются (см. `prebuilt/README.md`).
- Снапшот исходников: ветки `los-tv` во всех проектах (см. коммиты ниже).

## Коммиты снапшота 2026-11-03

| Проект | Коммит |
|---|---|
| device/generic/x86_64_tv | `2cf74c7` los-tv: x86_64 TV device tree (add-on, app, radeon codecs, recovery) |
| bootable/aaropa | `466d67a` initrd: BCB recovery, mode markers cleanup, installer hooks |
| bootable/recovery | `8a2159ba` recovery: sideload-auto-reboot-on-success |
| build/soong | `34a0c0b2f` fsgen: tv → xhdpi |
| system/core | `801b25579` init: keep initrd devtmpfs, early boot log |
| frameworks/base | `989e8d94a74e` cmd notification TvExtender; ru dialog |
| packages/apps/TvSettings | `e64eb0264` TV settings: x86 defaults |
| device/lineage/sepolicy | `18fe860` gmscore_app: drop apk_verity_prop |
| packages/modules/Bluetooth | `8613f98ee0` HID: 64 reports |
| packages/providers/ContactsProvider | `afedb0a8` TV call-log/tokenizer |
| system/apex | `414d1153` apexd loop-control timeout |
| frameworks/av | `54e40af875` dav1d/seccomp |
| external/stagefright-plugins | `357fa2c` c2-ffmpeg seccomp |
| external/skia | `26b1d8acb3` skcms vendor_available |
| external/mesa3d | `e8b98813062` virtio vendor_available |
| manifest | `19bdda5` path device/generic/x86_64_tv; device/aaropa on ilya84 |

Базовый порт (qcom/mesa/skia/av/prebuilts и др., унаследованный от
BassOS/aaropa) в снапшот los-tv не входит; он остаётся отдельным слоем.

## Планы

- SELinux enforcing (текущий этап).
- Обновление LineageOS/патчей безопасности (апстрим).
- Другое железо (Kabini/Haswell уже; далее — по мере появления).
- Шифрование данных, user-сборка — позже.

## Публикация

- https://github.com/ilya84/los-tv-x86 — этот набор (доки, патчи, установщик)
- https://github.com/ilya84/lineage_bass_android — манифест (ветка `lineage-23.2`)
- https://github.com/ilya84/android_device_generic_x86_64_tv — дерево устройства
- https://github.com/ilya84/bootable_aaropa — initrd/установщик

Публичные проекты из `github.com/los-tv-x86` (alsa-utils, intel/audio,
hcitools и т.п.) используются как read-only зависимости с атрибуцией.
