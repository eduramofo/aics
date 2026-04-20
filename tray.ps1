Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# CONFIG
$ServiceName      = "AICS-Service"
$BasePath         = "C:\AICS"
$LogFile          = "$BasePath\aics.log"
$PrivateInterface = "Ethernet"
$configPath       = "$BasePath\config.txt"
if (Test-Path $configPath) {
    foreach ($line in Get-Content $configPath) {
        if ($line -match "^interface=(.+)$") { $PrivateInterface = $Matches[1].Trim() }
    }
}

function New-TrayIcon {
    param ([System.Drawing.Color]$Color)
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($Color)), 1, 1, 14, 14)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Get-ServiceRunning {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    return ($svc -and $svc.Status -eq "Running")
}

function Get-ICSWorking {
    # Verifica rota padrão existente e saindo pela interface pública
    $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    if (-not $defaultRoute) { return $false }

    $routeIface = (Get-NetAdapter -InterfaceIndex $defaultRoute.InterfaceIndex -ErrorAction SilentlyContinue).Name
    if ($routeIface -eq $PrivateInterface) { return $false }

    # Verifica ICS habilitado em ambas as interfaces
    try {
        $ns     = New-Object -ComObject HNetCfg.HNetShare
        $pubOk  = $false
        $privOk = $false
        foreach ($c in $ns.EnumEveryConnection()) {
            $cfg = $ns.INetSharingConfigurationForINetConnection($c)
            if ($cfg.SharingEnabled) {
                if ($cfg.SharingConnectionType -eq 0) { $pubOk  = $true }
                if ($cfg.SharingConnectionType -eq 1) { $privOk = $true }
            }
        }
        return ($pubOk -and $privOk)
    } catch {
        return $false
    }
}

$tray         = New-Object System.Windows.Forms.NotifyIcon
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$itemStatus          = $menu.Items.Add("Verificando...")
$itemStatus.Enabled  = $false

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$itemLog = $menu.Items.Add("Abrir log")
$itemLog.Add_Click({
    if (Test-Path $LogFile) {
        Start-Process "notepad.exe" $LogFile
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Log nao encontrado:`n$LogFile", "AICS",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
})

$itemRestart = $menu.Items.Add("Reiniciar servico")
$itemRestart.Add_Click({
    Restart-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
})

$itemToggle = $menu.Items.Add("...")
$itemToggle.Add_Click({
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    } else {
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    }
})

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$itemExit = $menu.Items.Add("Sair")
$itemExit.Add_Click({
    $timer.Stop()
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$tray.ContextMenuStrip = $menu

function Update-Status {
    $running = Get-ServiceRunning
    if (-not $running) {
        $tray.Icon           = New-TrayIcon([System.Drawing.Color]::FromArgb(220, 38, 38))
        $tray.Text           = "AICS - Parado"
        $itemStatus.Text     = "[OFF] Servico parado"
        $itemToggle.Text     = "Iniciar servico"
        $itemRestart.Enabled = $false
    } elseif (Get-ICSWorking) {
        $tray.Icon           = New-TrayIcon([System.Drawing.Color]::FromArgb(34, 197, 94))
        $tray.Text           = "AICS - Ativo e funcionando"
        $itemStatus.Text     = "[ON]  ICS ativo e funcionando"
        $itemToggle.Text     = "Parar servico"
        $itemRestart.Enabled = $true
    } else {
        $tray.Icon           = New-TrayIcon([System.Drawing.Color]::FromArgb(234, 179, 8))
        $tray.Text           = "AICS - Servico ativo, ICS falhou"
        $itemStatus.Text     = "[!!]  Servico ativo, sem internet"
        $itemToggle.Text     = "Parar servico"
        $itemRestart.Enabled = $true
    }
}

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Status })
$timer.Start()

Update-Status

[System.Windows.Forms.Application]::Run()
