*работа далее MiMo-V2.6-Flash Free OpenCode Zen*

# USBBurnTool — итоги реверса (TW-300, USB\VID_A108&PID_4775)

Дата: 2026-09-28. Симптом: утилита запускается, показывает таблицу на 8 устройств, везде 0%,
переподключение устройства в работающей программе не помогает. Сообщений об ошибках нет.

---

## 1. Окружение и файлы

| Путь | Что это |
|---|---|
| `D:\Обновление TW-300 v.1.0\USBBurnTool\USBBurnTool.exe` | прошивальщик, **32-бит** (pei-i386), 3534848 байт, ImageBase 0x400000, SizeOfImage 0x269be000 |
| `USBBurnTool\tool_cfg\setting.ini` | `FileName=SmartQ.ini`, `WithoutPW=1`, `Password=123` |
| `USBBurnTool\ini\SmartQ.ini` (CP1251) | CPU=8, TotalFile=4, CheckedFile=4, пути валидны |
| `USBBurnTool\ini\SmartQ2.ini`, `ini\s2122b-15_jz4775_emcp_android-4.3.ini` | другие конфиги (не активные) |
| `USBBurnTool\4775\{fw_mddr.bin,usb_boot.bin}` | загрузчики для JZ4775 |
| `USBBurnTool\2014Дк11ФВ log.txt` | **лог прошлого успешного прогона 2014-11-14**: "SD erase!", "SD program succeeded!", "system reset!" — т.е. инструмент работал |
| `USB driver\64bit_driver\JZ_USB_Boot.inf` | INF, `USB\VID_A108&PID_4775` в `[Ingenic.NTAMD64]`, DriverVer 10/15/2013, v1.7.1.0 |
| `C:\Windows\System32\drivers\JZ_USB_Boot.sys` | установленный **64-битный** драйвер (26112 байт) |

**В дистрибутиве НЕТ** `.reg`, `.bat`, `.cmd`, `.ps1`, `.msi` — только INF, INI, EXE, txt.

Машина: Windows 11 Pro x64. Инструменты: python 3.14, `D:\msys64\mingw64\bin\{objdump,gdb,gcc}`.
`rg` нет. Кодировка консоли — всегда ставить `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8`.

Дампы (созданы ранее, переиспользовать):
- `C:\Users\user\AppData\Local\Temp\opencode\usb.dis` — полный `objdump -d` EXE (~1.15 млн строк)
- `C:\Users\user\AppData\Local\Temp\opencode\drv.dis` — полный `objdump -d` JZ_USB_Boot.sys
- `C:\Users\user\AppData\Local\Temp\opencode\exe_ascii.txt`, `exe_utf16.txt` — строки EXE

---

## 2. Проверено и НЕ является причиной

1. **Установка драйвера.** `Get-PnpDevice -Class JZ_USB_Boot -PresentOnly` →
   `USB\VID_A108&PID_4775\6&13C452C7&0&1`, Status=OK, Present=True,
   FriendlyName "USB boot driver for JZ47XX(2013)". INF подписан WHQL, сервис создан,
   `setupapi.dev.log` → `Exit status: SUCCESS`. (Второй инстанс `...&0&2` — stale, Present=False.)
2. **Наличие образов прошивки** — все 4 файла существуют.
3. **Гипотеза «нет значения `SymbolicLink` в DeviceClasses»** — ОПРОВЕРЖЕНА.
   У `HKLM\...\DeviceClasses\{guid}` подключённые ключи содержат **только** `DeviceInstance`.
   Так у ВСЕХ устройств на этой Win11 (включая рабочую сетевую карту), т.е. это особенность ОС,
   и инструменту это не нужно (см. п.4 — основной путь через SetupDi).
4. **Гипотеза «инструмент видит только `Vid_601a&Pid_4740`»** — частично верна для
   **мёртвого кода**: функция `0x56fda0` сравнивает `subkey.Left(25)=="##?#USB#Vid_601a&Pid_4740"`
   (`0x7698fc`), но у неё **нет ни одного вызова и нет ссылок в данных** (`4f c7 51 00`,
   `22 fb 51 00` не найдены) → мёртвый код, на работающий путь не влияет.
5. **Эмпирический тест SetupDi (P/Invoke, повторяет код инструмента)** — ВСЁ РАБОТАЕТ:
   ```
   SetupDiGetClassDevsA(GUID,0,0,0x12=DIGCF_DEVICEINTERFACE|DIGCF_PRESENT) → 1 интерфейс
   path = \\?\usb#vid_a108&pid_4775#6&13c452c7&0&1#{198b2804-759e-4e55-afd9-9184d66f816a}
   SetupDiGetDeviceInterfaceDetailA cbSize=8 (x64 ANSI; 4..7 → err=1784)
   CreateFileA(path, GENERIC_READ|WRITE, share=1|3, OPEN_EXISTING, 0x80) → OK
   ```
6. **IOCTL-тесты** (открыт хендл, nIn=0):
   - `0x220408` → FALSE, err=1 (ERROR_INVALID_FUNCTION) — совпало с дизассемблом свитча
   - `0x220000` nOut=512 → FALSE, err=122 (ERROR_INSUFFICIENT_BUFFER)
   - `0x220004` → TRUE
   - **`0x220008` → ЗАБЛОКОВАЛСЯ >120 с, команда прервана по таймауту. НЕ ВЫЗЫВАТЬ ПОВТОРНО.**
   Устройство после теста восстановилось (видно в PnP). При необходимости переподключить.

---

## 3. IOCTL-диспетчер драйвера (JZ_USB_Boot.sys, VMA 0x136a4, IRP_MJ_DEVICE_CONTROL)

Поддерживаемые коды (всё, что больше `0x220024` → `0xC0000010` STATUS_INVALID_DEVICE_REQUEST
= err 1 `ERROR_INVALID_FUNCTION`):

```
0x220000 0x220004 0x220008 0x22000c 0x220010
0x220014 0x220018 0x22001c 0x220020 0x220024
```

Коды, которые использует инструмент, но **драйвер НЕ поддерживает**:
- `0x22002c` — используется в функции `0x5a1f90` (`DeviceIoControl(h,0x22002c,in=0x200,out=0x200)`),
  thunk `0x51d04b`; **прямых `call 0x51d04b` не найдено** → вероятно, мёртвый код.
- `0x220408` — используется в `0x597e00` (probe, nOut=6), thunk `0x51ed60`;
  **нет вызовов и нет data-ссылок** → **мёртвый код**.

Драйвер импортирует `RtlQueryRegistryValues`, но в бинарнике **нет строк** `Linked`,
`DeviceClasses`, `CurrentControlSet`, `198b2804`, `ZwSetValueKey`.
⇒ **драйвер НЕ создаёт значение `Linked`.**

---

## 4. Как инструмент ищет устройство (SetupDi-путь) — работает

GUID интерфейса: **`{198b2804-759e-4e55-afd9-9184d66f816a}`**
(бинарная копия ровно одна — в `.data` по file 0x340ee4 → VMA **`0x857ee4`**).

Функция открытия `0x56a9e0`:
```
SetupDiGetClassDevsA(0x857ee4, 0, 0, 0x12)          ; DIGCF_DEVICEINTERFACE|DIGCF_PRESENT
  → 0x56add0 EnumInterface (cbSize жёстко = 5 — корректно для 32-бит ANSI)
  → CreateFileA(path, 0xc0000000, share=1, 0, 3, 0x80, 0)
  → возвращает HANDLE
```
Вызывается из `0x59547b` (index=0x8(%ebp)) и `0x59747a` (цикл `i=0..15`).

IAT (значения objdump, к ним надо прибавлять 0x400000):
| VMA | Функция |
|---|---|
| 0x26da7b68 | SetupDiGetClassDevsA |
| 0x26da7b64 | SetupDiDestroyDeviceInfoList |
| 0x26da7b5c | SetupDiEnumDeviceInterfaces |
| 0x26da7b60 | SetupDiGetDeviceInterfaceDetailA |
| 0x26da7754 | DeviceIoControl |
| 0x26da7230 | RegCreateKeyA |
| 0x26da7234 | RegDeleteValueA |
| 0x26da7238 | **RegSetValueExA** |
| 0x26da723c | RegCreateKeyExA |
| 0x26da7240 | RegDeleteKeyA |
| 0x26da7248 | RegSetValueA |
| 0x26da724c | RegEnumKeyA |
| 0x26da7250 | RegOpenKeyA |
| 0x26da7254 | **RegOpenKeyExA** |
| 0x26da7258 | **RegQueryValueExA** |
| 0x26da725c | RegCloseKey |

Секции EXE: `.textbss 0x401000`, `.text 0x518000 (file 0x1000)`,
`.rdata 0x762000 (file 0x24b000)`, `.data 0x857000 (file 0x340000)`, `.idata 0x26da6000`.
Перевод адресов: VMA строк = fileoff + 0x517000.

---

## 5. Глобальные структуры данных инструмента

Конструкторы (глобальные, вызываются до `main`):

| Адрес | Что конструируется |
|---|---|
| `0x75ad80` | `CString subkeyNames[0x80]` @ **`0x18863e10`** (item 4, ctor `0x523739`, dtor `0x51c2cc`) |
| `0x75adf0` | `Rec devs[0x80]` @ **`0x18864010`** (item **0x18**, ctor `0x51b575`, dtor `0x521943`) |
| `0x75ae60` | `Linked Linked[8]` @ **`0x18864c10`** (item **0x0c**, ctor `0x51ab39`, dtor `0x5225cd`) |

`0x18864010 + 0x80*0x18 = 0x18864c10` ✓ (массивы встык).

**Структура `Rec devs[i]` (stride 0x18):**
```
+0x00 CString  путь реестра (построен)
+0x04 CString  путь + "#\"
+0x08 CString  путь + "#\" + "Control\"   <-- lpSubKey для RegOpenKeyExA
+0x0c CString  отображаемая строка (уходит в таблицу)
+0x10 DWORD    выход IsLinked (BOOL)
+0x14 DWORD    индекс = i+1        (пишется в 0x5702f0)
```

**Структура `Linked[i]` (stride 0x0c) — это и есть таблица на 8 строк:**
```
+0x00 CString  имя/описание устройства (копируется из devs[j].+0x0c)
+0x04 DWORD    активен (1) / пусто (0)
+0x08 DWORD    индекс устройства (i+1)
```

Раскладка уже проверенного: `0x769818` = `"#"`, `0x76991c` = `"#\"`, `0x769920` = `"Control\"`,
`0x768ec4` = `"\\"`, `0x769820` = `"SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\"`
(с **конечным обратным слэшем**), `0x769810` = `"Linked"`, `0x76992c` = `"ERROR::Please Delete some device driver!!"`,
`0x76497c` = `"No Linked Device Find!"`, `0x764ea0` = `"Open Device failed!"`,
`0x76f450` = `"Please Connect the Device"`, `0x769888` = `"SymbolicLink"`.

---

## 6. Поток детекции при старте (главное)

В функции обработчика инициализации, фрагмент **`0x589557`–`0x589578`**:

```asm
0x589557: push $0x18864c10 ; push $0x18864c10
0x58955c: call 0x523851                 ; очистка Linked[]
0x589561: add  $0x4,%esp
0x589564: call 0x51fe22   ; -> 0x56f940  СКАН DeviceClasses (RegEnumKeyA)
0x589569: call 0x522870   ; -> 0x570500  devs[i].+0x04 = devs[i].+0x00 + "#\"
0x58956e: call 0x51b6ec   ; (не разобран)
0x589573: call 0x518ce4   ; -> 0x5706c0  devs[i].+0x08 = devs[i].+0x04 + "Control\"
0x589578: movl $0x1,0x193994bc          ; флаг «инициализировано»
```
Далее цикл `i<8` обнуляет слоты таблицы (`0x193994d0/0x193994d4/0x19399500`, stride 0x34,
плюс большие буферы `0x1939b9c0/0x1939b9c4`, stride 0xa0025c).

### 6.1. `0x56f940` — скан подключей DeviceClasses
```asm
CString base = 0x769820                       ; "SYSTEM\...\DeviceClasses\{198b2804-...}\"
RegOpenKeyA(HKLM, base, &hKey)                ; 0x26da7250
CString tmp = 0x769818                        ; "#"  (аргумент-заглушка, в 0x570860 не используется)
0x570860(&hKey, tmp)                          ; RegEnumKeyA-цикл
RegCloseKey(hKey)
```
> Проверено эмпирически: `OpenSubKey("...\{guid}\")` **с конечным `\` ОТКРЫВАЕТСЯ**, детей — 2:
> `##?#USB#VID_A108&PID_4775#6&13c452c7&0&1#{guid}` и `...&0&2#{guid}`.
> (Внутри каждого есть пустой подключ `#` — это системный, у 77 из 86 interface-ключей на машине.)

### 6.2. `0x570860(HKEY* phk, CString& scratch)` — перечисление
```asm
idx=0
loop:
  rc = RegEnumKeyA(*phk, idx, buf=GetBuffer(0x105), 0x105)
  if (idx > 0x80) { MessageBox(0,"ERROR::Please Delete some device driver!!",0); return 0 }
  if (rc == 0x103 /*ERROR_NO_MORE_ITEMS*/) return 0
  subkeyNames[idx] = buf          ; 0x51bef8 = CString::operator=(LPCSTR)
  scratch.Empty()                 ; 0x51f111(-1)
  idx++
```
Фильтра **нет** — берутся все подключи.

### 6.3. `0x5702f0` — `devs[i].+0x00` и `devs[i].+0x14`
```asm
CString sep = 0x768ec4                     ; "\"
for i<0x80:
  if (GetLength(subkeyNames[i])==0) continue
  devs[i].+0x14 = i+1                      ; 0x18864024 + i*0x18
  tmp = 0x52011a(&dest, 0x769820 /*base*/, subkeyNames[i])   ; 3 аргумента, add $0xc
  devs[i].+0x00 = 0x5246b1(&dest2, tmp, sep /*оставшийся на стеке аргумент*/)
```
> Разбор стека: `push &sep` идёт ПЕРЕД вызовом `0x52011a`, но `add $0xc` снимает только 3 аргумента,
> поэтому `&sep` остаётся и становится 3-м аргументом следующего `0x5246b1`.
> ⇒ **`devs[i].+0x00 = base + subkey + "\"`**.

### 6.4. `0x570500` — `devs[i].+0x04`
```asm
call 0x520638 (= 0x5702f0)                 ; сначала построить +0x00
CString sep = 0x76991c                     ; "#\"
for i<0x80:
  if (GetLength(&devs[i].+0x00)==0) break  ; ПЕРВАЯ пустая — выход из цикла
  devs[i].+0x04 = 0x5246b1(&dest, &devs[i].+0x00, &sep)
```

### 6.5. `0x5706c0` — `devs[i].+0x08`
```asm
CString sep = 0x769920                     ; "Control\"
for i<0x80:
  if (GetLength(&devs[i].+0x04)==0) continue
  devs[i].+0x08 = 0x5246b1(&dest, &devs[i].+0x04, &sep)
```

### 6.6. Что такое `0x5246b1` / `0x52011a` — ДОКАЗАНО
```
0x5246b1  jmp 0x53a170
0x53a170: -0x14 = CString(arg1);
          0x523270(&-0x14, p(arg1), len(arg1), p(arg2), len(arg2))   ; jmp 0x5350b0
          arg0 = -0x14
0x5350b0: n = len(arg2)+len(arg4);
          buf = arg0->GetBuffer(n);
          memcpy(buf, arg1, arg2);            ; 0x51b192 (dst, dstlen, src, len)
          memcpy(buf+len1, arg3, arg4);
```
⇒ **`0x5246b1(dest, a, b)` = `dest = a + b`** (обычная конкатенация).

Итоговые строки:
```
devs[i].+0x00 = SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-...}\<subkey>\
devs[i].+0x04 = ...\<subkey>\#\
devs[i].+0x08 = ...\<subkey>\#\Control\
```
Для нашего устройства (subkey = `##?#USB#VID_A108&PID_4775#6&13c452c7&0&1#{198b2804-...}`):
```
HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\
  ##?#USB#VID_A108&PID_4775#6&13c452c7&0&1#{198b2804-759e-4e55-afd9-9184d66f816a}\
  #\Control\
```

---

## 7. ГЕЙТ: почему таблица всегда 0% — главная находка

### 7.1. `0x56f7d0` = `IsLinked(int index, DWORD* out)` (thunk `0x523441`)
проверяет `1<=index<=0x80`, вызывает `0x56f670(index,out)`, при провале `*out=0; return 0`.

### 7.2. `0x56f670(index, out)`
```asm
if (GetLength(&devs[index-1].+0x08) == 0) fail
CString a("Linked");                     ; 0x769810
CString b(devs[index-1].+0x08);          ; копия
r = 0x51c29a(out, b, a);                 ; 3 аргумента, add $0xc
if (r) return 1;  *out = 0; return 0;
```

### 7.3. `0x51c29a` → `0x56f3a0` = **чтение реестра** (ДОКАЗАНО)
```asm
0x56f3a0(DWORD* out /*0x8*/, CString& subkey /*0xc*/, CString& valueName /*0x10*/):
  CString unused = 0x768374 ("0")
  if (RegOpenKeyExA(HKLM, GetString(subkey), 0, 0x20019 /*KEY_READ*/, &h) != 0) { *out=0; return 0 }
  DWORD dwType=4, cbData=4
  rc = RegQueryValueExA(h, GetString(valueName), 0, &dwType, &buf, &cbData)
  if (rc != 0) { *out=0; return 0 }
  ... *out = <прочитанный DWORD>
```
⇒ **`IsLinked(i)` == `RegQueryValueExA(HKLM\<devs[i-1].+0x08>, "Linked") == SUCCESS`.**

### 7.4. Кто наполняет таблицу: `0x570b60(Linked* L, Rec* D)` (thunk `0x5219de`)
```asm
1) for j<8:              L[j].+4 = 0
2) for j<8:              if (!IsLinked(L[j].+8, &L[j].+4)) L[j].+4 = 0
3) for i<0x80:
     if (!IsLinked(i+1, &D[i].+0x10)) continue        ; 0x523441(i+1,&D[i].+0x10)
     if (D[i].+0x10 == 0) continue
     idx = i+1
     для свободного/совпавшего слота j<8:
        L[j].+0 = D[i].+0x0c      ; 0x519446 = CString::operator=
        L[j].+8 = idx
        L[j].+4 = 1
```
Вызывается из `0x570eb0` (`0x5219de(0x18864c10, 0x18864010)`) и из кнопки `0x5a7610`.

**Шлюз на кнопке `0x5a7610` (ON_COMMAND, thunk `0x5210e7` из `0x5a7aab`):**
```asm
0x5a780b: push $0x18864010 ; push $0x18864c10 ; call 0x5219de
0x5a781d: cmpl $0x0,0x18864c14               ; L[0].+4
0x5a7822: jne  0x5a7848                       ; OK, пуск
0x5a782a: push $0x76497c "No Linked Device Find!" ; call 0x51bc3c ; return
```

### 7.5. КРИТИЧЕСКИЙ ВЫВОД
Значение `Linked` в системе **отсутствует полностью**:
```
reg query "HKLM\SYSTEM\CurrentControlSet\Control" /f "Linked" /d /s  →  0 match(es)
```
Строка `"Linked"` (`0x769810`) в EXE используется **ровно один раз** — на чтение (`0x56f6d2`).
Все 5 вызовов `RegSetValueExA` (`0x60940b`, `0x609577`, `0x60965c`, `0x6537a9`, `0x691a7d`)
относятся к MFC/OLE (`olereg.cpp`, `appui3.cpp`, `ThreadingModel`) либо в HKCU/HKCR —
**на наш путь не попадают**. `RegCreateKeyA` (`0x653781`) — HKCU.
Драйвер строку `Linked` не содержит.
Подключ `...\#\Control` **не существует нигде** в `DeviceClasses` на машине (count = 0).

⇒ **`IsLinked()` всегда возвращает 0 ⇒ `Linked[0].+4 == 0` ⇒ таблица всегда пустая (0%).**
⇒ Это и есть непосредственная причина симптома.

---

## 8. Что точно НЕ является причиной (проверено на этом шаге)

- Путь `HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-...}\` **открывается**
  с конечным обратным слэшем, дети enumerируются — скан `0x56f940` отрабатывает.
- Устройство присутствует и открывается (`CreateFileA` → OK).

---

## 9. Открытые вопросы / следующие шаги

1. **Кто должен создавать `HKLM\...\DeviceClasses\{guid}\<interface>\#\Control` и значение
   `Linked` (REG_DWORD)?**
   - инструмент — нет (доказано),
   - драйвер — нет (нет строк),
   - дистрибутив — нет (нет .reg/.bat/.msi).
   Варианты: это делал отдельный установщик/сервис, либо ключ создавался вручную/в XP-эпоху,
   либо путь `+0x08` на рабочей машине отличается (проверить на машине, где прошивка когда-то шла).
2. **Эксперимент (обратимый):** создать
   `HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\##?#USB#VID_A108&PID_4775#6&13c452c7&0&1#{198b2804-759e-4e55-afd9-9184d66f816a}\#\Control`
   и в нём DWORD `Linked` = 1, затем запустить USBBurnTool и посмотреть, появилось ли
   устройство в таблице. Если да — причина подтверждена и остаётся только вопрос «кто это делал».
   Откат: удалить созданный подключ `Control`.
   Делать **до** теста — иначе результат неоднозначен. Нужен запуск от администратора.
3. Разобрать `0x51b6ec` (вызов между `0x570500` и `0x5706c0` в `0x58956e`).
4. Разобрать `0x56f7d0` полностью и ветку успеха `0x56f4f5` в `0x56f3a0`
   (как именно кладётся прочитанный DWORD в `*out`).
5. Определить, попадает ли `0x5a1f90` (IOCTL `0x22002c`, не поддерживается драйвером)
   в основной путь прошивки — thunk `0x51d04b`, прямых вызовов нет.
6. Найти, кто пишет `devs[i].+0x0c` (строка, отображаемая в таблице).

---

## 10. Полезные адреса (шпаргалка)

```
0x56a9e0   SetupDi-открытие (GUID 0x857ee4), CreateFileA
0x56add0   SetupDiEnumInterface (cbSize=5)
0x56f3a0   RegOpenKeyExA+RegQueryValueExA(out, subkey, valueName)   <- thunk 0x51c29a
0x56f670   IsLinked-ядро (index, out)                               <- использует "Linked"
0x56f7d0   IsLinked-обёртка                                         <- thunk 0x523441
0x56f940   СКАН DeviceClasses: RegOpenKeyA(base)+RegEnumKeyA        <- thunk 0x51fe22
0x56fda0   мёртвый фильтр Vid_601a&Pid_4740
0x5702f0   devs[].+0x00 = base+subkey+"\",  devs[].+0x14 = i+1     <- thunk 0x520638
0x570500   devs[].+0x00 += "#\"                                     <- thunk 0x522870
0x5706c0   devs[].+0x04 += "Control\"                               <- thunk 0x518ce4
0x570860   RegEnumKeyA-цикл -> subkeyNames[]                        <- thunk 0x51f73d
0x570b60   RebuildLinked(Linked[8], devs[128])                      <- thunk 0x5219de
0x570eb0   вызов RebuildLinked + чтение L[i].+4
0x589557   СТАРТОВАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ ДЕТЕКЦИИ
0x5a7610   обработчик кнопки, гейт "No Linked Device Find!"
0x5a1f90   IOCTL 0x22002c (драйвером не поддерживается)
0x51ab8e   массив-конструктор (count, stride, ctor, dtor, base)
0x519446   CString::operator=
0x51cb69   CString::GetString
0x51a972   CString::GetBuffer
0x51c2cc   CString::~CString
0x521484   CString::GetLength
0x5215ce   CString::CString(LPCSTR)
0x5246b1   concat: dest = a + b        -> 0x53a170 -> 0x523270 -> 0x5350b0
0x52011a   concat-вариант (3 аргумента)
```

Строки:
```
0x76497c "No Linked Device Find!"        (0x53ba92 0x53bf06 0x53cdab 0x53d225 0x540346
                                           0x541d61 0x542f8c 0x5a782a)
0x764ea0 "Open Device failed!"           (0x53e48e 0x5409d0 0x54253e 0x5a726e)
0x76f450 "Please Connect the Device"
0x769810 "Linked"
0x769818 "#"
0x769820 "SYSTEM\CurrentControlSet\Control\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\"
0x769888 "SymbolicLink"
0x7698fc "##?#USB#Vid_601a&Pid_4740"     (мёртвый код)
0x76991c "#\"
0x769920 "Control\"
0x76992c "ERROR::Please Delete some device driver!!"
0x768ec4 "\"
0x769900 "USB#Vid_601a&Pid_4740"
```

*работа далее Muse Spark 1.3 Free OpenCode Zen xhigh*

---

## 11. Доразбор 2026-09-28 (открытые вопросы п.9 закрыты, кроме эксперимента)

Проверка состояния: `USB\VID_A108&PID_4775\6&13C452C7&0&1` Present=True, Status=OK.
Детей у `DeviceClasses\{198b2804-...}` — 2 (`...&0&1`, `...&0&2`), под `...\#\Control` — 0.
Текущий процесс НЕ elevated — запись в HKLM невозможна, эксперимент отложен.

### 11.1. `0x51b6ec` → `0x56fcd0` — строитель `devs[i].+0x0c` (ЗАКРЫТ п.9.3/9.6)
`0x51b6ec: jmp 0x56fcd0`. Цикл `i<0x80`:
`if (GetLength(&devs[i].+0x04 /*0x18864014+i*0x18*/)==0) continue;`
иначе `0x519301(tmp, &devs[i].+0x04)` + `0x51aeb3(&devs[i].+0x0c /*0x1886401c+i*0x18*/, tmp)`.
`0x51aeb3 → 0x56fb20`: единственный пользователь `"SymbolicLink"` (`0x769888`,
одна ссылка в бинарнике — `0x56fb7d`), thunk `0x5211a0 → 0x56f030`
(RegOpenKeyExA + RegQueryValueExA строкового значения, буфер `len("\\\\?\\USB#Vid_601a...")+1`).
⇒ **`devs[i].+0x0c = SymbolicLink из ключа `devs[i].+0x04` (`...\<subkey>\#\`)**.
Эмпирика: подключ `#` существует, но **значений в нём 0, `SymbolicLink` пуст**
(оба инстанса `&0&1`, `&0&2`) ⇒ на Win11 `+0x0c` тоже не заполняется.
Вторая (неблокирующая) деградация Win11; блокирует только `Linked`-гейт.

### 11.2. Ветка успеха `0x56f4f5` в `0x56f3a0` (ЗАКРЫТ п.9.4)
```
56f4f5: mov 0x8(%ebp),%eax   ; out
        mov -0x38(%ebp),%ecx ; DWORD-буфер RegQueryValueExA
        mov %ecx,(%eax)      ; *out = buf
```
Прямое копирование прочитанного DWORD, затем RegCloseKey, return 1.

### 11.3. `0x5a1f90` (IOCTL `0x22002c`) — мёртвый код (ЗАКРЫТ п.9.5)
Поиск по `usb.dis`: `5a1f90` — 2 вхождения (определение + `51d04b: jmp 0x5a1f90`),
`51d04b` — 1 вхождение (сам thunk). **`call 0x5a1f90` / `call 0x51d04b` — 0.**
В основной путь прошивки не попадает. Подтверждено.

### 11.4. Строка `0x7697b0`
`fileoff = 0x7697b0-0x517000 = 0x2527b0` →
`"\\\\?\\USB#Vid_601a&Pid_4740#5&1280f5eb&0&4#{198b2804-759e-4e55-afd..."`.
Используется в `0x56f030` только как мера длины (`GetLength+1` = размер буфера
для чтения SymbolicLink), не как fallback-значение.

### 11.5. Что осталось
Только обратимый эксперимент из п.9.2 (нужен elevated-процесс):
создать `...\<iface>\#\Control` + DWORD `Linked=1`, запустить USBBurnTool,
проверить таблицу, откатить удалением `Control`. Без прав HKLM-писать нельзя.

---

## 12. Кто должен создавать `Linked` — итог поиска (2026-09-28)

Проверены все кандидаты — создателя в дистрибутиве НЕТ:

1. **INF (64-бит `JZ_USB_Boot.inf`, 32-бит `Usb_Boot_Driver.inf`).**
   AddReg только `HKLM/.../Services/BulkUsb/Parameters` (мертвый — сервиса BulkUsb
   нет, ставится JZ_USB_Boot) и `BreakOnEntry`. Записей про
   `DeviceClasses\{198b2804...}\#\Control` / `Linked` нет в обоих INF.
2. **EXE — все 5 `RegSetValueExA`** (`0x60940b`, `0x609577`, `0x60965c`,
   `0x6537a9`, `0x691a7d`): строки рядом — `f:\rtm\vctools\vc7libs\ship\atlmfc\src\mfc\appui*`,
   `docmgr` / `Warning: registration database update failed`,
   `ThreadingModel`/`Insertable` — MFC/OLE/HKCR. Плюс свои `WithoutPW`/`Password`
   (`0x768020`/`0x767f88`). Ни одна не пишет в `DeviceClasses`.
3. **Драйвер 64-бит (`JZ_USB_Boot.sys`, 26112 б).**
   Строки: `RtlQueryRegistryValues`=1, `ZwSetValueKey`=0, `Linked`=0,
   `SymbolicLink`=0, `DeviceClasses`=0, `198b2804`=0.
   Импорты — `IoRegisterDeviceInterface`/`IoSetDeviceInterfaceState` (штатная
   регистрация интерфейса), `RtlQueryRegistryValues` (чтение своих Parameters).
   Создания `Control\Linked` нет.
4. **Драйвер 32-бит (`Usb_Boot_Driver.sys`, 81408 б).**
   `Linked`=0, `ZwSetValueKey`=0, `RtlQueryRegistryValues`=0,
   `SymbolicLink`=2 (штатный), `IoRegisterDeviceInterface`=1. Тоже не создаёт.
5. **`setting.ini`** указывает на dev-машину
   (`D:\JZ_Burntools\TabControl_2012_0223_1045\...`) — следов хелпера нет.

Эмпирика Win11: подключ `#` существует, но значений 0 (`SymbolicLink` пуст) —
поэтому `0x56fcd0` (`devs.+0x0c`) тоже пуст. На XP-эпохе (лог успеха 2014-11-14)
`SymbolicLink` в `#` существовал, а `Control\Linked`, видимо, создавал
отдельный установщик/хелпер XP-времён, в дистрибутив не вошедший.

Вывод: **на Win11 штатный путь невосстановим без шима** — ключи `DeviceClasses`
пересоздаёт PnP при каждом подключении, ручное создание слетит.
Практические пути: (A) Linux-порт `gcwnow/ingenic-boot` (тот же `usb_boot.bin`/
`fw_mddr.bin`, libusb, без реестра: `--probe/--boot/--system/--data`);
(B) volatile-тест `Control\Linked=1` из-под админа; (C) патч гейта
`0x5a781d`/`IsLinked` в EXE; (D) хук `RegQueryValueExA("Linked")→1`.

---

## 13. Патч C — применён (2026-09-28)

Файл: `USBBurnTool_patched.exe` (копия, оригинал не тронут).
- sha256 orig: `be1d67f3d86f4e372c34006a2f772010e045cc6c42e3dc5b48ce3ba1195d54ba`
- sha256 patched: `c115047ebe21dfe79e9af45423f7603b631df094f87a356b0f072874de7491ea`
- Точка: VMA `0x5a781d`, fileoff `0x9081d` (`VMA-0x517000`).
  Было `83 3D 14 4C 86 18 00 75 22` (`cmpl $0x0,0x18864c14; jne +0x22`).
  Стало `... EB 22` (`jmp 0x5a7848`) — байт по fileoff `0x90824`: `0x75→0xEB`.
- Проверка `objdump -d`: `5a7824: eb 22 jmp 0x5a7848` ✓.
- Эффект: ветка `"No Linked Device Find!"` (`0x5a782a`) недостижима, кнопка всегда
  идёт в пуск (`0x5a7848`). Имена строк могут быть пустыми (SymbolicLink на Win11
  нет) — косметика. Дальше — реальный путь SetupDi+IOCTL `0x220000–0x220024`.
  `0x220008` по-прежнему не вызывать вручную (виснет).

---

## 14. v2-патч — IsLinked форсирован (2026-09-28)

Симптом после v1: кнопка идёт в пуск, но всё равно 0% — ожидаемо: поток
`0x5a71a0` (thunk `0x5202eb`, старт через `0x51f49a→AfxBeginThread` с параметром
`0x1ff9ec18`, собранным в `0x5a7080` из `Linked[0]`) открывает устройство через
`0x51ec11→0x597c40` (5 попыток `0x521f56`, HANDLE в `+0x24`, иначе
`"Open Device failed!"` `0x764ea0`). При пустом `Linked` открывать нечего —
поток либо показывает ошибку, либо молча шьёт ноль слотов. Образы на месте
(`boot.img`, `mbr-xboot-gpt.bin`, `recovery.img`, `system.img` 400МБ) — дело не в них.

Файл: `USBBurnTool_patched2.exe` (от оригинала, включает v1).
- sha256: `b59f72a93bbb62e63edb343dce975a299b945196c1d1a309707bed49b339e004`
- v1: fileoff `0x90824`: `0x75→0xEB` (кнопка).
- v2a: fileoff `0x5874B`: `0x00→0x01` — в fail-ветке реестра `0x56f746`
  `movl $0x0,(%eax)` → `movl $0x1,(%eax)` (`*out=1`).
- v2b: fileoff `0x58751/0x58752`: `EB 0D` → `40 90` (`jmp` → `inc eax; nop`) —
  `xor eax,eax; inc` ⇒ return 1, падение в `jmp 0x56f760` (эпилог).
- Проверка `objdump`: `56f749: c7 00 01 00 00 00; 56f74f: 33 c0; 56f751: 40; 56f752: 90` ✓.
- Точечность: ветка пустых `devs` (`0x56f755`, GetLength) НЕ тронута — пустые
  слоты по-прежнему отсекаются; форсируются только реально перечисленные
  интерфейсы (`+0x08` непуст). Оба инстанса (`&0&1`, stale `&0&2`) станут
  linked — stale лучше удалить из Device Manager перед тестом.

---

## 15. Крах patched2: `Invalid handle!` ×2 + RTC `pError` (2026-09-28)

Симптом: два `Invalid handle!`, затем MSVC Debug RTC #3 `pError used without
being defined`, пропуск → выход.

Разбор:
- `"Invalid handle!"` — VMA `0x768eb0`, единственная ссылка `0x56b33f` в функции
  `0x56b2e0` (CreateFile-обёртка): `CreateFileA(path из struct+0x30)` →
  `INVALID_HANDLE` → MessageBox, затем
  `GetLastError → *([ebp-0x14])`, но `[ebp-0x14]` заполнен `0xCCCCCCCC` и нигде
  не инициализируется → RTC `pError` (имя переменной — fileoff `0x5438a`,
  сразу за `ret` функции) → abort. Латентный баг оригинала, виден только в
  Debug-сборке; в Release был бы AV по `0xCCCCCCCC`.
- Почему путь плохой: v2 форсирует `IsLinked=1`, `RebuildLinked` заполняет
  `Linked[8]` именами из `devs.+0x0c`, но `+0x0c = SymbolicLink` из ключа
  `...\#`, а на Win11 там 0 значений (проверено) → имена пустые → CreateFile
  по пустому пути → fail. Два попапа = два залинкованных слота (`&0&1` + stale
  `&0&2`, оба с пустыми именами).
- Дополнительно: в fail-ветке есть `if (-0xdd==0) call 0x5247bf(0x56b38a)`,
  где `0x56b38a` — уже байты строки `pError` (исполнение данных при `-0xdd!=0`).

Вывод: чинить надо не возврат IsLinked, а ДАННЫЕ — положить в `...\#`
настоящий `SymbolicLink` (`\\?\USB#VID_A108&PID_4775#...#{guid}`, формат как
захардкоженный `0x7697b0` эпохи XP) + `Control\Linked=1`. Тогда сработает даже
ОРИГИНАЛ без патчей. Stale `&0&2` перед тестом удалить (иначе его слот снова
даст `Invalid handle!`). patched2 до появления значений не запускать.

---

## 16. Ошибка в скрипте: двойные скобки (2026-09-28)

`fix_linked.ps1` записал
`...&0&1#{{198b2804-...}}` (PowerShell `#{$g}` при `$g` уже в скобках) —
такой путь `CreateFile` не открывает → `Invalid handle!` сохранился.
Исправлено в `fix_symlink.ps1` (одиночные скобки).
Проверка `CreateFileA(path, 0xC0000000, share=1, OPEN_EXISTING, 0x80)` —
параметры как в `0x56b2e0` — оба варианта (верх/низ регистра) дают handle
`0x1BC` ✓. Stale `&0&2` на момент проверки НЕ удалён (пустой `#`, без Control)
— с оригиналом он не линкуется, но лучше удалить.

---

## 17. ИТОГ: прошивка пошла на оригинале (2026-09-28) ✅

### В чём была проблема (две независимые деградации XP→Win11)
1. **Гейт `IsLinked` (`0x56f670`/`0x56f7d0`, кнопка `0x5a7610`).**
   Программа считает устройство «подключённым» только если существует ключ
   `HKLM\...\DeviceClasses\{198b2804-...}\<iface>\#\Control` со значением
   DWORD `Linked`. Его не создаёт никто: ни EXE (все 5 `RegSetValueExA` —
   MFC/OLE), ни оба драйвера (`ZwSetValueKey=0`, `Linked=0`), ни оба INF.
   На Win11 ключа нет → `IsLinked()=0` → `Linked[0].+4==0` → таблица 0%,
   кнопка отвечает `"No Linked Device Find!"`. Вероятно, в XP-эпоху ключ
   создавал отдельный установщик/хелпер, в дистрибутив не вошедший.
2. **Пустые имена устройств (`0x56fcd0`→`0x56fb20`→`0x56f030`).**
   Отображаемое имя читается из значения `SymbolicLink` в ключе `...\<iface>\#`.
   На Win11 там 0 значений → имена пустые → `CreateFile` по пустому пути →
   `"Invalid handle!"` + падение Debug-сборки на неинициализированном `pError`
   (`0x56b2e0`, §15). Маскировалось пунктом 1, вылезло после форсирования гейта.

Плюс мусор, затруднявший диагностику, но на рабочий путь не влияющий:
мёртвый фильтр `Vid_601a&Pid_4740` (`0x56fda0`), мёртвые IOCTL `0x22002c`
(`0x5a1f90`) и `0x220408` (`0x597e00`-probe), мёртвый `BulkUsb`-AddReg в INF.

### Что и как пофиксили (без патчей бинарника!)
1. Удалили stale-инстанс `...&0&2` (Present=False) из Диспетчера устройств,
   остался один живой `USB\VID_A108&PID_4775\6&13C452C7&0&1`.
2. От администратора создали данные для живого инстанса
   (`fix_linked.ps1` + исправление скобок `fix_symlink.ps1`):
   - `...\<iface>\#` → `SymbolicLink` (REG_SZ) =
     `\\?\USB#VID_A108&PID_4775#6&13C452C7&0&1#{198b2804-759e-4e55-afd9-9184d66f816a}`
     (формат как XP-путь `0x7697b0`;bieter `CreateFileA` с параметрами
     программы даёт валидный хендл);
   - `...\<iface>\#\Control` → `Linked = 1` (DWORD).
3. Запустили **оригинальный** `USBBurnTool.exe` — таблица заполнилась,
   прошивка стартовала сама. `USBBurnTool_patched*.exe` больше не нужны
   (v1/v2 были диагностическими ступенями; v2 без данных ронял программу
   по §15).

### Важно для повторения
- Проверено эмпирически 2026-09-28: после перезагрузки значения СОХРАНИЛИСЬ
  (ветка SYSTEM персистентна) — прошивка стартовала без повторного фикса.
  Оговорка про volatile снята частично: пересоздание скриптом нужно, только
  если устройство переэнумерировано как новый инстанс (другой USB-порт,
  переустановка драйвера — так ранее появился stale `...&0&2`) или при
  рецидиве 0%.
- Откат: `fix_linked.ps1 -Undo` / `fix_symlink.ps1 -Undo`, либо удалить
  `Control` и значение `SymbolicLink` вручную.

---

## 18. Ловушка `Fix-LinkedDevice.ps1` + PowerShell 5.1 (2026-09-28)

Симптом: прямой запуск `.\Fix-LinkedDevice.ps1` в Windows PowerShell 5.1 падал
с `AmpersandNotAllowed` на комментарии со `&` (строка 129) + каскадный
`MissingEndCurlyBrace`. Проверка парсером PS7 давала 0 ошибок — ложное чувство
исправности (целевой интерпретатор у пользователя — 5.1).
Расследование (бисекция + побайтовый дамп): виноват НЕ `&` (в изоляции ок),
а тире `—` (U+2014) в строке 121 внутри `"..."`. Файл был UTF-8 БЕЗ BOM —
5.1 читает такие как ANSI (cp1251), строка «теряла» закрывающую кавычку,
ошибки `&` были каскадом. Доказано минимумом: та же строка с `-` парсится.
Лечение: скрипт переведён на чистый ASCII (3 тире → `-`), перепроверено
парсерами 5.1 и 7.x — 0 ошибок. Урок: скрипты под 5.1 — только ASCII либо
UTF-8 с BOM, и валидировать парсером 5.1, а не 7.x.
Подтверждено заодно поведение из §17: другой USB-порт = новый инстанс
(старый уходит в stale) — скрипт находит живой автоматически.

---

## 19. Stale после смены порта: слот 1 мёртв, шьётся слот 2 (2026-09-28)

Симптом: после перестановки в другой порт — попап `Invalid handle!` (если его
не закрывать, прошивка живого устройства идёт, но прогресс в строке 2).
Причина: старый инстанс (`...&0&1`) хранит ранее созданные `SymbolicLink` +
`Control\Linked`, новый (`...&0&2`) получил свои от скрипта. `RebuildLinked`
кладёт stale в `Linked[0]` (порядок энумерации) → слот 1 открывает мёртвый
путь (попап), слот 2 шьёт живой. OK в попапе лучше не нажимать (там же
баг `pError` из §15 — в оригинале он тоже есть, это Debug-сборка).
Лечение без патчей: скрипт `Fix-LinkedDevice.ps1 -CleanStale` (устройство
подключено!) — снимает `SymbolicLink`/`Control` со stale-подключей, живой
возвращается в слот 1, попап исчезает. Проверено парсерами 5.1/7.x, чистый ASCII.

---

## 20. Лаунчер + самоэлевация (2026-09-28)

Побочка: запуск прошивальщика вообще без устройств тоже даёт ошибку, плюс
надоело вручную открывать админ-консоль. Скрипт стал лаунчером:
- без прав админа сам перезапускается с UAC (`Start-Process -Verb RunAs`,
  те же ключи), окно ждёт Enter в конце (`-NoPause` для автоматизации);
- чистит stale автоматически перед запуском, но только если найден хотя бы
  один живой инстанс (слепой вайп без живых запрещён — не отличить живое
  от stale); `-CleanStale` остался как явный вариант;
- после фикса сам стартует `USBBurnTool.exe` из своей папки (`-NoLaunch`
  чтобы только чинить). Без устройств прошивальщик тоже запускается (с
  предупреждением) — старт там отвечает benign `"No Linked Device Find!"`.
README (оба перевода) переведено на flow «одна команда». Парсеры 5.1/7.x —
0 ошибок, файл строго ASCII (урок §18 учтён).
