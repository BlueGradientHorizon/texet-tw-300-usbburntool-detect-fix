<#
.SYNOPSIS
  Fix for the flashing tool not detecting the connected device:
  USBBurnTool (TW-300, JZ4775) on Windows 10/11.

.DESCRIPTION
  For the full analysis, see README.md (English and Russian versions).

  USBBurnTool treats a device as "connected" only when the registry contains:
    1) HKLM\...\DeviceClasses\{198b2804-759e-4e55-afd9-9184d66f816a}\<iface>\#\Control
       with a DWORD value named "Linked" (the IsLinked check, start-button gate);
    2) a "SymbolicLink" value in the ...\<iface>\# key (device name for the table
       and the path used by CreateFile during flashing).
  On Windows 10/11 neither exists: nothing creates them - not the tool, not the
  JZ_USB_Boot.sys driver, not the INF files. Without them the table stays at 0%,
  the start button reports "No Linked Device Find!", and forcing the gate open
  only leads to "Invalid handle!" errors. Stale instances (...&0&2, Present=False)
  add phantom table rows.

  HOW THIS SCRIPT FIXES IT.
  For every CURRENTLY PRESENT JZ_USB_Boot device the script locates its interface
  key in DeviceClasses and creates the missing data:
    - SymbolicLink (REG_SZ) = the device path, e.g.
      \\?\USB#VID_A108&PID_4775#6&...&0&1#{198b2804-...} (derived from the subkey
      name: the "##?#" prefix is replaced with "\\?\");
    - a child "Control" key with Linked = 1 (DWORD).
  After that the ORIGINAL USBBurnTool.exe detects the device and flashes normally;
  no binary patching is needed.

  TEMPORARY OR PERMANENT FIX.
  PRACTICALLY PERSISTENT: verified that the values survive a reboot (the SYSTEM
  hive is persistent). Re-run only if the device is re-enumerated as a new
  instance (different USB port, driver reinstall) or if the symptom returns.
  The script is idempotent: re-running it is safe.

  SIDE EFFECTS AND ROLLBACK.
  - The script writes ONLY inside its own GUID branch {198b2804-...} (the "#"
    keys and "Control" keys of JZ47xx interfaces). System keys and the "#"
    subkeys themselves are never deleted or renamed. Risk is minimal.
  - To roll back, run with -Undo: it removes the created SymbolicLink values
    and Control subkeys (see below).
  - If you moved the device to another USB port, the old instance stays behind
    as stale (hidden) and keeps its old Linked data, so the flasher fills slot
    1 with a dead entry ("Invalid handle!" popup) while the live device works
    in slot 2. Run with -CleanStale to unlink such stale instances: for every
    interface key with no matching present device the script removes the
    SymbolicLink value and the Control subkey, so the live device takes slot 1
    and no popup appears. Connect the device first, then run with -CleanStale.

  LAUNCHER MODE (default).
  After fixing, the script starts USBBurnTool.exe from the same folder, so one
  run prepares everything and opens the flasher. Stale instances are unlinked
  automatically before the launch (same as -CleanStale, but only when at least
  one live device was fixed - with no devices connected nothing is deleted).
  Use -NoLaunch to fix only, without starting the flasher. With no devices
  connected the flasher still starts (with a warning); pressing start there
  only reports "No Linked Device Find!" - connect the device and run again.

  SELF-ELEVATION.
  Administrator rights are required (HKLM writes). If you run the script from
  a normal window, it re-launches itself elevated (UAC prompt) with the same
  switches. No manual admin console needed. The elevated window waits for
  Enter before closing (use -NoPause for automation).

.EXAMPLE
  # Connect the device in USB-boot mode, then just run (UAC prompt appears,
  # stale instances are cleaned, USBBurnTool.exe starts automatically):
  powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1

.EXAMPLE
  # Fix only, do not start the flasher:
  powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -NoLaunch

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -Undo

.EXAMPLE
  # After moving the device to another USB port (stale instance left behind):
  powershell -ExecutionPolicy Bypass -File .\Fix-LinkedDevice.ps1 -CleanStale

.NOTES
  Administrator rights are required (writes to HKLM); the script re-launches
  itself elevated when needed. Without -Undo it only reads PnP/registry and
  writes the missing values; it deletes stale leftovers only as described.
#>
param(
  [switch]$Undo,       # rollback: remove the created SymbolicLink values and Control keys
  [switch]$CleanStale, # also unlink stale instances (no matching present device)
  [switch]$NoLaunch,   # fix only, do not start USBBurnTool.exe
  [switch]$NoPause     # do not wait for Enter at the end (for automation)
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Guid = "{198b2804-759e-4e55-afd9-9184d66f816a}"
$Base = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\$Guid"

# --- Self-elevation: re-launch this same script as administrator (UAC prompt) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ("`"" + $PSCommandPath + "`""))
  if ($Undo) { $argList += "-Undo" }
  if ($CleanStale) { $argList += "-CleanStale" }
  if ($NoLaunch) { $argList += "-NoLaunch" }
  if ($NoPause) { $argList += "-NoPause" }
  Write-Output "Requesting administrator rights (UAC prompt)..."
  Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -WorkingDirectory $PSScriptRoot
  exit 0
}

# --- Pause helper: the elevated window would close at once, so wait for Enter ---
function Done($code) {
  if (-not $NoPause) {
    Write-Output ""
    Read-Host "Press Enter to close" | Out-Null
  }
  exit $code
}

function Get-PresentDevices {
  # Live devices of this boot driver (usually one: USB\VID_A108&PID_4775\...&0&1)
  $devs = Get-PnpDevice -Class "JZ_USB_Boot" -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.Present -eq $true }
  return @($devs)
}

function Find-InterfaceKey($instanceId) {
  # DeviceClasses subkey for an instance: "##?#" + InstanceId with "\"->"#" + "#{guid}"
  $frag = ($instanceId -replace "\\", "#")
  $kids = Get-ChildItem -LiteralPath $Base -ErrorAction SilentlyContinue
  foreach ($k in $kids) {
    if ($k.PSChildName -like "*$frag*") { return $k.PSChildName }
  }
  return $null
}

if ($Undo) {
  # --- ROLLBACK: remove only what this script creates (SymbolicLink values
  # --- and Control subkeys); the "#" subkeys and devices are left alone ---
  $kids = Get-ChildItem -LiteralPath $Base -ErrorAction SilentlyContinue
  foreach ($k in $kids) {
    $hashPath = Join-Path (Join-Path $Base $k.PSChildName) "#"
    Remove-ItemProperty -LiteralPath $hashPath -Name "SymbolicLink" `
      -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $hashPath "Control") -Recurse `
      -ErrorAction SilentlyContinue
    Write-Output (" rollback: " + $k.PSChildName)
  }
  Write-Output "Done: data created by the script has been removed."
  Done 0
}

$devs = Get-PresentDevices
if ($devs.Count -eq 0) {
  Write-Output "No JZ_USB_Boot device found among present devices."
  Write-Output "Connect the TW-300 in USB-boot mode and try again."
  Done 1
}

$fixed = 0
$matched = @()
foreach ($d in $devs) {
  Write-Output ("Device: " + $d.InstanceId + " [" + $d.Status + "]")
  $child = Find-InterfaceKey $d.InstanceId
  if (-not $child) {
    Write-Output "  No interface subkey in DeviceClasses - skipped."
    continue
  }
  $hashPath = Join-Path (Join-Path $Base $child) "#"
  if (!(Test-Path -LiteralPath $hashPath)) {
    Write-Output "  No '#' subkey, skipped."
    continue
  }
  # Device path: subkey "##?#USB#..." becomes "\\?\USB#..."
  $symLink = "\\?\" + ($child -replace "^\#\#\?#", "")
  New-ItemProperty -LiteralPath $hashPath -Name "SymbolicLink" `
    -Value $symLink -PropertyType String -Force | Out-Null
  $ctrlPath = Join-Path $hashPath "Control"
  New-Item -Path $ctrlPath -Force | Out-Null
  New-ItemProperty -LiteralPath $ctrlPath -Name "Linked" `
    -Value 1 -PropertyType DWord -Force | Out-Null
  Write-Output ("  SymbolicLink = " + $symLink)
  Write-Output "  Control\Linked = 1"
  $fixed++
  $matched += $child
}

# --- Stale instances (e.g. after moving the device to another USB port):
# --- their leftover Linked data fills slot 1 with a dead entry while the
# --- live device works in slot 2, plus an "Invalid handle!" popup ---
$allKids = @(Get-ChildItem -LiteralPath $Base -ErrorAction SilentlyContinue)
$stale = @($allKids | Where-Object { $matched -notcontains $_.PSChildName })
if ($stale.Count -gt 0) {
  if ($fixed -gt 0) {
    # Safe to unlink: live devices are known, the rest is stale. A blind wipe
    # with no live devices found is refused (see below).
    foreach ($k in $stale) {
      $hashPath = Join-Path (Join-Path $Base $k.PSChildName) "#"
      Remove-ItemProperty -LiteralPath $hashPath -Name "SymbolicLink" `
        -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath (Join-Path $hashPath "Control") -Recurse `
        -ErrorAction SilentlyContinue
      Write-Output ("  unlinked stale: " + $k.PSChildName)
    }
  } else {
    Write-Output ""
    Write-Output "WARNING: extra subkeys in DeviceClasses (probably stale):"
    foreach ($k in $stale) { Write-Output ("  " + $k.PSChildName) }
    Write-Output "Nothing was deleted: no live devices found to match against."
    Write-Output "Connect the device and re-run (stale entries are unlinked"
    Write-Output "automatically), or remove the hidden instances in Device"
    Write-Output "Manager (View -> hidden devices)."
  }
} elseif ($CleanStale) {
  Write-Output "No stale instances found."
}

Write-Output ""
if ($fixed -gt 0) {
  Write-Output "Done: $fixed device(s) fixed."
  if (-not $NoLaunch) {
    $exe = Join-Path $PSScriptRoot "USBBurnTool.exe"
    if (Test-Path -LiteralPath $exe) {
      Write-Output "Starting USBBurnTool.exe ..."
      Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot
    } else {
      Write-Output "WARNING: USBBurnTool.exe not found next to the script."
    }
  } else {
    Write-Output "Start the ORIGINAL USBBurnTool.exe."
  }
  Done 0
} else {
  Write-Output "Nothing fixed - see the messages above."
  Done 1
}
