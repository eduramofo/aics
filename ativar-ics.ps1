<#
.SYNOPSIS
AICS - Automatic Internet Connection Sharing Service

.DESCRIPTION
Configura NAT via Windows NetNat (mais confiável que ICS via COM).
Faz NAT de toda a sub-rede privada para a interface pública, incluindo
tráfego originado pelo próprio host (permite ping -S <ip_privado> funcionar).

CONFIGURAÇÃO:
Editar o arquivo config.txt na mesma pasta:

interface=Ethernet
private_ip=10.10.10.1

REQUISITOS:
- Executar como Administrador
- Windows 10/11
#>

# =========================
# CONFIG BASE
# =========================
$BasePath              = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $BasePath) { $BasePath = "C:\AICS" }
$PrefixLength          = 24
$NatName               = "AICS-NAT"
$TimeoutPrivateSeconds = 30
$TimeoutPublicSeconds  = 30
$LogDir                = "$BasePath\logs"
$LogFile               = "$LogDir\log.txt"
$ErrorFile             = "$LogDir\error.txt"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# =========================
# LOG
# =========================
function Write-Log {
    param ([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# =========================
# LÊ CONFIG
# =========================
$PrivateInterface = "Ethernet"
$PrivateIP        = "10.10.10.1"

$configPath = "$BasePath\config.txt"
if (Test-Path $configPath) {
    foreach ($line in Get-Content $configPath) {
        if ($line -match "^interface=(.+)$")  { $PrivateInterface = $Matches[1].Trim() }
        if ($line -match "^private_ip=(.+)$") { $PrivateIP        = $Matches[1].Trim() }
    }
} else {
    Write-Log "config.txt nao encontrado. Usando valores padrao." "AVISO"
}

# Calcula prefixo da rede (ex: 10.10.10.0/24)
$ipParts      = $PrivateIP -split '\.'
$NetworkPrefix = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$PrefixLength"

# =========================
# FUNÇÕES
# =========================
function Wait-InterfaceUp {
    param ([string]$InterfaceAlias, [int]$TimeoutSeconds = 30)
    $i = 0
    while ($i -lt $TimeoutSeconds) {
        $iface = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
        if ($iface -and $iface.Status -eq "Up") { return $true }
        Start-Sleep 1
        $i++
    }
    return $false
}

function Get-PublicInterface {
    param ([string]$PrivateInterface)
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

function Test-IPExists {
    param ([string]$InterfaceAlias, [string]$IPAddress)
    $out = netsh interface ipv4 show addresses name="$InterfaceAlias" 2>$null
    return ($out -match [regex]::Escape($IPAddress))
}

function Set-FixedIP {
    param ([string]$InterfaceAlias, [string]$IPAddress, [int]$PrefixLen)
    $existing = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -PrefixLength $PrefixLen `
        -ErrorAction SilentlyContinue | Out-Null
    $waited = 0
    while ($waited -lt 15) {
        if (Test-IPExists -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress) { return $true }
        Start-Sleep 1
        $waited++
    }
    Write-Log "IP $IPAddress nao apareceu em $InterfaceAlias apos ${waited}s." "AVISO"
    return $false
}

function Apply-NATConfig {
    param ([string]$PubIface, [string]$PrivIface, [string]$NetPrefix)

    # Forwarding em ambas as interfaces (necessário para rotear pacotes)
    Get-NetIPInterface | Where-Object { $_.InterfaceAlias -eq $PubIface -or $_.InterfaceAlias -eq $PrivIface } |
        Set-NetIPInterface -Forwarding Enabled -ErrorAction SilentlyContinue

    # WeakHost: permite que pacotes com source IP de outra interface saiam/entrem
    Set-NetIPInterface -InterfaceAlias $PubIface  -WeakHostSend    Enabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $PubIface  -WeakHostReceive Enabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $PrivIface -WeakHostSend    Enabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $PrivIface -WeakHostReceive Enabled -ErrorAction SilentlyContinue

    # Define interface privada como Private (firewall permite forwarding; Public bloqueia)
    $privIdx = (Get-NetAdapter -Name $PrivIface -ErrorAction SilentlyContinue).ifIndex
    if ($privIdx) {
        Set-NetConnectionProfile -InterfaceIndex $privIdx -NetworkCategory Private -ErrorAction SilentlyContinue
        Write-Log "Interface '$PrivIface' definida como Private (firewall)"
    }

    # Firewall: permite todo tráfego da rede privada entrando pela interface Ethernet
    # (necessário para WinNAT encaminhar pacotes de dispositivos conectados)
    Remove-NetFirewallRule -DisplayName "AICS-Private-In" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "AICS-Private-In" `
        -Direction Inbound -InterfaceAlias $PrivIface `
        -RemoteAddress $NetPrefix -Action Allow -Protocol Any `
        -ErrorAction SilentlyContinue | Out-Null
    Write-Log "Firewall: regra AICS-Private-In criada (allow $NetPrefix inbound em '$PrivIface')"

    # Garante que o WMI provider MSFT_NetNat está registrado
    # (HRESULT 0x80041010 = WBEM_E_INVALID_CLASS indica provider ausente)
    $natClass = Get-CimClass -Namespace root/StandardCimv2 -ClassName MSFT_NetNat -ErrorAction SilentlyContinue
    if (-not $natClass) {
        Write-Log "MSFT_NetNat WMI class ausente - registrando mof..."
        $mof = "$env:SystemRoot\System32\wbem\NetNat.mof"
        if (Test-Path $mof) {
            & mofcomp.exe $mof 2>&1 | Out-Null
            Start-Sleep 3
        }
        # Garante que o driver winnat está iniciado
        $winnat = Get-Service -Name winnat -ErrorAction SilentlyContinue
        if ($winnat -and $winnat.Status -ne 'Running') {
            Start-Service winnat -ErrorAction SilentlyContinue
            Start-Sleep 2
        }
        # Habilita feature se ainda não disponível (requer reboot mas tenta de qualquer forma)
        $natClass2 = Get-CimClass -Namespace root/StandardCimv2 -ClassName MSFT_NetNat -ErrorAction SilentlyContinue
        if (-not $natClass2) {
            Write-Log "MSFT_NetNat ainda ausente apos mofcomp. Verificar feature 'Microsoft-Windows-Subsystem-Linux' ou Hyper-V." "ERRO"
        }
    }

    # Remove TODOS os NetNats existentes (qualquer conflito impede criação)
    $allNats = Get-NetNat -ErrorAction SilentlyContinue
    if ($allNats) {
        $allNats | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "NetNats anteriores removidos: $(($allNats | Select-Object -ExpandProperty Name) -join ', ')"
    }

    # Cria NAT
    $created = New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $NetPrefix -ErrorAction Stop
    Write-Log "NetNat criado: $NetPrefix (id=$($created.Name))"

    # Confirma estado
    $pub  = Get-NetIPInterface -InterfaceAlias $PubIface  -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $priv = Get-NetIPInterface -InterfaceAlias $PrivIface -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $nat  = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    Write-Log "NATConfig pub='$PubIface' Forwarding=$($pub.Forwarding) WeakHostSend=$($pub.WeakHostSend) WeakHostReceive=$($pub.WeakHostReceive)"
    Write-Log "NATConfig priv='$PrivIface' Forwarding=$($priv.Forwarding) WeakHostSend=$($priv.WeakHostSend) WeakHostReceive=$($priv.WeakHostReceive)"
    Write-Log "NetNat='$($nat.Name)' Prefix=$($nat.InternalIPInterfaceAddressPrefix) State=$($nat.Active)"
}

# =========================
# DESATIVA ICS E PARA SharedAccess (conflita com NetNat)
# =========================
try {
    $ns = New-Object -ComObject HNetCfg.HNetShare -ErrorAction SilentlyContinue
    foreach ($conn in $ns.EnumEveryConnection()) {
        $cfg = $ns.INetSharingConfigurationForINetConnection($conn)
        if ($cfg.SharingEnabled) { $cfg.DisableSharing() }
    }
} catch {}

$sharedAccess = Get-Service -Name SharedAccess -ErrorAction SilentlyContinue
if ($sharedAccess -and $sharedAccess.Status -eq 'Running') {
    Stop-Service -Name SharedAccess -Force -ErrorAction SilentlyContinue
    Write-Log "Servico SharedAccess parado (conflita com NetNat)."
}

# =========================
# ESPERA REDE PRIVADA
# =========================
if (-not (Wait-InterfaceUp -InterfaceAlias $PrivateInterface -TimeoutSeconds $TimeoutPrivateSeconds)) {
    Write-Log "Interface privada '$PrivateInterface' nao ficou disponivel em ${TimeoutPrivateSeconds}s." "ERRO"
    exit 1
}

# =========================
# DETECTA INTERFACE PÚBLICA
# =========================
$PublicInterface = $null
$i = 0
while (-not $PublicInterface -and $i -lt $TimeoutPublicSeconds) {
    $PublicInterface = Get-PublicInterface -PrivateInterface $PrivateInterface
    if (-not $PublicInterface) { Start-Sleep 1; $i++ }
}

if (-not $PublicInterface) {
    Write-Log "Nao foi possivel detectar interface com internet em ${TimeoutPublicSeconds}s." "ERRO"
    exit 1
}

Write-Log "Interface publica detectada: '$PublicInterface'."

# =========================
# CONFIGURA IP FIXO (LAN)
# =========================
if (Test-IPExists -InterfaceAlias $PrivateInterface -IPAddress $PrivateIP) {
    Write-Log "IP fixo ja presente: $PrivateIP na interface '$PrivateInterface'."
} else {
    if (Set-FixedIP -InterfaceAlias $PrivateInterface -IPAddress $PrivateIP -PrefixLen $PrefixLength) {
        Write-Log "IP fixo configurado: $PrivateIP na interface '$PrivateInterface'."
    }
}

# =========================
# APLICA NAT E FORWARDING
# =========================
Apply-NATConfig -PubIface $PublicInterface -PrivIface $PrivateInterface -NetPrefix $NetworkPrefix

# =========================
# LOOP DE MONITORAMENTO
# =========================
Write-Log "Servico ativo. Monitorando a cada 60s..."

while ($true) {
    Start-Sleep -Seconds 60

    $newPublic = Get-PublicInterface -PrivateInterface $PrivateInterface
    if (-not $newPublic) { continue }

    if ($newPublic -ne $PublicInterface) {
        Write-Log "Interface publica mudou: '$PublicInterface' -> '$newPublic'. Reaplicando..."
        $PublicInterface = $newPublic
        Apply-NATConfig -PubIface $PublicInterface -PrivIface $PrivateInterface -NetPrefix $NetworkPrefix
    }

    if (-not (Test-IPExists -InterfaceAlias $PrivateInterface -IPAddress $PrivateIP)) {
        if (Set-FixedIP -InterfaceAlias $PrivateInterface -IPAddress $PrivateIP -PrefixLen $PrefixLength) {
            Write-Log "IP fixo reaplicado: $PrivateIP na interface '$PrivateInterface'."
        }
    }
}
