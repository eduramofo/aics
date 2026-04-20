<#
.SYNOPSIS
AICS Tray - Ícone de bandeja para monitorar o serviço AICS.

.DESCRIPTION
Exibe um ícone na área de notificação do Windows com status em tempo real
do AICS-Service. Sem dependências externas.

REQUISITOS:
- Executar como Administrador (para controlar o serviço)
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# CONFIG
# =========================
$ServiceName = "AICS-Service"
$BasePath    = "C:\AICS"
$LogFile     = "$BasePath\aics.log"

# =========================
# FUNÇÕES
# =========================

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

# =========================
# ÍCONE E MENU
# =========================
$tray          = New-Object System.Windows.Forms.NotifyIcon
$tray.Visible  = $true

$menu          = New-Object System.Windows.Forms.ContextMenuStrip

$itemStatus    = $menu.Items.Add("Verificando...")
$itemStatus.Enabled = $false

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$itemLog       = $menu.Items.Add("Abrir log")
$itemLog.Add_Click({
    if (Test-Path $LogFile) {
        Start-Process "notepad.exe" $LogFile
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Arquivo de log não encontrado:`n$LogFile", "AICS",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
})

$itemRestart   = $menu.Items.Add("Reiniciar serviço")
$itemRestart.Add_Click({
    Restart-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
})

$itemToggle    = $menu.Items.Add("...")
$itemToggle.Add_Click({
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    } else {
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    }
})

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$itemExit      = $menu.Items.Add("Sair")
$itemExit.Add_Click({
    $timer.Stop()
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$tray.ContextMenuStrip = $menu

# =========================
# ATUALIZAÇÃO DE STATUS
# =========================
function Update-Status {
    $running = Get-ServiceRunning

    if ($running) {
        $tray.Icon  = New-TrayIcon([System.Drawing.Color]::FromArgb(34, 197, 94))
        $tray.Text  = "AICS — Ativo"
        $itemStatus.Text  = "● Ativo"
        $itemToggle.Text  = "Parar serviço"
        $itemRestart.Enabled = $true
    } else {
        $tray.Icon  = New-TrayIcon([System.Drawing.Color]::FromArgb(220, 38, 38))
        $tray.Text  = "AICS — Parado"
        $itemStatus.Text  = "○ Parado"
        $itemToggle.Text  = "Iniciar serviço"
        $itemRestart.Enabled = $false
    }
}

# =========================
# TIMER (atualiza a cada 5s)
# =========================
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Status })
$timer.Start()

Update-Status

# =========================
# LOOP
# =========================
[System.Windows.Forms.Application]::Run()
