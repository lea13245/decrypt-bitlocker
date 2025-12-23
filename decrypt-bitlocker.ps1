#region UI
cls
Write-Host @"
==========================================================================================
  _________                                         .__                                  |
 /   _____/ ___________   ____   ____   ____   _____|  |__ _____ _______   ____          |
 \_____  \_/ ___\_  __ \_/ __ \_/ __ \ /    \ /  ___/  |  \\__  \\_  __ \_/ __ \         |
 /        \  \___|  | \/\  ___/\  ___/|   |  \\___ \|   Y  \/ __ \|  | \/\  ___/         |
/_______  /\___  >__|    \___  >\___  >___|  /____  >___|  (____  /__|    \___  >        |
        \/     \/            \/     \/     \/     \/     \/     \/            \/         |
   _____  .__  .__  .__                                                                  |
  /  _  \ |  | |  | |__|____    ____   ____  ____                                        |
 /  /_\  \|  | |  | |  \__  \  /    \_/ ___\/ __ \                                       |
/    |    \  |_|  |_|  |/ __ \|   |  \  \__\  ___/                                       |
\____|__  /____/____/__(____  /___|  /\___  >___  >                                      |
        \/                  \/     \/     \/    \/                                       |
==========================================================================================
"@ -ForegroundColor White
#endregion

#region HELPERS
function Info($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[!]" $m -ForegroundColor Yellow }
function Err ($m){ Write-Host "[X]" $m -ForegroundColor Red }

function Show-Tree {
    param(
        [string]$Path,
        [int]$Depth = 3,
        [int]$Level = 0
    )

    if ($Level -ge $Depth) { return }

    try {
        $items = Get-ChildItem $Path -Force -ErrorAction Stop
    } catch {
        throw "Access denied or unreadable"
    }

    foreach ($i in $items) {
        $indent = ("│   " * $Level)
        Write-Host "$indent├── $($i.Name)"
        if ($i.PSIsContainer) {
            Show-Tree -Path $i.FullName -Depth $Depth -Level ($Level + 1)
        }
    }
}
#endregion

#region ENUMERATION
Info "Enumerating volumes..."

$Volumes = Get-CimInstance Win32_Volume | Where-Object { $_.DriveType -ne 5 }
$BitLockerAvailable = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue

$Table = @()
$ID = 1

foreach ($v in $Volumes) {

    # Defaults
    $Encrypted   = "NO"
    $EncType     = "CLEAR"
    $AccessClass = "CLEAR"
    $LiveUnlock  = "NO"
    $MemAcquire  = "NO"
    $Priority    = "LOW"

    # --- BitLocker ---
    if ($BitLockerAvailable -and $v.DriveLetter) {
        try {
            $bl = Get-BitLockerVolume -MountPoint $v.DriveLetter -ErrorAction Stop
            if ($bl.VolumeStatus -ne "FullyDecrypted") {
                $Encrypted   = "YES"
                $EncType     = "BITLOCKER ($($bl.EncryptionMethod))"
                $AccessClass = "ENCRYPTED_UNCOVERED"
                $LiveUnlock  = "YES"
                $MemAcquire  = "YES"
                $Priority    = "HIGH"
            }
        } catch {}
    }

    # --- Strong third-party / RAW ---
    if (
        ($v.FileSystem -eq $null -or $v.FileSystem -eq "RAW") -and
        ($v.Capacity -gt 1GB)
    ) {
        $Encrypted   = "YES"
        $EncType     = "THIRD-PARTY FULL DISK"
        $AccessClass = "ENCRYPTED_LOCKED"
        $LiveUnlock  = "NO"
        $MemAcquire  = "YES"
        $Priority    = "CRITICAL"
    }

    $Table += [pscustomobject]@{
        ID         = $ID
        Drive      = if ($v.DriveLetter) { $v.DriveLetter } else { "[NO LETTER]" }
        FS         = if ($v.FileSystem) { $v.FileSystem } else { "RAW" }
        SizeGB     = [math]::Round($v.Capacity / 1GB,2)
        Encrypted  = $Encrypted
        Type       = $EncType
        Access     = $AccessClass
        LiveUnlock = $LiveUnlock
        MemAcquire = $MemAcquire
        Priority   = $Priority
        Root       = if ($v.DriveLetter) { $v.DriveLetter + "\" } else { $null }
    }

    $ID++
}
#endregion

#region DISPLAY
Write-Host ""
Write-Host "ID Drive        FS     SizeGB  Encrypted  Type                        Access                 Live  RAM   Priority"
Write-Host "-- -----        --     ------  ---------  ----                        ------                 ----  ----  --------"

foreach ($row in $Table) {

    switch ($row.Priority) {
        "LOW"      { $Color = "Green" }
        "HIGH"     { $Color = "Yellow" }
        "CRITICAL" { $Color = "Red" }
        default    { $Color = "White" }
    }

    $line = "{0,-2} {1,-12} {2,-6} {3,-7} {4,-9} {5,-26} {6,-21} {7,-5} {8,-5} {9}" -f `
        $row.ID,
        $row.Drive,
        $row.FS,
        $row.SizeGB,
        $row.Encrypted,
        $row.Type,
        $row.Access,
        $row.LiveUnlock,
        $row.MemAcquire,
        $row.Priority

    Write-Host $line -ForegroundColor $Color
}
#endregion

#region SELECT VOLUME
$Choice = Read-Host "`nSelect volume ID to display tree (ENTER to exit)"
if (-not $Choice) { return }

$Selected = $Table | Where-Object { $_.ID -eq [int]$Choice }

if (-not $Selected) {
    Err "Invalid ID"
    return
}

if (-not $Selected.Root) {
    Err "Volume has no mount point (locked or encrypted)"
    return
}
#endregion

#region TREE VIEW
Info "Building directory tree for $($Selected.Drive)"

try {
    $files = Get-ChildItem $Selected.Root -Force -ErrorAction Stop
    if (-not $files) {
        Warn "Volume accessible but contains no files"
        return
    }

    Write-Host "`nTREE (depth = 3):" -ForegroundColor Cyan
    Write-Host $Selected.Root
    Show-Tree -Path $Selected.Root -Depth 3

} catch {
    Err "Unable to enumerate files (encrypted, permission denied or locked)"
}
#endregion

Write-Host "`nTriage completed (report-only mode)." -ForegroundColor DarkGray
