# BitLocker Decrypt + Auto Open Volume
function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsEdition {
    try {
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
    } catch {
        return "UNKNOWN"
    }
}

function ManageBDE-Exists {
    Test-Path "$env:SystemRoot\System32\manage-bde.exe"
}

function Get-DriveBusType($driveLetter) {
    try {
        $dl = $driveLetter.TrimEnd(":")
        (Get-Partition -DriveLetter $dl | Get-Disk).BusType
    } catch {
        return "UNKNOWN"
    }
}

function Get-BitLockerStatus($drive) {
    try {
        & manage-bde -status $drive 2>&1
    } catch {
        return $null
    }
}

function Drive-Accessible($drive) {
    Test-Path "$drive\"
}

# MAIN
Write-Host "`n[+] BitLocker Decrypt Tool`n"

if (-not (Is-Admin)) {
    Write-Host "[!] ERROR: Ejecutar como Administrador."
    exit 1
}

$edition = Get-WindowsEdition
if ($edition -match "Home") {
    Write-Host "[!] ERROR: Windows Home no soporta BitLocker completo."
    exit 1
}

if (-not (ManageBDE-Exists)) {
    Write-Host "[!] ERROR: manage-bde.exe no está disponible."
    exit 1
}

$drive = Read-Host "Ingrese la partición (ej: E:)"
if ($drive -notmatch "^[A-Z]:$") {
    Write-Host "[!] ERROR: Formato inválido (use E:)"
    exit 1
}

$bus = Get-DriveBusType $drive
if ($bus -eq "USB") {
    Write-Host "[i] Unidad USB detectada (BitLocker To Go)."
}

$status = Get-BitLockerStatus $drive
if (-not $status) {
    Write-Host "[!] ERROR: No se pudo obtener estado BitLocker."
    exit 1
}

if ($status -match "Sin cifrar|Fully Decrypted|Protección desactivada") {
    Write-Host "[i] La unidad ya está desencriptada."
    if (Drive-Accessible $drive) {
        Write-Host "[+] Abriendo unidad..."
        Start-Process explorer.exe $drive
    }
    exit 0
}

if ($status -match "Bloqueado|Locked") {
    Write-Host "[!] ERROR: La unidad está BLOQUEADA."
    Write-Host "    Debe desbloquearla antes (password o recovery key)."
    exit 1
}

Write-Host "`n[+] Iniciando desencriptado de $drive ..."
try {
    $proc = Start-Process -FilePath "manage-bde.exe" `
                          -ArgumentList "-off $drive" `
                          -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0) {
        Write-Host "[!] ERROR: manage-bde falló (ExitCode $($proc.ExitCode))"
        exit 1
    }
}
catch {
    Write-Host "[!] ERROR al ejecutar manage-bde"
    Write-Host $_
    exit 1
}

Write-Host "[+] Desencriptado iniciado correctamente."
Write-Host "    Esperando a que el volumen sea accesible..."

# Esperar hasta que el volumen sea accesible (máx 60s)
$timeout = 60
while ($timeout -gt 0) {
    if (Drive-Accessible $drive) {
        Write-Host "[+] Volumen accesible."
        Write-Host "[+] Abriendo partición..."
        Start-Process explorer.exe $drive
        exit 0
    }
    Start-Sleep -Seconds 2
    $timeout -= 2
}

Write-Host "[!] El desencriptado comenzó, pero la unidad aún no está accesible."
Write-Host "    Verifique progreso con:"
Write-Host "    manage-bde -status $drive"

Write-Host "`n[FIN]"
