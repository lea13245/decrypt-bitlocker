#region UI / BANNER
cls
Write-Host @"
  _________                                         .__                           
 /   _____/ ___________   ____   ____   ____   _____|  |__ _____ _______   ____   
 \_____  \_/ ___\_  __ \_/ __ \_/ __ \ /    \ /  ___/  |  \\__  \\_  __ \_/ __ \  
 /        \  \___|  | \/\  ___/\  ___/|   |  \\___ \|   Y  \/ __ \|  | \/\  ___/  
/_______  /\___  >__|    \___  >\___  >___|  /____  >___|  (____  /__|    \___  > 
        \/     \/            \/     \/     \/     \/     \/     \/            \/  
"@ -ForegroundColor White
#endregion

#region CORE
$Results = @()
$Errors  = @()

function Status($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function Err($m){ Write-Host "[X] $m" -ForegroundColor Red }
#endregion

#region ENUMERATION (MAGNET-LIKE, SAFE)
Status "Enumerating disks, partitions and volumes"

try {
    $volumes = Get-CimInstance Win32_LogicalDisk -ErrorAction Stop
} catch {
    Err "Failed to enumerate logical disks"
    $Errors += $_.Exception.Message
    $volumes = @()
}

foreach ($v in $volumes) {

    $size = if ($v.Size) { [math]::Round($v.Size / 1GB,2) } else { "N/A" }
    $free = if ($v.FreeSpace) { [math]::Round($v.FreeSpace / 1GB,2) } else { "N/A" }

    $Results += [pscustomobject]@{
        Drive      = $v.DeviceID
        Label      = $v.VolumeName
        FileSystem = $v.FileSystem
        Type       = switch ($v.DriveType) {
            2 { "Removable" }
            3 { "Fixed" }
            4 { "Network" }
            5 { "Optical" }
            default { "Other" }
        }
        SizeGB     = $size
        FreeGB     = $free
        Encryption = "Not evaluated"
    }
}
#endregion

#region OUTPUT (SAFE FOR CMD / IEX)
if ($Results.Count -gt 0) {
    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        $Results | Out-GridView -Title "EDD+ Volume Overview"
    } else {
        $Results | Format-Table -AutoSize
    }
} else {
    Err "No volumes detected"
}

if ($Errors.Count -gt 0) {
    Write-Host ""
    Err "Errors:"
    $Errors | Format-List
}

Write-Host ""
Write-Host "Execution finished. Press ENTER to exit." -ForegroundColor DarkGray
[void][System.Console]::ReadLine()
#endregion
