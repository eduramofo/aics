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
        -Verb RunAs -Wait
    exit
}

# =========================
# CONFIG
# =========================
$ErrorActionPreference = "Stop"

$ServiceName = "AICS-Service"
$SourcePath  = $PSScriptRoot
if (-not $SourcePath) { $SourcePath = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$DestPath    = "C:\AICS"

$ScriptPath  = "$DestPath\ativar-ics.ps1"
$TrayPath    = "$DestPath\tray.ps1"
$LogDir      = "$DestPath\logs"
$LogFile     = "$LogDir\log.txt"
$nssm        = "$DestPath\nssm.exe"

# Garante pasta de logs antes do transcript
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$transcriptPath = "$LogDir\install.txt"
Start-Transcript -Path $transcriptPath -Force | Out-Null

Write-Host "DIAGNOSTICO:"
Write-Host "  PSScriptRoot : '$PSScriptRoot'"
Write-Host "  SourcePath   : '$SourcePath'"
Write-Host "  DestPath     : '$DestPath'"
Write-Host ""

try {
    # =========================
    # PREFLIGHT: VERIFICA REQUISITOS
    # =========================
    Write-Host "Verificando requisitos..."
    $preflightOk = $true

    # 1. Versao do Windows
    $build = [System.Environment]::OSVersion.Version.Build
    if ($build -lt 14393) {
        Write-Host "  [ERRO] Windows muito antigo (build $build). Minimo: Windows 10 1607 (build 14393)." -ForegroundColor Red
        $preflightOk = $false
    } else {
        Write-Host "  [OK] Windows build $build"
    }

    # 2. Verifica se winnat service existe e inicia
    $winnat = Get-Service -Name winnat -ErrorAction SilentlyContinue
    if (-not $winnat) {
        Write-Host "  [ERRO] Servico 'winnat' nao encontrado. Este servico e necessario para NetNat." -ForegroundColor Red
        $preflightOk = $false
    } else {
        if ($winnat.Status -ne 'Running') {
            Start-Service winnat -ErrorAction SilentlyContinue
            Start-Sleep 2
        }
        $winnat = Get-Service -Name winnat -ErrorAction SilentlyContinue
        if ($winnat.Status -eq 'Running') {
            Write-Host "  [OK] Servico winnat em execucao."
        } else {
            Write-Host "  [AVISO] Servico winnat existe mas nao iniciou. Tentando registrar WMI..." -ForegroundColor Yellow
        }
    }

    # 3. Registra WMI provider se ausente
    $natClass = Get-CimClass -Namespace root/StandardCimv2 -ClassName MSFT_NetNat -ErrorAction SilentlyContinue
    if (-not $natClass) {
        # Tenta o mof do sistema primeiro; se ausente, usa o bundled no pacote
        $mof = "$env:SystemRoot\System32\wbem\NetNat.mof"
        if (-not (Test-Path $mof)) {
            $bundled = Join-Path $SourcePath "NetNat.mof"
            if (Test-Path $bundled) {
                Write-Host "  [INFO] NetNat.mof ausente no sistema - copiando do pacote..."
                Copy-Item $bundled $mof -Force
            }
        }
        if (Test-Path $mof) {
            & mofcomp.exe $mof 2>&1 | Out-Null
            Start-Sleep 3
        }
        $natClass = Get-CimClass -Namespace root/StandardCimv2 -ClassName MSFT_NetNat -ErrorAction SilentlyContinue
    }

    # 4. Teste real: tenta criar e remover um NetNat de teste
    if ($natClass) {
        try {
            $testNat = New-NetNat -Name "__AICS_TEST__" -InternalIPInterfaceAddressPrefix "192.168.222.0/24" -ErrorAction Stop
            Remove-NetNat -Name "__AICS_TEST__" -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "  [OK] New-NetNat funcional."
        } catch {
            Write-Host "  [ERRO] New-NetNat falhou: $_" -ForegroundColor Red
            $preflightOk = $false
        }
    } else {
        Write-Host "  [ERRO] WMI class MSFT_NetNat ausente mesmo apos tentativa de registro." -ForegroundColor Red
        $preflightOk = $false
    }

    if (-not $preflightOk) {
        Write-Host "" 
        Write-Host "=========================================="  -ForegroundColor Red
        Write-Host "  INSTALACAO ABORTADA - Requisito ausente" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "O AICS requer o componente 'Virtual Machine Platform' do Windows." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Para habilitar, execute no PowerShell como Administrador:" -ForegroundColor Cyan
        Write-Host "  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart" -ForegroundColor White
        Write-Host ""
        Write-Host "Ou via 'Ativar ou desativar recursos do Windows':" -ForegroundColor Cyan
        Write-Host "  Marque: Plataforma de Maquina Virtual (Virtual Machine Platform)" -ForegroundColor White
        Write-Host ""
        Write-Host "Reinicie o computador e instale novamente." -ForegroundColor Yellow
        Write-Host ""
        Stop-Transcript -ErrorAction SilentlyContinue
        pause
        exit 1
    }

    Write-Host "  Todos os requisitos atendidos." -ForegroundColor Green
    Write-Host ""

    # =========================
    # PARA SERVICO ANTES DE COPIAR
    # =========================
    $existingEarly = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingEarly -and $existingEarly.Status -eq "Running") {
        Write-Host "Parando servico existente antes de copiar arquivos..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # =========================
    # COPIA ARQUIVOS
    # =========================
    Write-Host "Copiando arquivos para $DestPath..."

    if (-not (Test-Path $DestPath)) {
        New-Item -ItemType Directory -Path $DestPath | Out-Null
        Write-Host "  Pasta criada: $DestPath"
    }

    $filesToCopy = @(
        "ativar-ics.ps1",
        "tray.ps1",
        "config.txt",
        "nssm.exe",
        "desinstalar.ps1",
        "verificar.ps1",
        "NetNat.mof"
    )

    foreach ($file in $filesToCopy) {
        $src = "$SourcePath\$file"
        if (Test-Path $src) {
            Copy-Item $src $DestPath -Force
            Write-Host "  Copiado: $file"
        } else {
            Write-Warning "Arquivo nao encontrado, ignorando: $src"
        }
    }

    # Copia .bat da subpasta cmd/
    $batFiles = @("INSTALAR.bat", "DESINSTALAR.bat", "STATUS.bat")
    foreach ($bat in $batFiles) {
        $src = "$SourcePath\cmd\$bat"
        if (Test-Path $src) {
            Copy-Item $src $DestPath -Force
            Write-Host "  Copiado: cmd\$bat"
        }
    }

    # =========================
    # VALIDACOES
    # =========================
    if (-not (Test-Path $ScriptPath)) {
        throw "ativar-ics.ps1 nao encontrado em $DestPath (SourcePath era: '$SourcePath')"
    }

    if (-not (Test-Path $nssm)) {
        throw "nssm.exe nao encontrado em $DestPath (SourcePath era: '$SourcePath')"
    }

    # =========================
    # INSTALA SERVICO
    # =========================
    Write-Host "Instalando servico AICS..."

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Removendo servico existente..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        & $nssm remove $ServiceName confirm | Out-Null
    }

    & $nssm install $ServiceName "powershell.exe" `
        "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

    & $nssm set $ServiceName Start           SERVICE_AUTO_START
    & $nssm set $ServiceName AppRestartDelay 5000
    & $nssm set $ServiceName AppExit         Default Restart
    & $nssm set $ServiceName AppThrottle     1500
    & $nssm set $ServiceName AppStderr       "$LogDir\error.txt"
    & $nssm set $ServiceName AppRotateFiles  1
    & $nssm set $ServiceName AppRotateOnline 1
    & $nssm set $ServiceName AppRotateBytes  5242880

    Write-Host "Iniciando servico..."
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
    # CONCLUIDO
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
}
catch {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host " ERRO durante a instalacao:"
    Write-Host " $_"
    Write-Host "=========================================="
    Write-Host ""
}

Stop-Transcript | Out-Null
pause
