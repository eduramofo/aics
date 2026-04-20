# Requer Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptFile = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`"" -Verb RunAs -Wait
    exit
}

$ServiceName  = "AICS-Service"
$DestPath     = "C:\AICS"
$nssm         = "$DestPath\nssm.exe"
$regKey       = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$Interface    = "Ethernet"

Write-Host ""
Write-Host "=============================="
Write-Host "  Desinstalando AICS..."
Write-Host "=============================="
Write-Host ""

# Para e remove o servico
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Parando servico..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (Test-Path $nssm) {
        Write-Host "Removendo servico do Windows..."
        & $nssm remove $ServiceName confirm | Out-Null
    } else {
        sc.exe delete $ServiceName | Out-Null
    }
    Write-Host "  [OK] Servico removido."
} else {
    Write-Host "  [--] Servico nao estava instalado."
}

# Remove tray do startup
$trayVal = (Get-ItemProperty -Path $regKey -Name "AICS-Tray" -ErrorAction SilentlyContinue)."AICS-Tray"
if ($trayVal) {
    Remove-ItemProperty -Path $regKey -Name "AICS-Tray" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Tray removido do startup."
} else {
    Write-Host "  [--] Tray nao estava no startup."
}

# Mata processos do tray em segundo plano rodando tray.ps1
Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" | ForEach-Object {
    if ($_.CommandLine -like "*tray.ps1*") {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Processo tray encerrado."
    }
}

# Remove IP fixo da interface privada
$ip = Get-NetIPAddress -InterfaceAlias $Interface -ErrorAction SilentlyContinue |
      Where-Object { $_.AddressFamily -eq "IPv4" -and $_.PrefixOrigin -ne "Dhcp" }
if ($ip) {
    Remove-NetIPAddress -InterfaceAlias $Interface -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [OK] IP fixo removido da interface '$Interface'."
} else {
    Write-Host "  [--] Nenhum IP estatico encontrado em '$Interface'."
}

# Remove NetNat
$nat = Get-NetNat -Name "AICS-NAT" -ErrorAction SilentlyContinue
if ($nat) {
    Remove-NetNat -Name "AICS-NAT" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [OK] NetNat AICS-NAT removido."
} else {
    Write-Host "  [--] NetNat nao encontrado."
}

# Remove regra de firewall
Remove-NetFirewallRule -DisplayName "AICS-Private-In" -ErrorAction SilentlyContinue
Write-Host "  [OK] Regra de firewall AICS-Private-In removida."

# Restaura Forwarding e WeakHost nas interfaces
foreach ($iface in @($Interface, "Wi-Fi")) {
    Set-NetIPInterface -InterfaceAlias $iface -Forwarding Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $iface -WeakHostSend Disabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $iface -WeakHostReceive Disabled -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Forwarding e WeakHost desativados."

# Remove pasta C:\AICS
if (Test-Path $DestPath) {
    Write-Host "Removendo pasta $DestPath..."
    Remove-Item -Path $DestPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Pasta removida."
} else {
    Write-Host "  [--] Pasta $DestPath nao encontrada."
}

Write-Host ""
Write-Host "=============================="
Write-Host "  AICS desinstalado com sucesso."
Write-Host "  A conexao compartilhada foi desativada."
Write-Host "=============================="
Write-Host ""
