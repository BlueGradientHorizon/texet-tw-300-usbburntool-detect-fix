# USBBurnTool device-detection fix (TW-300, JZ4775) + stock ROM archive
# Фикс обнаружения устройства USBBurnTool (TW-300, JZ4775) + архив со стоковой прошивкой

[English](#english) | [Русский](#russian)

<a id="english"></a>
## English

### Fix for the flashing tool not detecting the connected device

**Symptom.** USBBurnTool starts, shows a table for up to 8 devices, every row
stays at 0%. Reconnecting the device while the program runs does not help, and
the start button reports `No Linked Device Find!`. The device itself is fine:
Device Manager shows `USB boot driver for JZ47XX(2013)` with status OK.

**Root cause.** The tool treats a device as "connected" only when the registry
contains, under
`HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\<iface>\`:

1. a child `#\Control` key with a DWORD value `Linked` (the `IsLinked` check —
   the start-button gate);
2. a `SymbolicLink` value in the `#` key (device name for the table and the
   path used by `CreateFile` during flashing).

On Windows 10/11 neither exists: nothing creates them — not the tool, not the
`JZ_USB_Boot.sys` driver, not the INF files (verified by reverse engineering;
see `RESEARCH.md`). Without them the table is always empty. Forcing the gate
open without the data only leads to `Invalid handle!` errors, because the
device path is empty too. Hidden stale instances (e.g. `...&0&2`) add phantom
rows on top.

**How the script fixes it.** `Fix-LinkedDevice.ps1` finds every currently
present `JZ_USB_Boot` device, locates its interface key in DeviceClasses and
creates the missing data:

- `SymbolicLink` (REG_SZ) — the device path, e.g.
  `\\?\USB#VID_A108&PID_4775#6&...&0&1#{198b2804-...}` (derived from the subkey
  name: the `##?#` prefix is replaced with `\\?\`);
- a child `Control` key with `Linked = 1` (DWORD).

After that the **original** `USBBurnTool.exe` detects the device and flashes
normally; no binary patching is needed.

**Usage.**

1. Connect the device in USB-boot mode (Device Manager: "USB boot driver
   for JZ47XX").
2. Run from any window, in the `USBBurnTool` folder:
   `powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1`
   Easiest way: right-click `Fix-LinkedDevice.ps1` → Run with PowerShell
   (if Windows blocks it due to the execution policy, use the command above).
   The script elevates itself (UAC prompt), fixes live devices, unlinks stale
   instances and starts the original `USBBurnTool.exe` automatically.
3. Press start in the flasher.

Switches: `-NoLaunch` (fix only, do not start the flasher), `-CleanStale`
(explicit stale cleanup), `-Undo` (rollback), `-NoPause` (do not wait for
Enter at the end, for automation).

**Temporary or permanent?** Practically persistent: verified that the values
survive a reboot (the SYSTEM hive is persistent) — flashing started without
re-running the fix. Re-run only if the device is re-enumerated as a new
instance (different USB port, driver reinstall — that is how the stale
`...&0&2` appeared) or if the symptom returns. The script is idempotent.

**Side effects and rollback.** The script writes only inside its own GUID
branch `{198b2804-...}` (the `#` and `Control` keys of JZ47xx interfaces);
system keys are untouched. To roll back:
`powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -Undo`

**Moved the device to another USB port?** The old instance stays behind as
hidden (stale) and keeps its Linked data, so the flasher fills slot 1 with a
dead entry (`Invalid handle!` popup) while the live device flashes in slot 2.
Connect the device and run the script normally (stale instances are unlinked
automatically before the launch) or explicitly with `-CleanStale` — the live
device returns to slot 1 and the popup disappears:
`powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -CleanStale`

*This fix was prepared by Muse Spark 1.3 Free with Opencode Zen on xhigh.*

---

<a id="russian"></a>
## Русский

### Фикс необнаружения подключённого устройства прошивальщиком

**Симптом.** USBBurnTool запускается, показывает таблицу до 8 устройств, везде
0%. Переподключение устройства при работающей программе не помогает, кнопка
старта отвечает `No Linked Device Find!`. Само устройство в порядке:
диспетчер показывает `USB boot driver for JZ47XX(2013)`, статус OK.

**Причина.** Программа считает устройство «подключённым», только если в реестре
есть (в ветке
`HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\<iface>\`):

1. подключ `#\Control` со значением DWORD `Linked` (проверка `IsLinked` —
   гейт кнопки старта);
2. значение `SymbolicLink` в ключе `#` (имя устройства для таблицы и путь для
   `CreateFile` при прошивке).

На Windows 10/11 их нет: их не создаёт никто — ни программа, ни драйвер
`JZ_USB_Boot.sys`, ни INF-файлы (проверено реверсом, см. `RESEARCH.md`). Без них
таблица всегда пуста. Обход гейта без данных даёт лишь `Invalid handle!`,
потому что путь устройства тоже пуст. Скрытые stale-инстансы (например,
`...&0&2`) добавляют ложные строки.

**Как скрипт это чинит.** `Fix-LinkedDevice.ps1` находит каждое подключённое
сейчас устройство `JZ_USB_Boot`, находит его ключ интерфейса в DeviceClasses и
создаёт недостающие данные:

- `SymbolicLink` (REG_SZ) — путь устройства, например
  `\\?\USB#VID_A108&PID_4775#6&...&0&1#{198b2804-...}` (выводится из имени
  подключа: префикс `##?#` заменяется на `\\?\`);
- подключ `Control` со значением `Linked = 1` (DWORD).

После этого **оригинальный** `USBBurnTool.exe` видит устройство и шьёт штатно,
патчить бинарник не нужно.

**Использование.**

1. Подключите устройство в режиме USB-boot (диспетчер устройств: «USB boot
   driver for JZ47XX»).
2. Запустите из любого окна, в папке `USBBurnTool`:
   `powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1`
   Проще всего: ПКМ по `Fix-LinkedDevice.ps1` → выполнить с помощью PowerShell
   (если Windows заблокирует из-за политики выполнения — используйте команду выше).
   Скрипт сам повысит привилегии (запрос UAC), починит живые устройства,
   отвяжет stale-инстансы и автоматически запустит оригинальный
   `USBBurnTool.exe`.
3. Нажмите старт в прошивальщике.

Ключи: `-NoLaunch` (только чинить, не запускать), `-CleanStale` (явная чистка
stale), `-Undo` (откат), `-NoPause` (не ждать Enter в конце, для автоматизации).

**Временный или постоянный?** Фактически постоянный: проверено, что значения
переживают перезагрузку (ветка SYSTEM персистентна) — прошивка стартовала без
повторного фикса. Повтор нужен, только если устройство переэнумерировано как
новый инстанс (другой USB-порт, переустановка драйвера — так появился stale
`...&0&2`) или при рецидиве симптома. Скрипт идемпотентен.

**Последствия и откат.** Скрипт пишет только внутрь ветки своего GUID
`{198b2804-...}` (ключи `#` и `Control` интерфейсов JZ47xx), системное не
трогает. Откат:
`powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -Undo`

**Переставили устройство в другой USB-порт?** Старый инстанс остаётся скрытым
(stale) и хранит свои Linked-данные, поэтому прошивальщик кладёт в слот 1
мёртвую запись (попап `Invalid handle!`), а живое устройство шьётся в слоте 2.
Подключите устройство и запустите скрипт как обычно (stale-инстансы отвяжутся
автоматически перед запуском) или явно с `-CleanStale` — живое вернётся в
слот 1, попап исчезнет:
`powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -CleanStale`

*Фикс подготовлен Muse Spark 1.3 Free с помощью Opencode Zen на xhigh.*
