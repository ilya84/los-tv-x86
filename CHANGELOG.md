# Changelog

История изменений проекта LOS-TV x86 относительно LineageOS 23.2 / x86-android
(BassOS/aaropa). Внутренний журнал решений — `STATE.md` в рабочем репозитории;
здесь — сводка по этапам и ссылки на коммиты.

Формат: дата — этап — что сделано.

## 2026-11-15 — production на release-keys, сетевой OTA, YouTube payload sync

- `intel` переведён на releasekey прямым flash в неактивный `_b`:
  build `1794665098`, `ro.build.tags=release-keys`, Enforcing; `_a`
  (`1794305356`, testkey) сохранён как откат. После первого старта
  bootctl/`/boot` label-persistence сработал, `android.cfg` получил
  `u:object_r:bootdir_file:s0`.
- Обнаружен и исправлен ghost YouTube на `intel`: preinstall брал с
  `/sdcard` старый 7.30.302 при установленном 7.31.301 и падал
  `INSTALL_FAILED_VERSION_DOWNGRADE`. Установлен base+split 7.31.301,
  данные сохранены, sdcard/payload обновлён.
- YouTube payload sync (device tree `3cc6260` + `c21e2ef`): на каждом
  boot `addon-autorestore.sh` копирует installed base+split в
  `/sdcard/los-tv-proprietary` (atomic, sidecar = versionCode + sha256
  base). Recovery add-on сравнивает `/data/app` и sdcard по sidecar/mtime
  и выбирает более новый источник; preinstall не ставит APK старее
  installed. В recovery нет `awk` — sha256 через `cut`; после первого
  boot-install вызывается sync с `YOUTUBE_SYNC_ONLY=1`. Ghost больше не
  воспроизводится.
- Опубликована OTA `1794665098`: 1 783 669 872 Б, md5
  `15824a62cdb13fc2b8562dba8f8bc60a`, sha256
  `a2d10acac22c22a7228cbf1e8c4e97a59184f2d54bd076571458f6ffcd1b7657`;
  ISO `lineage-23.2-20261114-UNOFFICIAL-x86_64_tv.iso` (2 629 386 240 Б,
  md5 `c301caaf3f1298010adfee350ca5c897`, sha256 `eba68070…f357`)
  содержит тот же build.
- Опубликована финальная OTA `1794703929`: 1 783 656 108 Б, md5
  `f49913aa0d7940272812663224ddee56`, sha256 `660bf424…ac45`;
  на `e3000n` recovery-addon отработал без `awk`, preinstall поставил
  YouTube 7.31.301, post-preinstall sync прошёл, downgrade нет.
- Сетевой OTA проверена на обоих стендах: полный цикл `update_engine`
  под Enforcing (`kSuccess`, переключение слота, add-on), scheduled
  daily auto-install (22:30), уведомление «Обновление установлено»,
  `RebootActivity`, ротация persistent logcat 2 МБ × 2. Updater
  запланирован на `intel` и `e3000n`.
- WMS/InputDispatcher: ANR лаунчера после OTA разобран как рассинхрон
  (WMS focused, `FocusedWindows=<none>`); добавлен workaround в
  `display-fixups.sh` (`wm size ±1` при рассинхроне). Полноценный фикс
  в WMS — следующий changeset.
- RTP-звук разведён на два ТВ: `intel` → `192.168.5.150:5004`,
  `e3000n` → `192.168.5.150:5006`; на audiohub два приёмника
  (`tv-rtp.service`, `tv-rtp-2.service`), оба потока active.
- Сборка переведена на release-конфиг **`bp4a`** (BP4A/Android 16,
  security patch `2026-10-01`; `trunk_staging` давал `2025-11-05` и
  ZP1A/Android 17-флаги). `make-ota.sh` берёт release из
  `vendor/lineage/vars/aosp_target_release` (default `bp4a`), допускает
  `LUNCH_VARIANT=...`. Для воспроизводимых сборок — `SKIP_AG_DOWNLOADS=true`:
  `vendorsetup.sh` при `lunch` иначе обновляет `pci.ids`/`usb.ids`,
  toolchain и firmware из сети. Тестовая OTA `1794711917` проверена на
  `e3000n`, не публиковалась.
- Публикация: device tree `8c17122` (squashed: RTP, YouTube payload sync,
  bootctl/`/boot` labels, WMS-workaround, RebootActivity), TvSettings
  `1c8edb57`, aaropa `c5107b0`, Updater patch `4662599`,
  system/sepolicy patch `5e09bcbf5`, bootable/recovery patch `2fd9aca`
  (sideload auto-reboot on success); обновлены README, BUILD.md,
  CHANGELOG и `patches/`.

## 2026-11-14 — OTA при Enforcing и опциональная автоустановка в Updater

- Policy `update_engine` перенесена из `system_ext` в
  `system/sepolicy/private`: разрешения на initrd-овый `/fstab` (tmpfs/
  rootfs) и на запись `initrd/kernel/ramdisk-recovery` через
  `block_device:blk_file`. Прямой `allow` конфликтует с neverallow в
  `domain.te`, поэтому для `update_engine` сделано точечное исключение
  `-update_engine`. Policy теперь приезжает вместе с `system` и не
  зависит от обновления `system_ext`.
- `system_ext`/`product` в этой x86-схеме — каталоги внутри `system.img`,
  а не отдельные A/B-разделы; добавлять их в `AB_OTA_PARTITIONS` нельзя.
  Причина старых build.prop — order-only зависимость Soong от
  `out/build_date.txt`. Новый `scripts/regen-build-props.sh` (вызывается
  `make-ota.sh`) удаляет все build.prop/intermediates, а `make-ota.sh`
  сверяет `ro.*.build.version.incremental` по всем разделам.
- В существующие настройки Updater добавлена категория «Автоматическая
  установка»: периодический worker при новой сборке запускает
  `UpdaterService.ACTION_INSTALL_UPDATE` (foreground, streaming или
  сначала загрузка), после `UPDATED_NEED_REBOOT` — уведомление либо
  автоматический `PowerManager.reboot()`; обе опции по умолчанию
  выключены.
- Исправлен экран настроек Updater на TV: вместо `RegularScaffold`
  используется `SettingsScaffold` с тем же `fillMaxSize + padding +
  verticalScroll` layout, что и главный экран, а начальный фокус
  переносится с левой back-кнопки на первую строку. Раньше ни одна
  строка не имела фокуса, D-pad не двигал, а OK/Enter нажимал «назад».
- Расписание проверок Updater стало управляемым: ежедневно,
  еженедельно (день недели) или ежемесячно (день месяца) в HH:MM;
  минуты выбираются шагом 5; показывается следующая проверка. Вместо
  PeriodicWorkRequest используются one-time WorkManager jobs с
  уникальными именами; пропущенная или неуспешная проверка повторяется
  примерно через 12 минут после загрузки/ошибки (до 3 попыток), состояние
  catch-up переживает reboot. Старый `CheckInterval` удалён с миграцией
  ключа `check_interval`.
- Улучшены уведомления Updater: после успешной установки всегда
  показывается «Обновление установлено. Перезагрузите устройство…»;
  нажатие на уведомление открывает `RebootActivity` с подтверждением
  перезагрузки (`Перезагрузить сейчас` / `Отмена`), а не сразу Updater.
  Уведомления об ошибках (загрузка, проверка, установка, сбой после
  перезагрузки) показываются только при включённой автоустановке; без
  неё ошибка остаётся в UI Updater и уведомление не создаётся.
- Исправлена ротация persistent logcat: `los_tv_kmsglog` получил
  `dir { read getattr remove_name rename }` и capability `sys_nice`.
  Раньше `logcat.log` рос без ограничения (36.8 МБ вместо 2 МБ × 2),
  в audit были AVC на `read`/`remove_name`. `dac_override` не выдаётся:
  он под neverallow, а файл принадлежит root.
- Собрана OTA `1794623813`: 1 783 751 785 Б, md5
  `5170c0afd6392e45473f51891419a110`, sha256
  `b87bd066881ecadd78c19bb2360fa34a192a8798240340119c84c0ad120dcff5`;
  все build.prop согласованы, `lineage.updater.uri` запечён, policy
  проверена в `plat_sepolicy.cil`, GUI автоустановки проверен на `e3000n`.
  OTA ещё не публиковалась и не устанавливалась; для проверки Enforcing её
  нужно поставить через sideload/recovery (текущая активная сборка содержит
  старую policy).
- Собрана и опубликована OTA `1794655508`: 1 783 670 000 Б, md5
  `355cd7373f2901ed3d514cd281ea0904`, sha256
  `fc53662d3d1de9676313a5c304272bacb0a13088d83f5f35b886876fdc535fc1`;
  `lineage.updater.uri=https://atv.kacnep.ru/x86_64_tv.json`. На `e3000n`
  проверено автообновление по расписанию daily 22:30: worker стартовал
  в 22:31:28, payload применён `B → A`, `kSuccess` в 22:42:23,
  `android.cfg` → `SLOT=_a`. После ручного ребута первый старт `_a`
  (`1794655508`, Enforcing), add-on автоустановлен (Play 53.4.17,
  microG GMS, YouTube 7.31.301), watchdog записал
  `input focus: launcher focused, ok`, ANR нет; следующая проверка —
  2026-11-15 22:30.
- Собрана OTA `1794662801` (промежуточная): 1 783 670 072 Б, md5
  `715a5e562ab7b641525e1c9e32050fff`, sha256
  `49d2729283e71efbc20a2f58e678a2dce0c3c3c2434fa8059fc75eb82cc2107e`;
  внутри rotation fix `los_tv_kmsglog` и UX уведомлений Updater.
  На `e3000n` установлена в `_b` (`kSuccess`), успешное уведомление
  «Обновление установлено…», после ребута ротация `logcat.log.1/.2`
  по 2 МБ.
- На уже установленной `e3000n` обнаружен цикл `adb reboot sideload`:
  установленный `/boot/grub/grub.cfg` был старым и не подставлял для
  `MODE=sideload` `androidboot.mode=recovery` + `force_normal_boot=0`
  (`BOOT_MODE`). Исправлено на устройстве (бэкап + `grub-script-check`);
  в `10_blissos` фикс уже есть, но OTA не обновляет `/boot/grub`.
  Существующие устройства требуют разового патча grub.cfg.
- Отмечено поведение recovery после sync с апстримом: adb по умолчанию
  выключен, в Advanced есть пункт включения adb (работает). Пока без
  изменений в коде.

## 2026-11-14 — фикс Bluetooth mac_permissions и сетевая OTA atv.kacnep.ru

- Исправлен незапускавшийся Bluetooth на release-keys сборке: APK
  подписан ключом `vendor/lineage-priv/keys/bluetooth.x509.pem`, а
  `plat_mac_permissions.xml` брал AOSP-ключ, потому что `config.mk`
  выбирает `MAINLINE_BLUETOOTH_SEPOLICY_DEV_CERTIFICATES` из
  `build/make/target/product/security/` для `com.android.bt`. Добавлено
  `PRODUCT_MAINLINE_BLUETOOTH_SEPOLICY_DEV_CERTIFICATES := vendor/lineage-priv/keys`
  в `keys.mk`; проверять соответствие подписи APK и `seinfo=bluetooth`.
- Собран и опубликован сетевой OTA на `https://atv.kacnep.ru`:
  `lineage_x86_64_tv-ota-full-1794611492.zip` (1 783 722 795 Б, sha256
  `610626a1b3a06b8a04e3b6c51033bd888cd3598907fb643f1d922c4d7f7e1e98`),
  JSON `x86_64_tv.json`, Range 206. В сборку запечён
  `lineage.updater.uri`; OTA установлена на `e3000n` в `_b`, Bluetooth
  включился, пульт подключился. На первом старте был ANR лаунчера из-за
  preinstall/dexopt (не Java-крэш), процесс перезапустился.
- OTA-файлы публикуются под уникальным именем (`...-<incremental>.zip`),
  чтобы не конфликтовать с `Cache-Control: immutable` на `/ota/*`.
- Ограничение x86-схемы: payload обновляет только
  `initrd/kernel/ramdisk-recovery/system`. `system_ext`/`product` здесь —
  каталоги внутри `system.img`, а не отдельные A/B-разделы, поэтому в
  `AB_OTA_PARTITIONS` их добавлять нельзя; policy и build.prop нужно
  держать в `system` (исправлено в следующей сборке).
- Косметика: в Updater кнопка «Перезапуск» переименована в
  «Перезагрузка»; перед автоматическим reboot в recovery для add-on
  показывается полноэкранное сообщение «Перезагружаю для установки
  проприетарных компонентов» с паузой 4 с (`RebootActivity` в
  `LosTvAddon`, вызов из `addon-autorestore.sh`). Собраны только APK
  `Updater`/`LosTvAddon`; ISO/OTA не пересобирались.

## 2026-11-13 — userdebug с собственными ключами; e3000n на новой сборке

- Добавлена поддержка собственных ключей: `vendor/lineage-priv/keys`
  (CN `los-tv-x86`), `PRODUCT_DEFAULT_DEV_CERTIFICATE=releasekey`;
  userdebug-сборка получает `ro.build.tags=release-keys`, `otacerts.zip`
  содержит `releasekey.x509.pem`. `make-ota.sh` автоматически выбирает
  `releasekey`, для перехода со старого testkey — `OTA_KEY=.../testkey`.
- `e3000n` напрямую прошит в `_a` (build `1794522175`): release-keys,
  Enforcing, RTP-сендер, NDK/Widevine, Play Store/YouTube 7.31.301;
  `_b` — старый test-keys откат.
- Исправлена ошибка recovery: на x86-схеме `recovery$SLOT.img` — это
  padded `ramdisk-recovery.img` (gzip cpio), а не `recovery.img`
  (Android boot image), иначе recovery падает в kernel panic.
- Add-on recovery теперь при обновлении preinstall берёт уже установленный
  YouTube APK из `/data/app`, а не старый APK из `/sdcard`; это убирает
  `INSTALL_FAILED_VERSION_DOWNGRADE` при ghost-пакете.
- ISO 2026-11-13: md5 `7fc769697ed3c329cf122bc409345365`; OTA 2026-11-13:
  md5 `869b68180a738b6f41210392b2216473` (releasekey); `system.img`
  release-keys md5 `fceb9ed99c440a239969156cc5bebcd7`.

## 2026-11-12 — bootstrap сборки и подготовка сетевого OTA

- `scripts/bootstrap-tree.sh` — один идемпотентный шаг после `repo sync`:
  патчи, prebuilt APK по `scripts/prebuilts.lock` с sha256, aaropa
  `initrd_lib`/`install.sfs`, патч `install.sfs`, meson/glslang и симлинки
  в `out/host/linux-x86/bin`. После `m clean` достаточно повторить.
- `installer/patch-install-sfs.sh` стал переносимым: пути считаются от
  репозитория, база обновлена на актуальную; добавлен `TREE`/`OVERLAY`.
- `scripts/make-ota-index.py` — генератор JSON для LineageOS Updater из
  full-OTA zip (sha256, size, `ota_property_files`).
- Актуализирован `BUILD.md`: чистый bootstrap, актуальные APK/URL, ISO
  `bass-lineout-*`, full OTA через `scripts/make-ota.sh`, опциональный
  сетевой OTA (`lineage.updater.uri`, HTTPS, Range).
- `BUILD.md`: результат ISO — `lineage-23.2-*-x86_64_tv.iso` (историческое
  имя; upstream `bass-lineout-*` убран).
- ISO 2026-11-12: `lineage-23.2-20261112-UNOFFICIAL-x86_64_tv.iso`,
  md5 `573a7265aa57ec60e4e6e75079d8a617`, sha256 `0277c39f…`;
  system `b86ab896…`, install.sfs `abe44dc7…`.
- Device tree `a4a40e2`: опциональный `LOS_TV_OTA_URI` →
  `lineage.updater.uri`; из `vendorsetup.sh` убран вызов несуществующего
  `newinstaller-ng`; aaropa `c5107b0`: `aaropa.lock` закреплён на `20260905`,
  ISO переименован в `lineage-*`.
- Роли стендов: `intel` — production, `e3000n` — тестовый.

## 2026-11-10 — YouTube TV переживает перепрошивку (preinstall)

- `prebuilt_etc`-модули init-rc теперь устанавливаются с явным `filename:
  "*.rc"`. Без него файлы назывались `*-rc`, init регистрировал service, но
  не `on-property`, и `preinstall-apps`, `play-store-fixups`,
  `display-fixups`, `checkin-enabler`, `tvres-notify` молча не запускались.
- Эти скрипты запускаются через `exec`/`exec_background` с `seclabel
  u:r:su:s0`: service без seclabel не мог выполнить `/system/bin/sh` под
  SELinux Enforcing.
- `preinstall-apps.sh` сам ставит YouTube TV (base+split через
  install-session), принимает абсолютные пути и ищет
  `split_config.arm64_v8a.apk` в `/data/media/0/los-tv-proprietary`, если
  add-on/recovery не скопировал его в `/system/etc/preinstall`.
- Ghost после перепрошивки (пакет в PackageManager, APK-каталога нет)
  автоматически чинится при `sys.boot_completed`; осознанно удалённое
  приложение (каталога данных нет) не воскрешается.
- Проверено на `intel` `_b`: reflash → YouTube base+split, Play Store
  «Открыть»; удаление `/data/app/<youtube>` + ребут → починка за ~14 с.
  Коммит device tree `ceeeae6`.
- Собраны ISO и полная A/B OTA с RTP-сендером, TvSettings и этим фиксом.
  Холодный sideload OTA на `intel`: add-on-autorestore сам поставил
  компоненты в `_a`, новый recovery скопировал base+split YouTube в
  `/system/etc/preinstall`, после загрузки — Enforcing, YouTube/Play Store,
  RTP-сендер, mediaextractor и bt_hotplug на месте.
  ISO: md5 `1c40b137a89b461b3429a684fefdc747`;
  OTA: md5 `643b5f4049ebd5bab25988d1ed322f35`.
- Публикация: device tree `179d7e2` (`los-tv` и `lineage-23.2`),
  aaropa `bdb615c` (`los-tv` и `lineage-23.2`); TvSettings — обновлённый
  единый патч в `patches/`.

## 2026-11-09 — target reboot sideload/GRUB, addon install, bt_hotplug

- recovery: `sideload_auto_reboot_on_success` больше не включает UI-флаг
  автоперезагрузки; plain `adb reboot sideload` остаётся в sideload.
- init: все `exec`-действия в `/system/etc/init` получили явный seclabel
  `u:r:su:s0`; без него init не мог запустить `/system/bin/sh`.
- GRUB/installer: для `MODE=sideload` теперь `androidboot.mode=recovery`,
  `androidboot.force_normal_boot=0` и пустой `SELINUX_ENTRY` — ранний ребут
  до старта recovery устранён. Фикс в `10_blissos` и в установленном
  `grub.cfg` на `.198`.
- bt_hotplug: watcher запускается через `exec_background`; старый
  `sh -c "nohup ... &"` убивался вместе с process group exec-сервиса.
- Проверено на `.198`: установка addon из мини-приложения из payload —
  clone `_b` → `_a`, NDK translation + Widevine, переключение слота, ~46 с.

## 2026-11-09 — exec-сервисы BT/add-on и фикс sideload-авторебута

- `bt-hotplug` и `los-tv-addon-check`/`los-tv-addon-notify`: переведены с
  `service`-блоков на `exec`-действия в `/system/etc/init` — init этой сборки
  не регистрирует service из этого каталога.
- recovery: `sideload_auto_reboot_on_success` больше не включает UI-флаг
  автоперезагрузки; reboot только при `status == INSTALL_SUCCESS`. Это
  убирает ложный ребут при `adb reboot sideload` без начатой передачи.
- Проверено: `adb reboot recovery` работает; Android→sideload доходит до
  recovery; recovery→sideload не поддерживается (сценарий не проектировался).

## 2026-11-09 — BT hot-plug watchdog

- Новый сервис `bt-hotplug` перезапускает Bluetooth, когда USB HCI-адаптер
  переподключается (например, кот задел донгл). Android после такого
  hot-plug может остаться в состоянии «HOGP connected» с мёртвым HCI-fd:
  пульт перестаёт работать, а стек не пытается переподключиться.
- Watcher следит за пересозданием `hciN` (inode+ctime), а не за USB
  devnum — при быстром re-plug номер устройства может не измениться.
- Если Bluetooth выключен пользователем, сервис не включает его.
  Отключается на лету: `setprop persist.sys.bt_hotplug 0`.
- Проверено на `.198`: реальный disconnect/reconnect порта
  (`usb1-port5/disable`) → ровно один автоматический restart BT, без
  цикла; при выключенном BT — skip.

## 2026-11-09 — KernelSU удалён, /metadata постоянный, recovery сам сбрасывает MODE

- Ядро (`kernel/x86/zenith`): `CONFIG_KSU` выключен — KernelSU больше не
  инициализируется и не спамит при загрузке; остаётся консольный AOSP su.
- Initrd: `/metadata` теперь bind-mount каталога `metadata` на
  cdrom-разделе (создаётся при первой загрузке; fallback — tmpfs):
  aconfig-оверрайды и APEX-rollback переживают перезагрузку.
- Recovery: при старте сбрасывает `MODE=normal` — обычный reboot из
  recovery возвращает в Android без цикла.
- Проверено на Intel H81M: загрузка, Enforcing, звук (scrcpy), recovery
  с сетью (eth0 + adb), сохранность `/metadata` после ребута.

## 2026-11-09 — тишина в scrcpy/REMOTE_SUBMIX (Intel): volume groups

- После апстрима захват звука (scrcpy, screen recording) на Intel отдавал
  тишину: `STRATEGY_MEDIA` уходил в `REMOTE_SUBMIX`, потоки писали/читали,
  но у потока MUSIC была `Volume: nan` (на e3000n — −21.6 dB), в logcat —
  `setMinVolumeIndexForGroup: Invalid group id -1` каждые 2 с.
- Причина: рабочий `/metadata` включил trunk_staging-флаг
  `android.media.audiopolicy.volume_group_management_update`; в
  аудио-конфиге x86-порта нет volume groups → `initStreamVolume` падал,
  громкость оставалась NaN → в субмикс писались нули.
- Фикс: флаг `volume_group_management_update` отключён в
  `build/release` для `trunk_staging` (проект добавлен в `patches/`);
  заглушка `/metadata` теперь ставится в корень образа (`root/...`), как
  и ожидает initrd. Проверено на Intel: scrcpy принимает звук.
- План на потом: новый initrd Bliss-Bass (в нём нет rtl_nic firmware и
  части модулей — recovery без сети) и аудит trunk_staging-флагов.

## 2026-11-08 — фиксы после апстрима: /metadata, GRUB recovery

- Новый порт `bootable/aaropa` на Bliss-Bass `8c6a69f`: initrd (BCB-recovery,
  маркеры режимов, NIC/kmsg для recovery), паддинг initrd 16 МиБ, ISO без
  HFS+/APM (патч теперь применяется к Bliss-Bass, не к старому aaropa).
- `/metadata`: в порте нет metadata-раздела, из-за чего aconfigd не
  инициализировал flag storage, PackageManager отбрасывал фичефлаговые
  разрешения (RANGING), и system_server падал в AppOpService. Initrd теперь
  монтирует tmpfs на `/metadata`, в образ ставится каталог-заглушка.
- `adb reboot recovery`: `MODE` в `android.cfg` теперь пишет
  `los-tv-boot-mode.sh` по BCB (раньше это делал только framework
  ShutdownThread, CLI-ребуты уходили в early-reboot); recovery при старте
  сбрасывает `MODE=normal`, initrd — тоже (защита от старых recovery).
- Проверено на Intel H81M: апстрим-система загружается под Enforcing,
  YouTube TV (NDK/arm64) стартует, Play Store и microG работают.

## 2026-11-07 — обновление апстрима LineageOS 23.2 / ASB

- Манифест: влиты LineageOS/android (5 коммитов, ASB-форки: conscrypt,
  ca-certificates, tinyalsa, broadcom/wlan, android-security-16.0.0_r8)
  и BassOS (aaropa переведён на Bliss-Bass, перенос отложен).
- 18 проектов переведены на ASB-форки LineageOS (system/libfmq,
  libhevc, freetype, conscrypt, incremental_delivery и др.).
- Прямые LineageOS-проекты: обновлено 28 (приложения, lineage-sdk,
  telephony и т.д.); org-форки смержены с LineageOS (frameworks/base +79,
  av +11, Bluetooth +17, core +3, native +1, TvSettings +4, recovery +3,
  soong +3, hardware/interfaces +4), los-tv-ветки перебазированы.
- Конфликты разрешены: TvSettings (build_date + OpenGL/Vulkan),
  recovery (MBR/GPT-чек оставлен x86-фиксом), vendor/lineage (kernel.mk
  остаётся удалённым), Catapult (null-safety апстрима).
- Публикация: TV Settings теперь включает поддержку BLE-пультов
  (раньше терялась из-за `format-patch -1` на многоветочной ветке).
- Без изменений: AOSP-теги (`android-16.0.0_r4`), mesa 26.0, ядро.

## 2026-11-04 … 07 — media.swcodec на любом GPU, Bluetooth, microG; Intel H81M под Enforcing

- `init.sh`: `media.swcodec` теперь стартует в общей точке входа
  `apexcodecs` (триггер `apex.all.ready=true`) для любого GPU, а не только
  внутри radeon-ветки `do_media_codec_lists()`. Без этого на Intel H81M
  не регистрировался AIDL `IComponentStore/software`, `mediaserver` ждал
  его на binder, и YouTube TV зависал чёрным экраном при холодном
  запуске. Проверено на железе после пересборки ISO и перезагрузки:
  `init.svc.media.swcodec=running`, `IComponentStore/software` и
  `/ffmpeg` в servicemanager, холодный старт YouTube TV ~9–12 с.
- `init.sh`: проверка наличия Bluetooth-адаптера в `do_bootcomplete()`
  переведена с `hciconfig` (отсутствует в toybox) на sysfs
  (`/sys/class/bluetooth/hci*`).
- Bluetooth по умолчанию включён (`def_bluetooth_on=true`), а в
  TvSettings пункт «Добавить аксессуар» остаётся видимым, когда адаптер
  выключен/недоступен (`AccessoriesFragment`) — пульт можно спарить
  при первой загрузке.
- `hardware/interfaces`: `BluetoothHci` — `return` после
  `UNABLE_TO_OPEN_INTERFACE`; без контроллера HAL падал в цикле на
  `FD_SET(-1)`. Проект добавлен в `patches/`.
- Add-on: установка microG (`install_microg`, APK кладёт пользователь,
  в git не публикуется).
- `ids/pci.ids` обновлён до upstream 2026.11.06.
- Intel H81M (`.198`) переведён на SELinux Enforcing (проверено
  2026-11-05 … 07); производительный/откатный слот сохранялся отдельно.

## 2026-11-05 — SELinux Enforcing и медиа (e3000n)

- SELinux переведён в **Enforcing** на e3000n (AMD Kabini): загрузка, сеть,
  adb, лончер, boot animation, Bluetooth, Widevine L3, media-сервисы.
- `init`: bind-mount radeon-списков кодеков разрешён (`mounton`/`ioctl`
  для `vendor_configs_file`/`system_file`); иначе приложения брали
  софт-`c2.android.avc` и SurfaceFlinger падал на YV12.
- `c2.ffmpeg.h264` в домене `mediacodec`: `appdomain_tmpfs`,
  `vendor_ffmpeg_prop` (`persist.vendor.ffmpeg-codec2.pixel_format=RGBX_8888`),
  `hal_drm_clearkey_aidl appdomain_tmpfs`; Widevine L3 provisioning.
- `mediaswcodec`, `hal_audio_default`, `audioserver`: `tmpfs:file`
  `rw`/`setattr` + `allowxperm ... ASHMEM_GET_SIZE`; `tmpfs`
  `mlstrustedobject` для MLS-записи в MessageQueue.
- Home на USB-клавиатуре → `HOME` (`device/google/atv/Generic.kl`).
- GRUB: автопереход в recovery по `MODE=recovery` теперь добавляет
  `androidboot.force_normal_boot=0` и убирает `selinux=enforcing`
  (`RECOVERY_EXTRA`/`SELINUX_ENTRY`).
- Add-on из recovery проверен (NDK, Widevine, метки, build.prop);
  Play Store 53.4.17 (TV) + microG 0.3.17 установлены из APK пользователя
  (в git не публикуются).
- Play Store + microG UX: после входа Play Store может вернуться на экран
  «Войти» (аккаунт уже добавлен) — перезапустите Play Store. Для закачки
  нужен appop `ACTIVATE_VPN=allow` (как на `.198`):
  `appops set com.android.vending ACTIVATE_VPN allow`.
- Итог: Wink TV и Jellyfin — видео и звук под Enforcing, качество
  приемлемое; `system/sepolicy` и `device/google/atv` добавлены в
  `patches/`.

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

- Обновление LineageOS/патчей безопасности (апстрим. текущий этап).
- Другое железо (Kabini/Haswell уже; далее — Asus 1225B (AMD C-60). и далее по мере появления).
- Шифрование данных, user-сборка — позже (пока под вопросом целесообразность).

## Публикация

Текущие публичные коммиты (2026-11-15): device tree `8c17122`, aaropa
`c5107b0`, TvSettings patch `1c8edb57`, bootable/recovery patch `2fd9aca`,
Updater patch `4662599`, system/sepolicy patch `5e09bcbf5`.

- https://github.com/ilya84/los-tv-x86 — этот набор (доки, патчи, установщик)
- https://github.com/ilya84/lineage_bass_android — манифест (ветка `lineage-23.2`)
- https://github.com/ilya84/android_device_generic_x86_64_tv — дерево устройства
- https://github.com/ilya84/bootable_aaropa — initrd/установщик

Публичные проекты из `github.com/los-tv-x86` (alsa-utils, intel/audio,
hcitools и т.п.) используются как read-only зависимости с атрибуцией.
