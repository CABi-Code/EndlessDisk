# ============================================================
# EndlessDisk — Main GUI Form (async, non-blocking)
# ============================================================

function Show-MainGui {
    $cfg = $script:Config

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "EndlessDisk v$($script:AppVersion)"
    $form.Size = New-Object System.Drawing.Size(550, 780)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
            [System.IO.Path]::Combine($env:SystemRoot, "System32", "shell32.dll"))
    } catch {}

    $fTitle  = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $fNorm   = New-Object System.Drawing.Font("Segoe UI", 9)
    $fSmall  = New-Object System.Drawing.Font("Segoe UI", 8)
    $fMono   = New-Object System.Drawing.Font("Consolas", 7.5)
    $cOk     = [System.Drawing.Color]::FromArgb(34, 139, 34)
    $cNo     = [System.Drawing.Color]::FromArgb(200, 60, 60)
    $cWarn   = [System.Drawing.Color]::FromArgb(200, 150, 0)
    $cGray   = [System.Drawing.Color]::FromArgb(130, 130, 130)

    # ---- STATUS GROUP ----
    $grpStatus = New-Object System.Windows.Forms.GroupBox
    $grpStatus.Text = "Статус компонентов"
    $grpStatus.Font = $fTitle
    $grpStatus.Location = New-Object System.Drawing.Point(12, 8)
    $grpStatus.Size = New-Object System.Drawing.Size(510, 155)
    $form.Controls.Add($grpStatus)

    $stLabels = @{}; $stBtns = @{}; $stBtns2 = @{}
    $items = @("rclone","WinFsp","Конфиг S3","Контекстное меню","Диск")
    $sy = 22
    foreach ($it in $items) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "${it}:"
        $lbl.Font = $fNorm
        $lbl.Location = New-Object System.Drawing.Point(15, $sy)
        $lbl.Size = New-Object System.Drawing.Size(130, 22)
        $grpStatus.Controls.Add($lbl)

        $stl = New-Object System.Windows.Forms.Label
        $stl.Font = $fNorm
        $stl.Location = New-Object System.Drawing.Point(150, $sy)
        $stl.Size = New-Object System.Drawing.Size(150, 22)
        $grpStatus.Controls.Add($stl)
        $stLabels[$it] = $stl

        $b1 = New-Object System.Windows.Forms.Button
        $b1.Font = $fSmall
        $b1.Location = New-Object System.Drawing.Point(310, ($sy - 2))
        $b1.Size = New-Object System.Drawing.Size(95, 24)
        $b1.FlatStyle = "Flat"
        $grpStatus.Controls.Add($b1)
        $stBtns[$it] = $b1

        $b2 = New-Object System.Windows.Forms.Button
        $b2.Font = $fSmall
        $b2.Location = New-Object System.Drawing.Point(410, ($sy - 2))
        $b2.Size = New-Object System.Drawing.Size(85, 24)
        $b2.FlatStyle = "Flat"
        $b2.Visible = $false
        $grpStatus.Controls.Add($b2)
        $stBtns2[$it] = $b2

        $sy += 26
    }

    # ---- SETTINGS GROUP ----
    $grpSettings = New-Object System.Windows.Forms.GroupBox
    $grpSettings.Text = "Настройки диска"
    $grpSettings.Font = $fTitle
    $grpSettings.Location = New-Object System.Drawing.Point(12, 170)
    $grpSettings.Size = New-Object System.Drawing.Size(510, 225)
    $form.Controls.Add($grpSettings)

    $tbs = @{}
    $sMap = [ordered]@{
        "DriveLetter"  = "Буква диска"
        "RcloneRemote" = "Имя remote"
        "Bucket"       = "Бакет (bucket)"
        "Domain"       = "Домен"
        "EndpointHost" = "Эндпоинт S3"
        "Region"       = "Регион"
        "CacheSize"    = "Размер кэша"
        "Transfers"    = "Потоков загрузки"
    }
    $ty = 22
    foreach ($e in $sMap.GetEnumerator()) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "$($e.Value):"
        $lbl.Font = $fNorm
        $lbl.Location = New-Object System.Drawing.Point(15, ($ty + 3))
        $lbl.Size = New-Object System.Drawing.Size(140, 20)
        $grpSettings.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Font = $fNorm
        $tb.Location = New-Object System.Drawing.Point(160, $ty)
        $tb.Size = New-Object System.Drawing.Size(335, 22)
        $tb.Text = [string]$cfg[$e.Key]
        $grpSettings.Controls.Add($tb)
        $tbs[$e.Key] = $tb
        $ty += 25
    }

    # ---- S3 KEYS GROUP (with blur overlay) ----
    $grpKeys = New-Object System.Windows.Forms.GroupBox
    $grpKeys.Text = "Ключи S3"
    $grpKeys.Font = $fTitle
    $grpKeys.Location = New-Object System.Drawing.Point(12, 402)
    $grpKeys.Size = New-Object System.Drawing.Size(510, 85)
    $form.Controls.Add($grpKeys)

    $lblAK = New-Object System.Windows.Forms.Label
    $lblAK.Text = "Access Key:"
    $lblAK.Font = $fNorm
    $lblAK.Location = New-Object System.Drawing.Point(15, 25)
    $lblAK.Size = New-Object System.Drawing.Size(85, 20)
    $grpKeys.Controls.Add($lblAK)
    $tbAK = New-Object System.Windows.Forms.TextBox
    $tbAK.Font = $fNorm
    $tbAK.Location = New-Object System.Drawing.Point(105, 22)
    $tbAK.Size = New-Object System.Drawing.Size(390, 22)
    $grpKeys.Controls.Add($tbAK)

    $lblSK = New-Object System.Windows.Forms.Label
    $lblSK.Text = "Secret Key:"
    $lblSK.Font = $fNorm
    $lblSK.Location = New-Object System.Drawing.Point(15, 52)
    $lblSK.Size = New-Object System.Drawing.Size(85, 20)
    $grpKeys.Controls.Add($lblSK)
    $tbSK = New-Object System.Windows.Forms.TextBox
    $tbSK.Font = $fNorm
    $tbSK.Location = New-Object System.Drawing.Point(105, 49)
    $tbSK.Size = New-Object System.Drawing.Size(390, 22)
    $grpKeys.Controls.Add($tbSK)

    # Blur overlay panel
    $keysOverlay = New-Object System.Windows.Forms.Panel
    $keysOverlay.BackColor = [System.Drawing.Color]::FromArgb(220, 225, 235)
    $keysOverlay.Location = New-Object System.Drawing.Point(5, 18)
    $keysOverlay.Size = New-Object System.Drawing.Size(500, 62)
    $keysOverlay.Cursor = [System.Windows.Forms.Cursors]::Hand
    $grpKeys.Controls.Add($keysOverlay)
    $keysOverlay.BringToFront()

    $lblOverlayText = New-Object System.Windows.Forms.Label
    $lblOverlayText.Text = "Нажмите для отображения ключей S3"
    $lblOverlayText.Font = $fNorm
    $lblOverlayText.ForeColor = $cGray
    $lblOverlayText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblOverlayText.Dock = [System.Windows.Forms.DockStyle]::Fill
    $keysOverlay.Controls.Add($lblOverlayText)

    $keysRevealed = $false
    $revealKeys = {
        $keysOverlay.Visible = $false
        $script:keysRevealed = $true
    }
    $keysOverlay.Add_Click($revealKeys)
    $lblOverlayText.Add_Click($revealKeys)

    # Eye button to re-hide
    $btnHideKeys = New-Object System.Windows.Forms.Button
    $btnHideKeys.Text = "Скрыть"
    $btnHideKeys.Font = $fSmall
    $btnHideKeys.Location = New-Object System.Drawing.Point(440, 0)
    $btnHideKeys.Size = New-Object System.Drawing.Size(65, 18)
    $btnHideKeys.FlatStyle = "Flat"
    $btnHideKeys.ForeColor = $cGray
    $btnHideKeys.Add_Click({ $keysOverlay.Visible = $true; $keysOverlay.BringToFront() })
    $grpKeys.Controls.Add($btnHideKeys)

    # Load current keys
    $keys = Get-S3Keys
    if ($keys) { $tbAK.Text = $keys.AccessKey; $tbSK.Text = $keys.SecretKey }

    # ---- DISK INFO ----
    $grpDisk = New-Object System.Windows.Forms.GroupBox
    $grpDisk.Text = "Информация о диске"
    $grpDisk.Font = $fTitle
    $grpDisk.Location = New-Object System.Drawing.Point(12, 494)
    $grpDisk.Size = New-Object System.Drawing.Size(510, 42)
    $form.Controls.Add($grpDisk)

    $lblDiskInfo = New-Object System.Windows.Forms.Label
    $lblDiskInfo.Font = $fNorm
    $lblDiskInfo.ForeColor = $cGray
    $lblDiskInfo.Location = New-Object System.Drawing.Point(15, 18)
    $lblDiskInfo.Size = New-Object System.Drawing.Size(480, 20)
    $lblDiskInfo.Text = "Диск не подключен"
    $grpDisk.Controls.Add($lblDiskInfo)

    # ---- OPTIONS ----
    $chkAuto = New-Object System.Windows.Forms.CheckBox
    $chkAuto.Text = "Запускать диск при старте Windows (без окон)"
    $chkAuto.Font = $fNorm
    $chkAuto.Location = New-Object System.Drawing.Point(15, 544)
    $chkAuto.Size = New-Object System.Drawing.Size(400, 20)
    $chkAuto.Checked = (Test-Autostart)
    $form.Controls.Add($chkAuto)

    $lblAutoWarn = New-Object System.Windows.Forms.Label
    $lblAutoWarn.Text = "Запись в HKCU\...\Run. Диск подключится автоматически без видимых окон."
    $lblAutoWarn.Font = $fSmall
    $lblAutoWarn.ForeColor = $cGray
    $lblAutoWarn.Location = New-Object System.Drawing.Point(33, 564)
    $lblAutoWarn.Size = New-Object System.Drawing.Size(480, 16)
    $form.Controls.Add($lblAutoWarn)

    $chkShort = New-Object System.Windows.Forms.CheckBox
    $chkShort.Text = "Ярлык на рабочем столе"
    $chkShort.Font = $fNorm
    $chkShort.Location = New-Object System.Drawing.Point(15, 584)
    $chkShort.Size = New-Object System.Drawing.Size(400, 20)
    $chkShort.Checked = (Test-DesktopShortcut)
    $form.Controls.Add($chkShort)

    $lblShortWarn = New-Object System.Windows.Forms.Label
    $lblShortWarn.Text = "Ярлык откроет это окно настроек без консоли."
    $lblShortWarn.Font = $fSmall
    $lblShortWarn.ForeColor = $cGray
    $lblShortWarn.Location = New-Object System.Drawing.Point(33, 604)
    $lblShortWarn.Size = New-Object System.Drawing.Size(480, 16)
    $form.Controls.Add($lblShortWarn)

    # ---- BUTTONS ----
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Сохранить"
    $btnSave.Font = $fNorm
    $btnSave.Location = New-Object System.Drawing.Point(12, 626)
    $btnSave.Size = New-Object System.Drawing.Size(125, 32)
    $btnSave.FlatStyle = "Flat"
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 230)
    $form.Controls.Add($btnSave)

    $btnMount = New-Object System.Windows.Forms.Button
    $btnMount.Text = "Подключить диск"
    $btnMount.Font = $fNorm
    $btnMount.Location = New-Object System.Drawing.Point(143, 626)
    $btnMount.Size = New-Object System.Drawing.Size(130, 32)
    $btnMount.FlatStyle = "Flat"
    $btnMount.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 250)
    $form.Controls.Add($btnMount)

    $btnUnmount = New-Object System.Windows.Forms.Button
    $btnUnmount.Text = "Отключить диск"
    $btnUnmount.Font = $fNorm
    $btnUnmount.Location = New-Object System.Drawing.Point(279, 626)
    $btnUnmount.Size = New-Object System.Drawing.Size(125, 32)
    $btnUnmount.FlatStyle = "Flat"
    $btnUnmount.BackColor = [System.Drawing.Color]::FromArgb(250, 235, 230)
    $form.Controls.Add($btnUnmount)

    $btnUninstall = New-Object System.Windows.Forms.Button
    $btnUninstall.Text = "Полное удаление"
    $btnUninstall.Font = $fSmall
    $btnUninstall.Location = New-Object System.Drawing.Point(410, 626)
    $btnUninstall.Size = New-Object System.Drawing.Size(112, 32)
    $btnUninstall.FlatStyle = "Flat"
    $btnUninstall.ForeColor = [System.Drawing.Color]::FromArgb(180, 50, 50)
    $form.Controls.Add($btnUninstall)

    # ---- STATUS BAR (bottom) ----
    $pnlStatus = New-Object System.Windows.Forms.Panel
    $pnlStatus.Location = New-Object System.Drawing.Point(0, 665)
    $pnlStatus.Size = New-Object System.Drawing.Size(550, 70)
    $pnlStatus.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 248)
    $form.Controls.Add($pnlStatus)

    $barProgress = New-Object System.Windows.Forms.ProgressBar
    $barProgress.Location = New-Object System.Drawing.Point(12, 6)
    $barProgress.Size = New-Object System.Drawing.Size(520, 18)
    $barProgress.Style = "Continuous"
    $barProgress.Value = 0
    $barProgress.Visible = $false
    $pnlStatus.Controls.Add($barProgress)

    $lblStatusText = New-Object System.Windows.Forms.Label
    $lblStatusText.Font = $fNorm
    $lblStatusText.Location = New-Object System.Drawing.Point(12, 28)
    $lblStatusText.Size = New-Object System.Drawing.Size(520, 18)
    $lblStatusText.Text = "EndlessDisk v$($script:AppVersion)"
    $lblStatusText.ForeColor = $cGray
    $pnlStatus.Controls.Add($lblStatusText)

    $lblBlockText = New-Object System.Windows.Forms.Label
    $lblBlockText.Font = $fMono
    $lblBlockText.Location = New-Object System.Drawing.Point(12, 48)
    $lblBlockText.Size = New-Object System.Drawing.Size(520, 16)
    $lblBlockText.ForeColor = [System.Drawing.Color]::FromArgb(170, 170, 180)
    $pnlStatus.Controls.Add($lblBlockText)

    # ---- HELPER: collect all interactive buttons ----
    $allBtns = @($btnSave, $btnMount, $btnUnmount, $btnUninstall) +
               @($stBtns.Values) + @($stBtns2.Values)

    function Set-ButtonsEnabled([bool]$Enabled) {
        foreach ($b in $allBtns) { $b.Enabled = $Enabled }
    }

    # ---- UPDATE STATUS ----
    $updateStatus = {
        $hasRclone = $null -ne (Find-Rclone)
        $hasWinFsp = Find-WinFsp
        $hasKeys   = $null -ne (Get-S3Keys)
        $hasMenu   = Test-ContextMenu
        $mounted   = Test-DiskMounted

        # rclone
        if ($hasRclone) {
            $stLabels["rclone"].Text = "Установлен"; $stLabels["rclone"].ForeColor = $cOk
            $stBtns["rclone"].Text = "Переустановить"; $stBtns["rclone"].Visible = $true
            $stBtns2["rclone"].Text = "Удалить"; $stBtns2["rclone"].Visible = $true
        } else {
            $stLabels["rclone"].Text = "Не найден"; $stLabels["rclone"].ForeColor = $cNo
            $stBtns["rclone"].Text = "Установить"; $stBtns["rclone"].Visible = $true
            $stBtns2["rclone"].Visible = $false
        }

        # WinFsp
        if ($hasWinFsp) {
            $stLabels["WinFsp"].Text = "Установлен"; $stLabels["WinFsp"].ForeColor = $cOk
            $stBtns["WinFsp"].Text = "Переустановить"; $stBtns["WinFsp"].Visible = $true
            $stBtns2["WinFsp"].Text = "Удалить"; $stBtns2["WinFsp"].Visible = $true
        } else {
            $stLabels["WinFsp"].Text = "Не найден"; $stLabels["WinFsp"].ForeColor = $cNo
            $stBtns["WinFsp"].Text = "Установить"; $stBtns["WinFsp"].Visible = $true
            $stBtns2["WinFsp"].Visible = $false
        }

        # S3 Config
        if ($hasKeys) {
            $stLabels["Конфиг S3"].Text = "Настроен"; $stLabels["Конфиг S3"].ForeColor = $cOk
            $stBtns["Конфиг S3"].Visible = $false; $stBtns2["Конфиг S3"].Visible = $false
        } else {
            $stLabels["Конфиг S3"].Text = "Не настроен"; $stLabels["Конфиг S3"].ForeColor = $cNo
            $stBtns["Конфиг S3"].Text = "Настроить"; $stBtns["Конфиг S3"].Visible = $true
            $stBtns2["Конфиг S3"].Visible = $false
        }

        # Context menu
        if ($hasMenu) {
            $stLabels["Контекстное меню"].Text = "Установлено"; $stLabels["Контекстное меню"].ForeColor = $cOk
            $stBtns["Контекстное меню"].Text = "Переустановить"; $stBtns["Контекстное меню"].Visible = $true
            $stBtns2["Контекстное меню"].Text = "Удалить"; $stBtns2["Контекстное меню"].Visible = $true
        } else {
            $stLabels["Контекстное меню"].Text = "Не установлено"; $stLabels["Контекстное меню"].ForeColor = $cNo
            $stBtns["Контекстное меню"].Text = "Установить"; $stBtns["Контекстное меню"].Visible = $true
            $stBtns2["Контекстное меню"].Visible = $false
        }

        # Disk
        if ($mounted) {
            $stLabels["Диск"].Text = "$($script:Config.DriveLetter) подключен"
            $stLabels["Диск"].ForeColor = $cOk
            $stBtns["Диск"].Text = "Отключить"; $stBtns["Диск"].Visible = $true
            $stBtns2["Диск"].Visible = $false

            $space = Get-DiskSpace
            if ($space) {
                $lblDiskInfo.Text = "Занято: $($space.UsedGB) ГБ  |  Свободно: $($space.FreeGB) ГБ"
                $lblDiskInfo.ForeColor = $cOk
            } else {
                $lblDiskInfo.Text = "Диск подключен (данные о размере недоступны)"
                $lblDiskInfo.ForeColor = $cGray
            }
        } else {
            $stLabels["Диск"].Text = "Не подключен"; $stLabels["Диск"].ForeColor = $cGray
            $stBtns["Диск"].Text = "Подключить"; $stBtns["Диск"].Visible = $true
            $stBtns2["Диск"].Visible = $false
            $lblDiskInfo.Text = "Диск не подключен"
            $lblDiskInfo.ForeColor = $cGray
        }
    }

    # ---- ASYNC RUN ----
    $script:uninstallPhase = 0

    $runAsync = {
        param([scriptblock]$Work, [string]$Label, [scriptblock]$OnDone)
        if ($script:bgState.Running) {
            Show-Msg "EndlessDisk" "Дождитесь завершения текущей операции." "Warning"
            return
        }
        Set-ButtonsEnabled $false
        $barProgress.Visible = $true
        $barProgress.Style = "Marquee"
        $barProgress.MarqueeAnimationSpeed = 30
        $lblStatusText.Text = $Label
        $lblStatusText.ForeColor = $cWarn
        $script:onDoneCallback = $OnDone
        Start-BackgroundTask -Work $Work
    }

    # ---- POLL TIMER ----
    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = 100
    $pollTimer.Add_Tick({
        if ($script:bgState.Running) {
            if ($script:bgState.Status) { $lblStatusText.Text = $script:bgState.Status }
            if ($script:bgState.Block)  { $lblBlockText.Text  = $script:bgState.Block }
            if ($script:bgState.Percent -ge 0) {
                $barProgress.Style = "Continuous"
                $barProgress.Value = [Math]::Min($script:bgState.Percent, 100)
            }
        }
        if ($script:bgState.Done -and $script:bgState.Running) {
            Complete-BackgroundTask
            $barProgress.Visible = $false
            $barProgress.Value = 0
            $lblBlockText.Text = ""
            if ($script:bgState.Error) {
                $lblStatusText.Text = "Ошибка: $($script:bgState.Error)"
                $lblStatusText.ForeColor = $cNo
                Show-Msg "EndlessDisk — Ошибка" $script:bgState.Error "Error"
            } else {
                $lblStatusText.Text = "Готово"
                $lblStatusText.ForeColor = $cOk
            }
            Set-ButtonsEnabled $true
            & $updateStatus
            if ($script:onDoneCallback) {
                $cb = $script:onDoneCallback
                $script:onDoneCallback = $null
                & $cb
            }
        }
    })

    # ---- BUTTON HANDLERS ----

    # rclone install
    $stBtns["rclone"].Add_Click({
        $doIt = Show-YesNo "EndlessDisk — rclone" (
            "Будет скачан rclone с официального сайта rclone.org.`n" +
            "Файлы установятся в: $env:LOCALAPPDATA\rclone\`n`n" +
            "Продолжить скачивание и установку?")
        if (-not $doIt) { return }
        $stLabels["rclone"].Text = "Установка..."
        $stLabels["rclone"].ForeColor = $cWarn
        & $runAsync { Install-RcloneAuto } "Установка rclone..." $null
    })

    # rclone uninstall
    $stBtns2["rclone"].Add_Click({
        if (-not (Show-YesNo "EndlessDisk" "Удалить rclone?")) { return }
        $stLabels["rclone"].Text = "Удаление..."
        $stLabels["rclone"].ForeColor = $cWarn
        & $runAsync { Uninstall-Rclone } "Удаление rclone..." $null
    })

    # WinFsp install
    $stBtns["WinFsp"].Add_Click({
        $doIt = Show-YesNo "EndlessDisk — WinFsp" (
            "WinFsp — драйвер файловой системы для монтирования.`n`n" +
            "Будет скачан установщик с GitHub (winfsp/winfsp).`n" +
            "Потребуются права администратора.`n`n" +
            "Продолжить?")
        if (-not $doIt) { return }
        $stLabels["WinFsp"].Text = "Установка..."
        $stLabels["WinFsp"].ForeColor = $cWarn
        & $runAsync { Install-WinFspAuto } "Установка WinFsp..." $null
    })

    # WinFsp uninstall
    $stBtns2["WinFsp"].Add_Click({
        if (-not (Show-YesNo "EndlessDisk" "Удалить WinFsp?`nПотребуются права администратора.")) { return }
        $stLabels["WinFsp"].Text = "Удаление..."
        $stLabels["WinFsp"].ForeColor = $cWarn
        & $runAsync { Uninstall-WinFsp } "Удаление WinFsp..." $null
    })

    # S3 config hint
    $stBtns["Конфиг S3"].Add_Click({
        $keysOverlay.Visible = $false
        $tbAK.Focus()
        Show-Msg "EndlessDisk" "Введите Access Key и Secret Key, затем нажмите 'Сохранить'."
    })

    # Context menu install/uninstall
    $stBtns["Контекстное меню"].Add_Click({
        $stLabels["Контекстное меню"].Text = "Установка..."
        $stLabels["Контекстное меню"].ForeColor = $cWarn
        & $runAsync { Install-ContextMenu } "Установка контекстного меню..." $null
    })
    $stBtns2["Контекстное меню"].Add_Click({
        if (-not (Show-YesNo "EndlessDisk" "Удалить контекстное меню?")) { return }
        $stLabels["Контекстное меню"].Text = "Удаление..."
        $stLabels["Контекстное меню"].ForeColor = $cWarn
        & $runAsync { Uninstall-ContextMenu } "Удаление контекстного меню..." $null
    })

    # Disk mount/unmount (inline button)
    $stBtns["Диск"].Add_Click({
        if (Test-DiskMounted) {
            if (Show-YesNo "EndlessDisk" "Отключить диск $($script:Config.DriveLetter)?") {
                $stLabels["Диск"].Text = "Отключение..."
                $stLabels["Диск"].ForeColor = $cWarn
                & $runAsync { Do-Unmount } "Отключение диска..." $null
            }
        } else {
            $stLabels["Диск"].Text = "Подключение..."
            $stLabels["Диск"].ForeColor = $cWarn
            & $runAsync {
                Do-Mount
                Start-Sleep -Seconds 3
                $state.Status = "Диск подключен"
                $state.Percent = 100
            } "Подключение диска..." $null
        }
    })

    # Save button
    $btnSave.Add_Click({
        $newCfg = @{}
        foreach ($e in $sMap.GetEnumerator()) {
            $val = $tbs[$e.Key].Text.Trim()
            if ($e.Key -eq "Transfers") { $newCfg[$e.Key] = [int]$val }
            else { $newCfg[$e.Key] = $val }
        }
        Save-Config $newCfg
        $script:Config = $newCfg
        Update-GlobalVars

        $ak = $tbAK.Text.Trim()
        $sk = $tbSK.Text.Trim()
        if ($ak -and $sk) { Save-RcloneConfig $ak $sk }

        # Autostart
        if ($chkAuto.Checked -and -not (Test-Autostart)) {
            $ok = Show-YesNo "EndlessDisk — Автозапуск" (
                "Включить автозапуск?`n`n" +
                "При старте Windows диск подключится`n" +
                "автоматически без видимых окон.`n`n" +
                "Запись будет добавлена в реестр:`n" +
                "  HKCU\...\Run\EndlessDisk")
            if ($ok) { Add-Autostart } else { $chkAuto.Checked = $false }
        } elseif (-not $chkAuto.Checked) { Remove-Autostart }

        # Shortcut
        if ($chkShort.Checked -and -not (Test-DesktopShortcut)) {
            $ok = Show-YesNo "EndlessDisk — Ярлык" (
                "Создать ярлык на рабочем столе?`n`n" +
                "Ярлык откроет окно настроек EndlessDisk.")
            if ($ok) { Add-DesktopShortcut } else { $chkShort.Checked = $false }
        } elseif (-not $chkShort.Checked) { Remove-DesktopShortcut }

        & $updateStatus
        $lblStatusText.Text = "Настройки сохранены"
        $lblStatusText.ForeColor = $cOk
    })

    # Mount/Unmount buttons
    $btnMount.Add_Click({
        $stLabels["Диск"].Text = "Подключение..."
        $stLabels["Диск"].ForeColor = $cWarn
        & $runAsync {
            Do-Mount
            Start-Sleep -Seconds 3
            $state.Status = "Диск подключен"
            $state.Percent = 100
        } "Подключение диска..." $null
    })
    $btnUnmount.Add_Click({
        if (Show-YesNo "EndlessDisk" "Отключить диск?") {
            $stLabels["Диск"].Text = "Отключение..."
            $stLabels["Диск"].ForeColor = $cWarn
            & $runAsync { Do-Unmount } "Отключение диска..." $null
        }
    })

    # Full uninstall
    $btnUninstall.Add_Click({
        if (-not (Show-YesNo "EndlessDisk — Полное удаление" (
            "Будут удалены:`n" +
            "  - Контекстное меню, автозапуск, ярлык`n" +
            "  - VBS-лаунчер, конфигурация`n" +
            "  - Диск будет отключен`n`n" +
            "Далее будет предложено удалить rclone,`n" +
            "WinFsp и конфигурацию rclone.`n`n" +
            "Продолжить?"))) { return }

        & $runAsync { Do-FullUninstallWork } "Удаление EndlessDisk..." {
            # Phase 2: ask about rclone config
            $deleteAll = Show-YesNo "EndlessDisk — Конфиг rclone" (
                "Удалить конфигурацию rclone?`n`n" +
                "Да — удалить ВЕСЬ конфиг rclone.`n" +
                "Нет — удалить только секцию [$($script:Config.RcloneRemote)].")

            $deleteRcloneExe = $false
            if (Find-Rclone) {
                $deleteRcloneExe = Show-YesNo "EndlessDisk — rclone" "Удалить rclone.exe и его папки?"
            }
            $deleteWinFsp = $false
            if (Find-WinFsp) {
                $deleteWinFsp = Show-YesNo "EndlessDisk — WinFsp" "Удалить WinFsp?"
            }

            & $runAsync {
                Do-FullUninstallRcloneConfig $deleteAll
                if ($deleteRcloneExe) { Do-FullUninstallRcloneExe }
                if ($deleteWinFsp) { Do-FullUninstallWinFsp }
                $state.Status  = "Удаление завершено"
                $state.Percent = 100
            } "Завершение удаления..." {
                Show-Msg "EndlessDisk" "Программа полностью удалена.`n`nФайл VKDiskMenu.ps1 можно удалить вручную."
                $form.Close()
            }
        }
    })

    # ---- Init & Show ----
    & $updateStatus
    $pollTimer.Start()
    $form.ShowDialog() | Out-Null
    $pollTimer.Stop()
    $pollTimer.Dispose()
    $form.Dispose()
}
