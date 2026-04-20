@echo off
chcp 65001 >nul
title Instalador AICS

:: ---- Verificar Admin ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissao de Administrador...
    powershell -Command "Start-Process cmd -ArgumentList '/c cd /d ""%~dp0"" && ""%~f0""' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo.
echo ==========================================
echo  INSTALANDO AICS
echo  Pasta: %~dp0
echo ==========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; try { . '%~dp0setup.ps1' } catch { Write-Host ''; Write-Host 'ERRO: ' $_ -ForegroundColor Red }"

echo.
echo ==========================================
echo  Concluido. Verifique as mensagens acima.
echo ==========================================
echo.
pause
