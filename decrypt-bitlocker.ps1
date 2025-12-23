#region UI / BANNER
cls
cls

Write-Host @"
  _________                                         .__                           
 /   _____/ ___________   ____   ____   ____   _____|  |__ _____ _______   ____   
 \_____  \_/ ___\_  __ \_/ __ \_/ __ \ /    \ /  ___/  |  \\__  \\_  __ \_/ __ \  
 /        \  \___|  | \/\  ___/\  ___/|   |  \\___ \|   Y  \/ __ \|  | \/\  ___/  
/_______  /\___  >__|    \___  >\___  >___|  /____  >___|  (____  /__|    \___  > 
        \/     \/            \/     \/     \/     \/     \/     \/            \/  
   _____  .__  .__  .__                            
  /  _  \ |  | |  | |__|____    ____   ____  ____  
 /  /_\  \|  | |  | |  \__  \  /    \_/ ___\/ __ \ 
/    |    \  |_|  |_|  |/ __ \|   |  \  \__\  ___/ 
\____|__  /____/____/__(____  /___|  /\___  >___  >
        \/                  \/     \/     \/    \/ 
"@ -ForegroundColor White

Start-Sleep 1
cls
#endregion

#region CORE
$Results = @()
$Errors  = @()

function Status($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function Err($m){ Write-Host "[X] $m" -ForegroundColor Red }

function SafeExec($Name,[scriptblock]$b){
    try {
        Status $Name
        & $b
    } catch {
        $Errors += [pscustomobject]@{
            Step  = $Name
            Error = $_.Exception.Message
        }
        Err "$Name failed"
    }
}
#endregion

#region PARTITION ENUMERATION (MAGNET-LIKE)
Status "Enumerating disks and partitions (safe mode)"

$volumes = @()

try {
    $volumes = Get-WmiObject Win32_LogicalDisk -ErrorAction Stop
} catch {
    Err "WMI Win32_LogicalDisk failed"
    $Errors += [pscustomobject]@{
        Step  = "Get-WmiObject Win32_LogicalDisk"
        Error = $_.Exception.Message
    }
}

foreach ($v in $volumes) {

    $size = "N/A"
    $free = "N/A"

    if ($v.Size -and $v.Size -gt 0) {
        $size = [math]::Round($v.Size / 1GB,2)
    }

    if ($v.FreeSpace -and $v.FreeSpace -gt 0) {
        $free = [math]::Round($v.FreeSpace / 1GB,2)
    }

    $Results += [pscustomobject]@{
        Drive      = $v.DeviceID
        Label      = $v.VolumeName
        FileSystem = $v.FileSystem
        Type       = switch ($v.DriveType) {
            2 { "Removable (USB)" }
            3 { "Fixed Disk" }
            5 { "Optical" }
            default { "Other" }
        }
        SizeGB     = $size
        FreeGB     = $free
        Encryption = "Not evaluated"
        Cipher     = "N/A"
    }
}

#endregion

#region OUTPUT
if ($Results.Count -gt 0) {
    $Results | Out-GridView -Title "EDD+ Partition & Encryption Overview"
}

if ($Errors.Count -gt 0) {
    $Errors | Out-GridView -Title "EDD+ Errors"
}
#endregion
