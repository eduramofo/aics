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
        & $nssm stop $ServiceName confirm 2>$null | Out-Null
        & $nssm remove $ServiceName confirm 2>$null | Out-Null
    } else {
        sc.exe stop $ServiceName | Out-Null
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

# Mata TODOS os processos com arquivos abertos em C:\AICS
# Isso inclui: nssm.exe, powershell.exe (ativar-ics, tray) e qualquer outro
Write-Host "Encerrando processos com arquivos abertos em $DestPath..."

# 1. Mata pelo CommandLine (powershell rodando scripts do AICS)
Get-WmiObject Win32_Process | ForEach-Object {
    $cmd = $_.CommandLine
    if ($cmd -and ($cmd -like "*$DestPath*" -or $cmd -like "*AICS*")) {
        if ($_.ProcessId -ne $PID) {  # nao mata o proprio processo
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Processo encerrado: $($_.Name) (PID $($_.ProcessId))"
        }
    }
}

# 2. Mata o nssm.exe explicitamente (ele mantem handle na pasta)
Get-Process -Name "nssm" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] nssm.exe encerrado (PID $($_.Id))"
}

# Aguarda SO liberar todos os handles de arquivo
Start-Sleep -Seconds 4

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
# Como este script pode estar rodando DE DENTRO de C:\AICS, usamos um processo
# externo (cmd.exe) agendado para deletar a pasta DEPOIS que este script encerrar.
if (Test-Path $DestPath) {
    Write-Host "Agendando remocao da pasta $DestPath..."

    # Tenta remover imediatamente primeiro (funciona se o script nao esta em C:\AICS)
    Remove-Item -Path $DestPath -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path $DestPath) {
        # Pasta ainda existe: agenda via cmd.exe para rodar apos este processo encerrar
        $delCmd = "ping 127.0.0.1 -n 3 >nul & rd /s /q `"$DestPath`""
        Start-Process "cmd.exe" -ArgumentList "/c $delCmd" -WindowStyle Hidden
        Write-Host "  [OK] Remocao agendada. A pasta sera excluida em segundos."
    } else {
        Write-Host "  [OK] Pasta removida."
    }
} else {
    Write-Host "  [--] Pasta $DestPath nao encontrada."
}

Write-Host ""
Write-Host "=============================="
Write-Host "  AICS desinstalado com sucesso."
Write-Host "  A conexao compartilhada foi desativada."
Write-Host "=============================="
Write-Host ""
