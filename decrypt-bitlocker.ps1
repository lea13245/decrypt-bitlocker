#Requires -RunAsAdministrator
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# =======================
# CONFIGURACIÓN
# =======================
$CASE_ID = "CASE_001"
$ROOT = "$env:SystemDrive\DFIR_EDD_$CASE_ID"
$COPY_DIR = "$ROOT\COPIED"
$ERR_FILE = "$ROOT\ERRORS.txt"
$OUT_FILE = "$ROOT\EDD.txt"

New-Item -ItemType Directory -Force -Path $ROOT,$COPY_DIR | Out-Null

$UTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
$HOST = $env:COMPUTERNAME

# =======================
# CIFRADOS CONOCIDOS
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
function Log($msg){ Add-Content -Encoding UTF8 $OUT_FILE $msg }
function LogErr($blk,$err){
 Add-Content -Encoding UTF8 $ERR_FILE "[$blk] $err"
}

function SafeExec {
 param($Name,[scriptblock]$Code)
 try { & $Code }
 catch {
   LogErr $Name $_
   try { & $Code }
   catch { LogErr "$Name-RETRY" $_ }
 }
}

# =======================
# HEADER (MAGNET STYLE)
# =======================
Log "MAGNET-STYLE ENCRYPTED DISK DETECTOR +"
Log "Host: $HOST"
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
     $_.DriveLetter,$_.FileSystem,$_.FileSystemLabel,$_.HealthStatus)
 }
}

# =======================
# BITLOCKER
# =======================
SafeExec "BITLOCKER" {
 Log "== BITLOCKER STATUS =="
 Get-BitLockerVolume | ForEach-Object {
   Log ("{0} | Encrypted:{1} | Lock:{2}" -f `
     $_.MountPoint,$_.VolumeStatus,$_.LockStatus)
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
 Get-PnpDevice -PresentOnly | Where-Object {
   $_.Class -match "USB|Disk"
 } | ForEach-Object {
   Log ("USB {0} | Status:{1}" -f $_.FriendlyName,$_.Status)
 }
}

SafeExec "USB_HISTORY" {
 Log "== USB HISTORY =="
 Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*" `
  -ErrorAction Stop | ForEach-Object {
   Log ("USB HIST {0}" -f $_.PSChildName)
 }
}

# =======================
# DECISIÓN FORENSE
# =======================
SafeExec "DECISION" {
 $enc = (Get-BitLockerVolume | Where-Object {
   $_.VolumeStatus -ne "FullyDecrypted"
 }).Count

 Log "== FORENSIC DECISION =="
 if($enc -gt 0){
   Log "ENCRYPTION DETECTED – KEEP SYSTEM POWERED ON"
 } else {
   Log "NO FULL DISK ENCRYPTION DETECTED"
 }
}

# =======================
# FILE COPY (SAFE)
# =======================
function Copy-AccessibleFile($Path){
 SafeExec "COPY:$Path" {
   if(Test-Path $Path){
     $dst = Join-Path $COPY_DIR (Split-Path $Path -Leaf)
     Copy-Item $Path $dst -Force
     Log ("COPIED: $Path -> $dst")
   }
 }
}

# Example:
# Copy-AccessibleFile "C:\Users\Public\example.txt"

Log "-------------------------------------"
Log "EDD+ EXECUTION COMPLETE"
