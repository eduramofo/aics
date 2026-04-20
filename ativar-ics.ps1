<#
.SYNOPSIS
AICS - Automatic Internet Connection Sharing Service

.DESCRIPTION
Este script configura automaticamente o compartilhamento de internet (ICS)
no Windows de forma dinâmica e resiliente.

FUNCIONALIDADES:
- Detecta automaticamente a interface com internet (rota padrão)
- Lê a interface privada via arquivo de configuração local
- Evita reconfiguração desnecessária (idempotente)
- Configura ICS via COM (HNetCfg.HNetShare)
- Configura IP fixo na rede interna
- Funciona em modo serviço (NSSM)

CONFIGURAÇÃO:
Editar o arquivo config.txt na mesma pasta:

interface=Ethernet 2
private_ip=10.10.10.1

REQUISITOS:
- Executar como Administrador
- Serviço ICS (SharedAccess) habilitado no Windows
#>

# =========================
# CONFIG BASE
# =========================
$BasePath               = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $BasePath) { $BasePath = "C:\AICS" }
$PrefixLength           = 24
$TimeoutPrivateSeconds  = 30
$TimeoutPublicSeconds   = 30
$LogFile                = "$BasePath\aics.log"

# =========================
# LOG
# =========================
function Write-Log {
    param ([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# =========================
# LÊ CONFIG
# =========================
$PrivateInterface = "Ethernet 2"
$PrivateIP        = "10.10.10.1"

$configPath = "$BasePath\config.txt"
if (Test-Path $configPath) {
    foreach ($line in Get-Content $configPath) {
        if ($line -match "^interface=(.+)$")  { $PrivateInterface = $Matches[1].Trim() }
        if ($line -match "^private_ip=(.+)$") { $PrivateIP        = $Matches[1].Trim() }
    }
} else {
    Write-Log "config.txt não encontrado. Usando valores padrão (interface='$PrivateInterface', ip='$PrivateIP')." "AVISO"
}

# =========================
# FUNÇÕES
# =========================

function Wait-InterfaceUp {
    param (
        [string]$InterfaceAlias,
        [int]$TimeoutSeconds = 30
    )

    $i = 0
    while ($i -lt $TimeoutSeconds) {
        $iface = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
        if ($iface -and $iface.Status -eq "Up") {
            return $true
        }

        Start-Sleep 1
        $i++
    }

    return $false
}

function Get-PublicInterface {
    param (
        [string]$PrivateInterface
    )

    $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, InterfaceMetric

    if (-not $routes) { return $null }

    foreach ($route in $routes) {
        $iface = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue

        if (-not $iface) { continue }
        if ($iface.Status -ne "Up") { continue }
        if ($iface.Name -eq $PrivateInterface) { continue }

        return $iface.Name
    }

    return $null
}

# =========================
# ESPERA REDE PRIVADA
# =========================
if (-not (Wait-InterfaceUp -InterfaceAlias $PrivateInterface -TimeoutSeconds $TimeoutPrivateSeconds)) {
    Write-Log "Interface privada '$PrivateInterface' não ficou disponível em ${TimeoutPrivateSeconds}s." "ERRO"
    exit 1
}

# =========================
# DETECTA INTERFACE PÚBLICA
# =========================
$PublicInterface = $null
$i = 0

while (-not $PublicInterface -and $i -lt $TimeoutPublicSeconds) {
    $PublicInterface = Get-PublicInterface -PrivateInterface $PrivateInterface

    if (-not $PublicInterface) {
        Start-Sleep 1
        $i++
    }
}

if (-not $PublicInterface) {
    Write-Log "Não foi possível detectar interface com internet em ${TimeoutPublicSeconds}s." "ERRO"
    exit 1
}

# =========================
# MAPEAMENTO ICS (COM OBJECT)
# =========================
$netShare = New-Object -ComObject HNetCfg.HNetShare
$map = @{}

foreach ($conn in $netShare.EnumEveryConnection()) {
    $props = $netShare.NetConnectionProps($conn)
    $map[$props.Name] = $conn
}

if (-not $map.ContainsKey($PublicInterface) -or -not $map.ContainsKey($PrivateInterface)) {
    Write-Log "Interfaces não encontradas no sistema ICS (pub='$PublicInterface', priv='$PrivateInterface')." "ERRO"
    exit 1
}

$pub  = $map[$PublicInterface]
$priv = $map[$PrivateInterface]

$cfgPub  = $netShare.INetSharingConfigurationForINetConnection($pub)
$cfgPriv = $netShare.INetSharingConfigurationForINetConnection($priv)

# =========================
# VERIFICA SE PRECISA ALTERAR (IDEMPOTENTE)
# =========================
$needsChange = $false

if (-not $cfgPub.SharingEnabled -or $cfgPub.SharingConnectionType -ne 0) {
    $needsChange = $true
}

if (-not $cfgPriv.SharingEnabled -or $cfgPriv.SharingConnectionType -ne 1) {
    $needsChange = $true
}

# =========================
# APLICA ICS SE NECESSÁRIO
# =========================
if ($needsChange) {
    $cfgPub.DisableSharing()
    $cfgPriv.DisableSharing()

    $cfgPub.EnableSharing(0)   # Internet
    $cfgPriv.EnableSharing(1)  # Rede privada

    Write-Log "ICS configurado (pub='$PublicInterface', priv='$PrivateInterface')."
}

# =========================
# CONFIGURA IP FIXO (LAN)
# =========================
$currentIP = Get-NetIPAddress -InterfaceAlias $PrivateInterface -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $PrivateIP }

if (-not $currentIP) {
    Remove-NetIPAddress -InterfaceAlias $PrivateInterface -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress `
        -InterfaceAlias $PrivateInterface `
        -IPAddress $PrivateIP `
        -PrefixLength $PrefixLength

    Write-Log "IP fixo configurado: $PrivateIP na interface '$PrivateInterface'."
}

# =========================
# LOOP DE MONITORAMENTO
# Mantém o serviço vivo e reaplica config se a rede mudar
# =========================
Write-Log "Servico ativo. Monitorando a cada 60s..."

while ($true) {
    Start-Sleep -Seconds 60

    # Reverifica interface publica
    $newPublic = Get-PublicInterface -PrivateInterface $PrivateInterface

    if (-not $newPublic) { continue }

    # Reaplica ICS se a interface publica tiver mudado
    if ($newPublic -ne $PublicInterface) {
        Write-Log "Interface publica mudou: '$PublicInterface' -> '$newPublic'. Reaplicando ICS..."
        $PublicInterface = $newPublic

        if (-not $map.ContainsKey($PublicInterface)) {
            foreach ($conn in $netShare.EnumEveryConnection()) {
                $props = $netShare.NetConnectionProps($conn)
                $map[$props.Name] = $conn
            }
        }

        if ($map.ContainsKey($PublicInterface)) {
            $pub     = $map[$PublicInterface]
            $cfgPub  = $netShare.INetSharingConfigurationForINetConnection($pub)
            $cfgPriv = $netShare.INetSharingConfigurationForINetConnection($priv)

            $cfgPub.DisableSharing()
            $cfgPriv.DisableSharing()
            $cfgPub.EnableSharing(0)
            $cfgPriv.EnableSharing(1)

            Write-Log "ICS reaplicado (pub='$PublicInterface', priv='$PrivateInterface')."
        }
    }

    # Reaplica IP fixo se tiver sumido
    $checkIP = Get-NetIPAddress -InterfaceAlias $PrivateInterface -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $PrivateIP }

    if (-not $checkIP) {
        Remove-NetIPAddress -InterfaceAlias $PrivateInterface -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $PrivateInterface -IPAddress $PrivateIP -PrefixLength $PrefixLength -ErrorAction SilentlyContinue
        Write-Log "IP fixo reaplicado: $PrivateIP na interface '$PrivateInterface'."
    }
}