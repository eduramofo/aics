Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# CONFIG
$ServiceName      = "AICS-Service"
$BasePath         = "C:\AICS"
$LogDir           = "$BasePath\logs"
$LogFile          = "$LogDir\log.txt"
$ErrorFile        = "$LogDir\error.txt"
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
    # Modo NetNat: verifica se o NetNat AICS-NAT existe
    $nat = Get-NetNat -Name "AICS-NAT" -ErrorAction SilentlyContinue
    if ($nat) {
        $ping = & ping.exe -n 1 -w 2000 8.8.8.8 2>&1
        return ($LASTEXITCODE -eq 0)
    }

    # Modo ICS: verifica se SharedAccess esta rodando e ha compartilhamento ativo
    $sa = Get-Service -Name SharedAccess -ErrorAction SilentlyContinue
    if ($sa -and $sa.Status -eq 'Running') {
        try {
            $ns = New-Object -ComObject HNetCfg.HNetShare -ErrorAction Stop
            foreach ($conn in @($ns.EnumEveryConnection())) {
                $cfg = $ns.INetSharingConfigurationForINetConnection($conn)
                if ($cfg.SharingEnabled) {
                    $ping = & ping.exe -n 1 -w 2000 8.8.8.8 2>&1
                    return ($LASTEXITCODE -eq 0)
                }
            }
        } catch {}
    }

    return $false
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

$itemErrorLog = $menu.Items.Add("Abrir log de erros")
$itemErrorLog.Add_Click({
    if (Test-Path $ErrorFile) {
        Start-Process "notepad.exe" $ErrorFile
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Nenhum erro registrado.`n$ErrorFile", "AICS",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
})

$itemLogsFolder = $menu.Items.Add("Abrir pasta de logs")
$itemLogsFolder.Add_Click({
    if (Test-Path $LogDir) {
        Start-Process "explorer.exe" $LogDir
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Pasta de logs nao encontrada:`n$LogDir", "AICS",
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
