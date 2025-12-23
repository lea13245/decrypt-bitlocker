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
SafeExec "Enumerating disks and partitions" {

    $volumes = Get-CimInstance Win32_LogicalDisk
    $bitlockerAvailable = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue

    foreach ($v in $volumes) {

        $encStatus = "Unknown"
        $encMethod = "N/A"

        if ($bitlockerAvailable -and $v.DriveType -eq 3) {
            $bl = Get-BitLockerVolume -MountPoint $v.DeviceID -ErrorAction SilentlyContinue
            if ($bl) {
                $encStatus = $bl.ProtectionStatus
                $encMethod = $bl.EncryptionMethod
            }
        }

        $Results += [pscustomobject]@{
            Drive        = $v.DeviceID
            VolumeName   = $v.VolumeName
            FileSystem   = $v.FileSystem
            DriveType    = switch ($v.DriveType) {
                2 { "Removable (USB)" }
                3 { "Fixed Disk" }
                5 { "Optical" }
                default { "Other" }
            }
            SizeGB       = [math]::Round($v.Size / 1GB,2)
            FreeGB       = [math]::Round($v.FreeSpace / 1GB,2)
            Encryption   = $encStatus
            Cipher       = $encMethod
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
