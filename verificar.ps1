<#
.SYNOPSIS
Verifica se o AICS está instalado e funcionando corretamente.

COMO USAR:
Clique com o botão direito e selecione "Executar com PowerShell"
(não precisa ser Administrador para verificar)
#>

$DestPath    = "C:\AICS"
$ServiceName = "AICS-Service"
$regKey      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

function Ok   { param($msg) Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Fail { param($msg) Write-Host "  [X]   $msg" -ForegroundColor Red }
function Info { param($msg) Write-Host "        $msg" -ForegroundColor Gray }

Write-Host ""
Write-Host "=========================================="
Write-Host "  VERIFICACAO AICS"
Write-Host "=========================================="
Write-Host ""

# --- PASTA ---
Write-Host "[ Pasta ]"
if (Test-Path $DestPath) {
    Ok "C:\AICS existe"
} else {
    Fail "C:\AICS NAO existe - o setup nao copiou os arquivos"
}

# --- ARQUIVOS ---
Write-Host ""
Write-Host "[ Arquivos em C:\AICS ]"
foreach ($f in @("ativar-ics.ps1","tray.ps1","config.txt","nssm.exe","aics.log")) {
    $p = "$DestPath\$f"
    if (Test-Path $p) { Ok $f } else { Fail "$f ausente" }
}

# --- SERVICO ---
Write-Host ""
Write-Host "[ Servico Windows ]"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") {
        Ok "$ServiceName esta RODANDO"
    } else {
        Fail "$ServiceName existe mas status: $($svc.Status)"
    }
} else {
    Fail "$ServiceName NAO esta instalado"
}

# --- TRAY NO STARTUP ---
Write-Host ""
Write-Host "[ Tray no Startup ]"
$trayVal = (Get-ItemProperty -Path $regKey -Name "AICS-Tray" -ErrorAction SilentlyContinue)."AICS-Tray"
if ($trayVal) {
    Ok "AICS-Tray configurado no startup"
    Info $trayVal
} else {
    Fail "AICS-Tray NAO esta no startup"
}

# --- TRAY PROCESS ---
Write-Host ""
Write-Host "[ Processo Tray ]"
$proc = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*tray.ps1*"
} | Select-Object -First 1
if ($proc) {
    Ok "Tray rodando (PID $($proc.Id))"
} else {
    Fail "Processo tray nao encontrado em execucao"
}

# --- LOG ---
Write-Host ""
Write-Host "[ Ultimas linhas do log ]"
$log = "$DestPath\aics.log"
if (Test-Path $log) {
    Ok "Log encontrado"
    Get-Content $log -Tail 5 | ForEach-Object { Info $_ }
} else {
    Fail "Log nao encontrado (servico nunca rodou?)"
}

Write-Host ""
Write-Host "=========================================="
Write-Host ""
pause
