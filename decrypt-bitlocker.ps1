#Requires -RunAsAdministrator
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# =======================
# CONFIGURACIÓN
# =======================
$CASE_ID = "CASE_001"
$DFIR_HOSTNAME = $env:COMPUTERNAME
$ROOT = Join-Path $env:SystemDrive "DFIR_EDD_$CASE_ID"
$COPY_DIR = Join-Path $ROOT "COPIED"
$ERR_FILE = Join-Path $ROOT "ERRORS.txt"
$OUT_FILE = Join-Path $ROOT "EDD.txt"

New-Item -ItemType Directory -Force -Path $ROOT,$COPY_DIR | Out-Null

$UTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")

# =======================
# FIRMAS DE CIFRADO
# =======================
$CRYPTO_SIGS = @(
  "bitlocker","fvevol",
  "veracrypt","truecrypt",
  "pgpwded","pgp",
  "safeboot","mcafee",
  "checkpoint","fde",
  "bestcrypt",
  "symantec",
  "luks"
)

# =======================
# HELPERS
# =======================
function Log { param([string]$Msg)
  Add-Content -Encoding UTF8 -Path $OUT_FILE -Value $Msg
}
function LogErr { param([string]$Block,[string]$Err)
  Add-Content -Encoding UTF8 -Path $ERR_FILE -Value ("[{0}] {1}" -f $Block,$Err)
}
function SafeExec {
  param([string]$Name,[scriptblock]$Code)
  try { & $Code }
  catch {
    LogErr $Name $_.Exception.Message
    try { & $Code }
    catch { LogErr "$Name-RETRY" $_.Exception.Message }
  }
}

# =======================
# HEADER (ESTILO MAGNET)
# =======================
Log "MAGNET-STYLE ENCRYPTED DISK DETECTOR +"
Log "Host: $DFIR_HOSTNAME"
Log "Case: $CASE_ID"
Log "Time: $UTC"
Log "-------------------------------------"

# =======================
# PHYSICAL DISKS
# =======================
SafeExec "DISKS" {
  Log "== PHYSICAL DISKS =="
  Get-Disk | ForEach-Object {
    Log ("Disk {0}: {1} | Bus:{2} | Partition:{3}" -f `
      $_.Number,$_.FriendlyName,$_.BusType,$_.PartitionStyle)
  }
}

# =======================
# LOGICAL VOLUMES
# =======================
SafeExec "VOLUMES" {
  Log "== LOGICAL VOLUMES =="
  Get-Volume | ForEach-Object {
    Log ("Volume {0}: FS:{1} Label:{2} Health:{3}" -f `
      ($_.DriveLetter -as [string]),$_.FileSystem,$_.FileSystemLabel,$_.HealthStatus)
  }
}

# =======================
# BITLOCKER
# =======================
SafeExec "BITLOCKER" {
  Log "== BITLOCKER STATUS =="
  if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    Get-BitLockerVolume | ForEach-Object {
      Log ("{0} | Status:{1} | Lock:{2}" -f `
        $_.MountPoint,$_.VolumeStatus,$_.LockStatus)
    }
  } else {
    Log "BitLocker cmdlets not available."
  }
}

# =======================
# ENCRYPTION DRIVERS
# =======================
SafeExec "DRIVERS" {
  Log "== ENCRYPTION DRIVERS =="
  Get-CimInstance Win32_SystemDriver | Where-Object {
    $n=$_.Name.ToLower()
    $CRYPTO_SIGS | Where-Object { $n -like "*$_*" }
  } | ForEach-Object {
    Log ("Driver {0} | State:{1} | Path:{2}" -f `
      $_.Name,$_.State,$_.PathName)
  }
}

# =======================
# ENCRYPTION SERVICES
# =======================
SafeExec "SERVICES" {
  Log "== ENCRYPTION SERVICES =="
  Get-Service | Where-Object {
    $n=$_.Name.ToLower()
    $CRYPTO_SIGS | Where-Object { $n -like "*$_*" }
  } | ForEach-Object {
    Log ("Service {0} | Status:{1}" -f $_.Name,$_.Status)
  }
}

# =======================
# USB PRESENT & HISTORY
# =======================
SafeExec "USB_PRESENT" {
  Log "== USB PRESENT =="
  if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
    Get-PnpDevice -PresentOnly | Where-Object {
      $_.Class -match "USB|Disk"
    } | ForEach-Object {
      Log ("USB {0} | Status:{1}" -f $_.FriendlyName,$_.Status)
    }
  } else {
    Log "PnP cmdlets not available."
  }
}

SafeExec "USB_HISTORY" {
  Log "== USB HISTORY =="
  Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*" -ErrorAction Stop |
    ForEach-Object { Log ("USB HIST {0}" -f $_.PSChildName) }
}

# =======================
# DECISIÓN FORENSE
# =======================
SafeExec "DECISION" {
  Log "== FORENSIC DECISION =="
  if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    $enc = (Get-BitLockerVolume | Where-Object {
      $_.VolumeStatus -ne "FullyDecrypted"
    }).Count
    if ($enc -gt 0) { Log "ENCRYPTION DETECTED – KEEP SYSTEM POWERED ON" }
    else { Log "NO FULL DISK ENCRYPTION DETECTED" }
  } else {
    Log "Decision limited: BitLocker cmdlets unavailable."
  }
}

# =======================
# FILE COPY (VOLUMEN YA ACCESIBLE)
# =======================
function Copy-AccessibleFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  SafeExec "COPY:$Path" {
    if (Test-Path $Path) {
      $dst = Join-Path $COPY_DIR (Split-Path $Path -Leaf)
      Copy-Item -Path $Path -Destination $dst -Force
      Log ("COPIED: {0} -> {1}" -f $Path,$dst)
    } else {
      Log ("COPY SKIPPED (NOT FOUND): {0}" -f $Path)
    }
  }
}

Log "-------------------------------------"
Log "EDD+ EXECUTION COMPLETE"
