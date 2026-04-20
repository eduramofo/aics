Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# CONFIG
$ServiceName      = "AICS-Service"
$BasePath         = "C:\AICS"
$LogFile          = "$BasePath\log.txt"
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
    # Lê o IP privado do config
    $srcIP = "10.10.10.1"
    if (Test-Path $configPath) {
        foreach ($line in Get-Content $configPath) {
            if ($line -match "^private_ip=(.+)$") { $srcIP = $Matches[1].Trim() }
        }
    }

    # Teste real: ping -S <IP privado> 8.8.8.8 com 1 pacote e timeout de 2s
    $result = & ping.exe -S $srcIP -n 1 -w 2000 8.8.8.8 2>&1
    return ($LASTEXITCODE -eq 0)
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

$script:_checking = $false

$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 20000
$timer.Add_Tick({
    if ($script:_checking) { return }
    $script:_checking = $true
    try { Update-Status } finally { $script:_checking = $false }
})
$timer.Start()

Update-Status

[System.Windows.Forms.Application]::Run()
