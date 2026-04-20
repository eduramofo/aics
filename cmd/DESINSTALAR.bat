@echo off
chcp 65001 >nul
title Desinstalar AICS

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissao de Administrador...
    powershell -Command "Start-Process cmd -ArgumentList '/c cd /d ""%~dp0"" && ""%~f0""' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo.
echo ==========================================
echo  DESINSTALANDO AICS
echo ==========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\desinstalar.ps1"

echo.
pause
