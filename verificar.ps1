# Salva saida num arquivo e abre no Notepad
$logPath = "$env:USERPROFILE\Desktop\AICS-verificar.txt"
Start-Transcript -Path $logPath -Force | Out-Null

$DestPath    = "C:\AICS"
$ServiceName = "AICS-Service"
$regKey      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

function Ok   { param($msg) Write-Host "  [OK]  $msg" }
function Fail { param($msg) Write-Host "  [X]   $msg" }
function Info { param($msg) Write-Host "        $msg" }

Write-Host ""
Write-Host "=========================================="
Write-Host "  VERIFICACAO AICS"
Write-Host "=========================================="
Write-Host ""

Write-Host "[ Pasta ]"
if (Test-Path $DestPath) { Ok "C:\AICS existe" }
else { Fail "C:\AICS NAO existe - setup nao rodou corretamente" }

Write-Host ""
Write-Host "[ Arquivos em C:\AICS ]"
foreach ($f in @("ativar-ics.ps1","tray.ps1","config.txt","nssm.exe","aics.log")) {
    if (Test-Path "$DestPath\$f") { Ok $f } else { Fail "$f ausente" }
}

Write-Host ""
Write-Host "[ Servico Windows ]"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") { Ok "$ServiceName RODANDO" }
    else { Fail "$ServiceName existe mas status: $($svc.Status)" }
} else { Fail "$ServiceName NAO instalado" }

Write-Host ""
Write-Host "[ Tray no Startup ]"
$trayVal = (Get-ItemProperty -Path $regKey -Name "AICS-Tray" -ErrorAction SilentlyContinue)."AICS-Tray"
if ($trayVal) { Ok "AICS-Tray no startup"; Info $trayVal }
else { Fail "AICS-Tray NAO esta no startup" }

Write-Host ""
Write-Host "[ Ultimas linhas do log ]"
$log = "$DestPath\aics.log"
if (Test-Path $log) {
    Ok "Log encontrado"
    Get-Content $log -Tail 5 | ForEach-Object { Info $_ }
} else { Fail "Log nao encontrado (servico nunca rodou?)" }

Write-Host ""
Write-Host "=========================================="
Write-Host "  Resultado salvo em: $logPath"
Write-Host "=========================================="

Stop-Transcript | Out-Null
Start-Process notepad.exe $logPath
