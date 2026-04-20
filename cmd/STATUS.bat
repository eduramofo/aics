@echo off
chcp 65001 >nul
title AICS Status

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$svc = Get-Service -Name 'AICS-Service' -ErrorAction SilentlyContinue;" ^
    "Write-Host '';" ^
    "Write-Host '==============================';" ^
    "Write-Host '  AICS - Status do Servico';" ^
    "Write-Host '==============================';" ^
    "if (-not $svc) { Write-Host '  [X] Servico NAO instalado' -ForegroundColor Red }" ^
    "elseif ($svc.Status -eq 'Running') { Write-Host '  [OK] Rodando' -ForegroundColor Green }" ^
    "elseif ($svc.Status -eq 'Paused') { Write-Host '  [!] Pausado (NSSM throttle) - rode: Start-Service AICS-Service' -ForegroundColor Yellow }" ^
    "else { Write-Host \"  [X] Parado (status: $($svc.Status))\" -ForegroundColor Red };" ^
    "Write-Host '';" ^
    "Write-Host '  Interface publica:';" ^
    "$pub = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1 | ForEach-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).Name });" ^
    "Write-Host \"    $pub\";" ^
    "Write-Host '  ICS ativo:';" ^
    "$ics = (Get-Service SharedAccess).Status;" ^
    "Write-Host \"    SharedAccess = $ics\";" ^
    "Write-Host '';" ^
    "Write-Host '  Log (ultimas 5 linhas):';" ^
    "if (Test-Path 'C:\AICS\logs\log.txt') { Get-Content 'C:\AICS\logs\log.txt' -Tail 5 | ForEach-Object { Write-Host \"    $_\" } } else { Write-Host '    (log vazio)' };" ^
    "Write-Host '=============================='; Write-Host ''"

pause
