<#
.SYNOPSIS
Instalador do AICS como serviço Windows via NSSM.

.DESCRIPTION
Este script instala o AICS (Automatic Internet Connection Sharing Service)
como um serviço Windows persistente usando NSSM.

O serviço executa o script principal:
<pasta do instalador>\ativar-ics.ps1

CARACTERÍSTICAS:
- Criação automática do serviço
- Remoção e recriação se já existir
- Inicialização automática no boot
- Logs centralizados na raiz do projeto
- Execução como SYSTEM (alta confiabilidade)

REQUISITOS:
- NSSM instalado e disponível no PATH (ou via "nssm")
- Executar como Administrador
#>

# =========================
# CONFIG
# =========================
$ServiceName = "AICS-Service"
$BasePath    = $PSScriptRoot
if (-not $BasePath) { $BasePath = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $BasePath) { $BasePath = "C:\AICS" }

$ScriptPath  = "$BasePath\ativar-ics.ps1"
$LogFile     = "$BasePath\log.txt"

# NSSM
$nssm = "$BasePath\nssm.exe"

# =========================
# VALIDAÇÕES
# =========================
Write-Host "Iniciando instalação do AICS..."

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Script principal não encontrado: $ScriptPath"
    exit 1
}

# Testa NSSM
try {
    & $nssm version | Out-Null
} catch {
    Write-Error "NSSM não encontrado no sistema. Instale e tente novamente."
    exit 1
}

# =========================
# REMOVE SERVIÇO SE EXISTIR
# =========================
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($existing) {
    Write-Host "Removendo serviço existente..."
    & $nssm remove $ServiceName confirm | Out-Null
}

# =========================
# CRIA SERVIÇO
# =========================
Write-Host "Criando serviço AICS..."

& $nssm install $ServiceName "powershell.exe" `
    "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# =========================
# CONFIGURAÇÃO DO SERVIÇO
# =========================
& $nssm set $ServiceName Start SERVICE_AUTO_START

# reinício automático se falhar
& $nssm set $ServiceName AppRestartDelay 5000
& $nssm set $ServiceName AppExit Default Restart
& $nssm set $ServiceName AppThrottle 1500

# logs (stdout e stderr separados, rotação a cada 5 MB)
& $nssm set $ServiceName AppStdout $LogFile
& $nssm set $ServiceName AppStderr "$BasePath\error.txt"
& $nssm set $ServiceName AppRotateFiles 1
& $nssm set $ServiceName AppRotateOnline 1
& $nssm set $ServiceName AppRotateBytes 5242880

# =========================
# FINALIZAÇÃO
# =========================
Write-Host "Serviço instalado com sucesso: $ServiceName"

Start-Service $ServiceName

Write-Host "AICS está ativo e rodando como serviço Windows."