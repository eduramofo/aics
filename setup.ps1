<#
.SYNOPSIS
Instalador unificado do AICS.

.DESCRIPTION
Instala o serviço AICS e configura o ícone de bandeja para iniciar
automaticamente com o Windows.

COMO USAR:
Clique com o botão direito neste arquivo e selecione:
"Executar com PowerShell" (como Administrador)

O QUE ESTE SCRIPT FAZ:
1. Copia os arquivos para C:\AICS
2. Instala o AICS-Service via NSSM
3. Adiciona o tray icon ao startup do Windows
#>

# =========================
# REQUER ADMINISTRADOR
# =========================
if (-not ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent() `
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    $scriptFile = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
    Start-Process powershell -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`"" `
        -Verb RunAs
    exit
}

# =========================
# CONFIG
# =========================
$ServiceName = "AICS-Service"
$SourcePath  = $PSScriptRoot
if (-not $SourcePath) { $SourcePath = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$DestPath    = "C:\AICS"

$ScriptPath  = "$DestPath\ativar-ics.ps1"
$TrayPath    = "$DestPath\tray.ps1"
$LogFile     = "$DestPath\aics.log"
$nssm        = "$DestPath\nssm.exe"

# =========================
# COPIA ARQUIVOS
# =========================
Write-Host "Copiando arquivos para $DestPath..."

if (-not (Test-Path $DestPath)) {
    New-Item -ItemType Directory -Path $DestPath | Out-Null
}

$filesToCopy = @(
    "ativar-ics.ps1",
    "tray.ps1",
    "config.txt",
    "nssm.exe"
)

foreach ($file in $filesToCopy) {
    $src = "$SourcePath\$file"
    if (Test-Path $src) {
        Copy-Item $src $DestPath -Force
    } else {
        Write-Warning "Arquivo não encontrado, ignorando: $file"
    }
}

# =========================
# VALIDAÇÕES
# =========================
if (-not (Test-Path $ScriptPath)) {
    Write-Error "ativar-ics.ps1 não encontrado em $DestPath"
    pause
    exit 1
}

if (-not (Test-Path $nssm)) {
    Write-Error "nssm.exe não encontrado em $DestPath"
    pause
    exit 1
}

# =========================
# INSTALA SERVIÇO
# =========================
Write-Host "Instalando serviço AICS..."

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removendo serviço existente..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    & $nssm remove $ServiceName confirm | Out-Null
}

& $nssm install $ServiceName "powershell.exe" `
    "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

& $nssm set $ServiceName Start             SERVICE_AUTO_START
& $nssm set $ServiceName AppRestartDelay   5000
& $nssm set $ServiceName AppExit           Default Restart
& $nssm set $ServiceName AppThrottle       1500
& $nssm set $ServiceName AppStdout         $LogFile
& $nssm set $ServiceName AppStderr         $LogFile
& $nssm set $ServiceName AppRotateFiles    1
& $nssm set $ServiceName AppRotateOnline   1
& $nssm set $ServiceName AppRotateBytes    5242880

Write-Host "Iniciando serviço..."
Start-Service -Name $ServiceName -ErrorAction SilentlyContinue

# =========================
# TRAY NO STARTUP DO WINDOWS
# =========================
Write-Host "Configurando tray no startup..."

$trayCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$TrayPath`""
$regKey  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

Set-ItemProperty -Path $regKey -Name "AICS-Tray" -Value $trayCmd

# inicia o tray imediatamente (sem bloquear)
Start-Process powershell -ArgumentList `
    "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$TrayPath`"" `
    -WindowStyle Hidden

# =========================
# CONCLUÍDO
# =========================
Write-Host ""
Write-Host "=========================================="
Write-Host " AICS instalado com sucesso!"
Write-Host "=========================================="
Write-Host " Servico : $ServiceName (em execucao)"
Write-Host " Tray    : iniciado e configurado no startup"
Write-Host " Log     : $LogFile"
Write-Host "=========================================="
Write-Host ""

pause
