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
Status "Enumerating disks and partitions"

$volumes = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue
$bitlockerCmd = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue

foreach ($v in $volumes) {

    try {
        $encStatus = "N/A"
        $encMethod = "N/A"

        if ($bitlockerCmd -and $v.DriveType -eq 3) {
            try {
                $bl = Get-BitLockerVolume -MountPoint $v.DeviceID -ErrorAction Stop
                if ($bl) {
                    $encStatus = switch ($bl.ProtectionStatus) {
                        0 { "Off" }
                        1 { "On" }
                        default { "Unknown" }
                    }
                    $encMethod = $bl.EncryptionMethod
                }
            } catch {
                $encStatus = "Unavailable"
            }
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
            SizeGB     = if ($v.Size) { [math]::Round($v.Size / 1GB,2) } else { "N/A" }
            FreeGB     = if ($v.FreeSpace) { [math]::Round($v.FreeSpace / 1GB,2) } else { "N/A" }
            Encryption = $encStatus
            Cipher     = $encMethod
        }

    } catch {
        $Errors += [pscustomobject]@{
            Drive = $v.DeviceID
            Error = $_.Exception.Message
        }
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
