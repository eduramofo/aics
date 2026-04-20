# Salva saida num arquivo e abre no Notepad
$logPath = "$env:USERPROFILE\Desktop\AICS-verificar.txt"
Start-Transcript -Path $logPath -Force | Out-Null

$DestPath    = "C:\AICS"
$ServiceName = "AICS-Service"
$regKey      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

$configPath = "$DestPath\config.txt"
$PrivateInterface = "Ethernet"
if (Test-Path $configPath) {
    foreach ($line in Get-Content $configPath) {
        if ($line -match "^interface=(.+)$") { $PrivateInterface = $Matches[1].Trim() }
    }
}

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
foreach ($f in @("ativar-ics.ps1","tray.ps1","config.txt","nssm.exe")) {
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
Write-Host "[ ICS - Compartilhamento de Conexao ]"
try {
    $ns = New-Object -ComObject HNetCfg.HNetShare
    $pubOk = $false
    $privOk = $false
    foreach ($c in $ns.EnumEveryConnection()) {
        $p   = $ns.NetConnectionProps($c)
        $cfg = $ns.INetSharingConfigurationForINetConnection($c)
        if ($cfg.SharingEnabled) {
            if ($cfg.SharingConnectionType -eq 0) {
                Ok "Interface publica (internet): $($p.Name)"
                $pubOk = $true
            } else {
                Ok "Interface privada (LAN):      $($p.Name)"
                $privOk = $true
            }
        }
    }
    if (-not $pubOk)  { Fail "Nenhuma interface publica com ICS ativo" }
    if (-not $privOk) { Fail "Nenhuma interface privada com ICS ativo" }
} catch {
    Fail "Erro ao verificar ICS: $_"
}

Write-Host ""
Write-Host "[ Encaminhamento IP (Forwarding) ]"
$fwdIfaces = Get-NetIPInterface | Where-Object { $_.Forwarding -eq "Enabled" }
if ($fwdIfaces) {
    foreach ($iface in $fwdIfaces) { Ok "Forwarding ativo: $($iface.InterfaceAlias)" }
} else {
    Fail "Forwarding IP nao ativo em nenhuma interface"
}

Write-Host ""
Write-Host "[ Rota Padrao ]"
$defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric | Select-Object -First 1
if ($defaultRoute) {
    $routeIface = (Get-NetAdapter -InterfaceIndex $defaultRoute.InterfaceIndex -ErrorAction SilentlyContinue).Name
    if ($routeIface -ne $PrivateInterface) {
        Ok "Rota padrao: $routeIface (NextHop: $($defaultRoute.NextHop))"
    } else {
        Fail "Rota padrao saindo pela interface PRIVADA '$routeIface' - ICS pode estar errado"
    }
} else {
    Fail "Nenhuma rota padrao encontrada"
}

Write-Host ""
Write-Host "[ Conectividade Internet (ping 8.8.8.8) ]"
$pingResult = Test-Connection -ComputerName "8.8.8.8" -Count 2 -ErrorAction SilentlyContinue
if ($pingResult) {
    $avg = ($pingResult | Measure-Object ResponseTime -Average).Average
    Ok "Ping 8.8.8.8 OK  (media: ${avg}ms)"
} else {
    Fail "Sem resposta de 8.8.8.8 - verificar conexao com internet"
}

Write-Host ""
Write-Host "[ Ultimas linhas do log ]"
$log = "$DestPath\logs\log.txt"
if (Test-Path $log) {
    Ok "Log encontrado"
    Get-Content $log -Tail 5 | ForEach-Object { Info $_ }
} else { Fail "Log nao encontrado (servico nunca rodou?)" }

Write-Host ""
Write-Host "[ Erros do servico (error.txt) ]"
$errLog = "$DestPath\logs\error.txt"
if (Test-Path $errLog) {
    $errLines = Get-Content $errLog -Tail 5
    if ($errLines) {
        Fail "Erros encontrados:"
        $errLines | ForEach-Object { Info $_ }
    } else { Ok "error.txt vazio (sem erros)" }
} else { Ok "error.txt nao existe (sem erros)" }

Write-Host ""
Write-Host "=========================================="
Write-Host "  Resultado salvo em: $logPath"
Write-Host "=========================================="

Stop-Transcript | Out-Null
Start-Process notepad.exe $logPath
