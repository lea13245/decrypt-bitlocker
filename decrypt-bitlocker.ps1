# BitLocker / USB Auto Handler (DFIR Safe)
function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsEdition {
    try {
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
    } catch { "UNKNOWN" }
}

function ManageBDE-Exists {
    Test-Path "$env:SystemRoot\System32\manage-bde.exe"
}

function Get-DriveBusType($drive) {
    try {
        $dl = $drive.TrimEnd(":")
        (Get-Partition -DriveLetter $dl | Get-Disk).BusType
    } catch { "UNKNOWN" }
}

function Drive-Accessible($drive) {
    Test-Path "$drive\"
}

function Get-BitLockerStatus($drive) {
    try { & manage-bde -status $drive 2>&1 } catch { $null }
}

function Copy-RawFile {
    param($src)

    $dstDir = "$env:USERPROFILE\Downloads\DFIR_Copy"
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    $dst = Join-Path $dstDir ([IO.Path]::GetFileName($src))

    Write-Host "[+] Copiando archivo RAW..."
    $buf = New-Object byte[] 4MB
    $in  = [IO.File]::OpenRead($src)
    $out = [IO.File]::OpenWrite($dst)

    while (($r = $in.Read($buf,0,$buf.Length)) -gt 0) {
        $out.Write($buf,0,$r)
    }

    $in.Close(); $out.Close()
    Write-Host "[+] Archivo copiado a $dst"
}

# MAIN
Write-Host "`n[+] BitLocker / USB Auto DFIR Tool`n"

if (-not (Is-Admin)) {
    Write-Host "[!] Ejecutar como Administrador."
    exit 1
}

$drive = Read-Host "Ingrese la partición (ej: E:)"
if ($drive -notmatch "^[A-Z]:$" -or -not (Drive-Accessible $drive)) {
    Write-Host "[!] Volumen inválido o no accesible."
    exit 1
}

$edition = Get-WindowsEdition
$hasBDE  = ManageBDE-Exists
$bus     = Get-DriveBusType $drive

Write-Host "[i] Windows Edition : $edition"
Write-Host "[i] manage-bde     : $hasBDE"
Write-Host "[i] Bus Type       : $bus"

# =========================
# MODO WINDOWS HOME / SIN BITLOCKER
# =========================
if ($edition -match "Home" -or -not $hasBDE) {
    Write-Host "`n[MODE] Windows Home / Sin BitLocker admin"
    Write-Host "[+] Modo LECTURA forense"

    Write-Host "[+] Listando archivos..."
    Get-ChildItem "$drive\" -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize

    $src = Read-Host "`nRuta COMPLETA de archivo a copiar (Enter para salir)"
    if ($src -and (Test-Path $src)) {
        Copy-RawFile $src
    }

    Write-Host "`n[FIN]"
    exit 0
}

# MODO WINDOWS PRO / BITLOCKER
$status = Get-BitLockerStatus $drive
if (-not $status) {
    Write-Host "[!] No se pudo obtener estado BitLocker."
    exit 1
}

if ($status -match "Bloqueado|Locked") {
    Write-Host "[!] Unidad BLOQUEADA. Desbloquee primero."
    exit 1
}

if ($status -match "Sin cifrar|Fully Decrypted|Protección desactivada") {
    Write-Host "[+] Unidad ya desencriptada."
    Start-Process explorer.exe $drive
    exit 0
}

Write-Host "`n[+] Iniciando desencriptado BitLocker..."
$proc = Start-Process manage-bde.exe `
        -ArgumentList "-off $drive" `
        -Wait -PassThru -NoNewWindow

if ($proc.ExitCode -ne 0) {
    Write-Host "[!] Error en manage-bde (ExitCode $($proc.ExitCode))"
    exit 1
}

Write-Host "[+] Desencriptado iniciado. Abriendo volumen..."
Start-Process explorer.exe $drive

Write-Host "`n[FIN]"
