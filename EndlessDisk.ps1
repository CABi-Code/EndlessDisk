param(
    [string]$Mode,
    [string]$FilePath
)

# 1. ЗАПУСК ЗАСТАВКИ
$SplashScript = {
    Add-Type -AssemblyName System.Windows.Forms
    $S = New-Object Windows.Forms.Form
    $S.Size = New-Object Drawing.Size(400, 100); $S.StartPosition = 'CenterScreen'
    $S.FormBorderStyle = 'None'; $S.TopMost = $true; $S.BackColor = 'White'; $S.Text = 'ED_SPLASH'
    
    $B = New-Object Windows.Forms.Button
    $B.Text = '×'; $B.Size = New-Object Drawing.Size(25, 25); $B.Location = New-Object Drawing.Point(370, 5)
    $B.FlatStyle = 'Flat'; $B.FlatAppearance.BorderSize = 0; $B.Cursor = [System.Windows.Forms.Cursors]::Hand
    $B.Font = New-Object Drawing.Font('Arial', 12)
    
    # Крестик: Убивает родительский процесс и себя
    $B.Add_Click({ 
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId = $pid").ParentProcessId
        Stop-Process -Id $parent -Force -ErrorAction SilentlyContinue
        Stop-Process -Id $pid -Force 
    })
    
    $L = New-Object Windows.Forms.Label
    $L.Text = 'Запуск EndlessDisk... Пожалуйста, подождите'; $L.AutoSize = $true
    $L.Location = New-Object Drawing.Point(50, 40); $L.Font = New-Object Drawing.Font('Segoe UI', 11)
    
    $S.Controls.AddRange(@($B, $L))
    $S.ShowDialog()
}.ToString()

# Запуск
$Bytes = [System.Text.Encoding]::Unicode.GetBytes($SplashScript)
$Encoded = [Convert]::ToBase64String($Bytes)
$AsyncCmd = "powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand $Encoded"
(New-Object -ComObject WScript.Shell).Run($AsyncCmd, 0, $false)

# 2. ПАРАМЕТРЫ И АРГУМЕНТЫ
if (-not $Mode -and $args.Count -ge 1) { $Mode = $args }
if (-not $FilePath -and $args.Count -ge 2) { $FilePath = ($args[1..($args.Count - 1)]) -join " " }

# 3. КОДИРОВКА И БИБЛИОТЕКИ
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$libDir = Join-Path $PSScriptRoot "lib"
. "$libDir\Core.ps1"
. "$libDir\Setup.ps1"
. "$libDir\MainForm.ps1"

# Функция для удаления заставки
function Kill-Splash {
    Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "ED_SPLASH" } | Stop-Process -Force -ErrorAction SilentlyContinue
}

# 4. ЗАПУСК РЕЖИМОВ
switch ($Mode) {
    "mount"     { Kill-Splash; Do-Mount }
    "gui"       { Show-MainGui } 
    "install"   { Kill-Splash; Do-Install }
    "uninstall" { Kill-Splash; Do-FullUninstallWork }
    "copylink"  { Kill-Splash; Do-CopyLink $FilePath }
    "toggleacl" { Kill-Splash; Do-ToggleAcl $FilePath }
    default     { Show-MainGui }
}

Kill-Splash
