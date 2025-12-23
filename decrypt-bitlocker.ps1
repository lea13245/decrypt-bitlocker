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
#endregion

#region ENUMERATION
Info "Enumerating volumes..."

$Volumes = Get-CimInstance Win32_Volume | Where-Object { $_.DriveType -ne 5 }
$BitLockerAvailable = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue

$Table = @()
$ID = 1

foreach ($v in $Volumes) {

    $Encrypted = "NO"
    $EncType   = "CLEAR"
    $Priority  = "LOW"

    # --- BitLocker (verificación real)
    if ($BitLockerAvailable -and $v.DriveLetter) {
        try {
            $bl = Get-BitLockerVolume -MountPoint $v.DriveLetter -ErrorAction Stop
            if ($bl.VolumeStatus -ne "FullyDecrypted") {
                $Encrypted = "YES"
                $EncType   = "BITLOCKER ($($bl.EncryptionMethod))"
                $Priority  = "HIGH"
            }
        } catch {}
    }

    # --- Full Disk Encryption third-party (estricto)
    if (
        ($v.FileSystem -eq $null -or $v.FileSystem -eq "RAW") -and
        ($v.Capacity -gt 1GB)
    ) {
        $Encrypted = "YES"
        $EncType   = "THIRD-PARTY FULL DISK"
        $Priority  = "CRITICAL"
    }

    $Table += [pscustomobject]@{
        ID        = $ID
        Drive     = if ($v.DriveLetter) { $v.DriveLetter } else { "[NO LETTER]" }
        FS        = if ($v.FileSystem) { $v.FileSystem } else { "RAW" }
        SizeGB    = [math]::Round($v.Capacity / 1GB,2)
        Encrypted = $Encrypted
        Type      = $EncType
        Priority  = $Priority
        Root      = if ($v.DriveLetter) { $v.DriveLetter + "\" } else { $null }
    }
    $ID++
}
#endregion

#region DISPLAY (COLORIZED)
Write-Host ""
Write-Host "ID Drive        FS     SizeGB  Encrypted  Type                          Priority"
Write-Host "-- -----        --     ------  ---------  ----                          --------"

foreach ($row in $Table) {

    switch ($row.Priority) {
        "LOW"      { $Color = "Green" }
        "HIGH"     { $Color = "Yellow" }
        "CRITICAL" { $Color = "Red" }
        default    { $Color = "White" }
    }

    $line = "{0,-2} {1,-12} {2,-6} {3,-7} {4,-9} {5,-28} {6}" -f `
        $row.ID,
        $row.Drive,
        $row.FS,
        $row.SizeGB,
        $row.Encrypted,
        $row.Type,
        $row.Priority

    Write-Host $line -ForegroundColor $Color
}
#endregion

#region REPORT
Info "Generating forensic report..."

foreach ($v in $Table | Where-Object { $_.Root }) {

    Write-Host "`n--- Volume $($v.Drive) ---" -ForegroundColor Cyan

    # Timeline del volumen
    try {
        $rootItem = Get-Item $v.Root -ErrorAction Stop
        $rootItem | Select-Object CreationTime, LastWriteTime, LastAccessTime | Format-List
    } catch {
        Warn "Timeline not accessible"
    }

    # Hash lógico del volumen (estructura accesible)
    try {
        $files = Get-ChildItem $v.Root -Recurse -File -ErrorAction SilentlyContinue
        if ($files) {
            $hash = ($files | Get-FileHash -Algorithm SHA256).Hash |
                Sort-Object |
                Get-FileHash -Algorithm SHA256
            Write-Host "Logical Volume SHA256: $($hash.Hash)" -ForegroundColor Gray
        } else {
            Warn "No accessible files for hashing"
        }
    } catch {
        Warn "Hashing failed"
    }
}
#endregion

Write-Host "`nTriage completed. Report mode only." -ForegroundColor DarkGray
