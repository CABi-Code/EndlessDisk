# ============================================================
# EndlessDisk — Main GUI Form (async, non-blocking)
# ============================================================

function Show-MainGui {
	# ================================================
	# EndlessDisk — Объединённый UI (стиль как в первом скрипте)
	# ================================================

	# ==============================================================================
	# EndlessDisk UI - Полная сборка с сохранением оригинальной логики
	# ==============================================================================

	try {
		# 1. СИСТЕМНЫЕ МЕТОДЫ (Сообщение 1)
		Add-Type -TypeDefinition @"
			using System;
			using System.Runtime.InteropServices;
			public class IconHelper {
				[DllImport("shell32.dll", CharSet = CharSet.Auto)]
				public static extern int ExtractIconEx(string lpszFile, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, int nIcons);
				[DllImport("user32.dll", CharSet = CharSet.Auto)]
				public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, IntPtr lParam);
			}
"@ -ErrorAction SilentlyContinue

		Add-Type -TypeDefinition @"
			using System;
			using System.Runtime.InteropServices;
			public class TaskbarHelper {
				[DllImport("shell32.dll", SetLastError = true)]
				public static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
			}
"@ -ErrorAction SilentlyContinue

		Add-Type -TypeDefinition @"
			using System;
			using System.Runtime.InteropServices;
			public class Win32 {
				[DllImport("user32.dll")]
				public static extern IntPtr GetForegroundWindow();
			}
"@ -ErrorAction SilentlyContinue

		[TaskbarHelper]::SetCurrentProcessExplicitAppUserModelID("EndlessDisk.VKCloud.S3.Manager")

		$shell32Path = Join-Path $env:SystemRoot "System32\shell32.dll"
		$hLargeIcon = [IntPtr]::Zero
		$hSmallIcon = [IntPtr]::Zero
		[IconHelper]::ExtractIconEx($shell32Path, 149, [ref]$hLargeIcon, [ref]$hSmallIcon, 1)
	} catch {
		Write-Warning "Ошибка инициализации системных ресурсов: $_"
	}

	# 2. НАСТРОЙКА ГЛАВНОГО ОКНА (Сообщение 1)
	$cfg = $script:Config
	$form = New-Object System.Windows.Forms.Form
	$form.Text = "EndlessDisk v$($script:AppVersion)"
	$form.Size = New-Object System.Drawing.Size(560, 920) # Увеличено до 920, чтобы влез расширенный статус-бар
	$form.StartPosition = "CenterScreen"
	$form.FormBorderStyle = "FixedSingle"
	$form.MaximizeBox = $false
	$form.BackColor = [System.Drawing.Color]::White
	$form.ShowInTaskbar = $true
	$form.ShowIcon = $true

	if ($hLargeIcon -ne [IntPtr]::Zero) {
		$form.Icon = [System.Drawing.Icon]::FromHandle($hLargeIcon)
	}

	# 3. ОБЩИЕ СТИЛИ (Сообщение 1)
	$fHeader = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
	$fTitle  = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
	$fNorm   = New-Object System.Drawing.Font("Segoe UI", 9)
	$fSmall  = New-Object System.Drawing.Font("Segoe UI", 8)
	$fMono   = New-Object System.Drawing.Font("Consolas", 9)
	$cAccent = [System.Drawing.Color]::FromArgb(0, 120, 215)
	$cBgLight = [System.Drawing.Color]::FromArgb(248, 249, 250)
	$cGray   = [System.Drawing.Color]::FromArgb(130, 130, 130)

	# 4. БЛОК: СТАТУС КОМПОНЕНТОВ (Сообщение 1)
	$lblStatusHead = New-Object System.Windows.Forms.Label
	$lblStatusHead.Text = "СТАТУС КОМПОНЕНТОВ"
	$lblStatusHead.Font = $fTitle
	$lblStatusHead.ForeColor = $cAccent
	$lblStatusHead.Location = New-Object System.Drawing.Point(20, 15)
	$lblStatusHead.AutoSize = $true
	$form.Controls.Add($lblStatusHead)
	$stBars = @()

	$pnlStatusList = New-Object System.Windows.Forms.Panel
	$pnlStatusList.Location = New-Object System.Drawing.Point(15, 40)
	$pnlStatusList.Size = New-Object System.Drawing.Size(520, 180) # Высота увеличена
	$pnlStatusList.BackColor = $cBgLight
	$form.Controls.Add($pnlStatusList)

	$stLabels = @{}; $stBtns = @{}; $stBtns2 = @{}; $stActions = @{} # Добавили массив для статус-оверлеев
	$items = @("rclone","WinFsp","Конфиг S3","Контекстное меню","Диск")
	$sy = 10
	foreach ($it in $items) {
		# 1. Название компонента
		$lbl = New-Object System.Windows.Forms.Label
		$lbl.Text = $it; $lbl.Font = $fNorm
		$lbl.Location = New-Object System.Drawing.Point(10, $sy) 
		$lbl.Size = New-Object System.Drawing.Size(120, 20)
		$pnlStatusList.Controls.Add($lbl)

		# 2. Статус (Установлено/Нет)
		$stl = New-Object System.Windows.Forms.Label
		$stl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold) # Сделал жирным
		$stl.Location = New-Object System.Drawing.Point(135, $sy) 
		$stl.Size = New-Object System.Drawing.Size(140, 20)
		$pnlStatusList.Controls.Add($stl)
		$stLabels[$it] = $stl

		# 3. Кнопка 1
		$b1 = New-Object System.Windows.Forms.Button
		$b1.Font = $fSmall; $b1.Location = New-Object System.Drawing.Point(280, $sy)
		$b1.Size = New-Object System.Drawing.Size(100, 26); $b1.FlatStyle = "Flat"
		$pnlStatusList.Controls.Add($b1); $stBtns[$it] = $b1

		# 4. Кнопка 2
		$b2 = New-Object System.Windows.Forms.Button
		$b2.Font = $fSmall; $b2.Location = New-Object System.Drawing.Point(385, $sy)
		$b2.Size = New-Object System.Drawing.Size(100, 26); $b2.FlatStyle = "Flat"
		$b2.Visible = $false
		$pnlStatusList.Controls.Add($b2); $stBtns2[$it] = $b2

		# 5. ОВЕРЛЕЙ (Текст процесса, перекрывающий кнопки)
		$act = New-Object System.Windows.Forms.Label
		$act.Location = New-Object System.Drawing.Point(280, $sy)
		$act.Size = New-Object System.Drawing.Size(205, 26) # Ширина обеих кнопок + зазор
		$act.TextAlign = "MiddleCenter"
		$act.Font = $fNorm
		$act.Visible = $false # По умолчанию скрыт
		$pnlStatusList.Controls.Add($act)
		$stActions[$it] = $act # Сохраняем для обращения
		
		# Прогресс-бар для конкретной строки
		$pb = New-Object System.Windows.Forms.ProgressBar
		$pb.Location = New-Object System.Drawing.Point(280, $sy) # На уровне кнопок
		$pb.Size = New-Object System.Drawing.Size(205, 18) # Во всю длину двух кнопок
		$pb.Style = "Marquee"            # Как у нижнего бара
		$pb.MarqueeAnimationSpeed = 30    # Скорость бега
		$pb.Visible = $false              # Скрыт по умолчанию
		$pnlStatusList.Controls.Add($pb)
		$stBars[$it] = $pb
		
		$sy += 32
	}


	# УПРАВЛЕНИЕ
	
	# для установки rclone:
	$item = "rclone"

	# Прячем кнопки
	$stBtns[$item].Visible = $false
	$stBtns2[$item].Visible = $false

	# Показываем статус процесса
	$stActions[$item].Text = "Установка..."
	$stActions[$item].ForeColor = [System.Drawing.Color]::DarkGoldenrod
	$stActions[$item].Visible = $true

	# Когда всё закончилось (успешно):
	$stActions[$item].Visible = $false
	$stLabels[$item].Text = "Установлено"
	$stLabels[$item].ForeColor = [System.Drawing.Color]::Green # Цвет для статуса
	$stBtns[$item].Text = "Удалить"
	$stBtns[$item].Visible = $true


	# 5. БЛОК: НАСТРОЙКИ (ПАРАМЕТРЫ ПОДКЛЮЧЕНИЯ) (Сообщение 1)
	$lblSettingsHead = New-Object System.Windows.Forms.Label
	$lblSettingsHead.Text = "ПАРАМЕТРЫ ПОДКЛЮЧЕНИЯ"; $lblSettingsHead.Font = $fTitle; $lblSettingsHead.ForeColor = $cAccent; $lblSettingsHead.Location = New-Object System.Drawing.Point(20, 235); $lblSettingsHead.AutoSize = $true
	$form.Controls.Add($lblSettingsHead)

	$tbs = @{}
	$sMap = [ordered]@{"DriveLetter"="Буква диска"; "RcloneRemote"="Имя remote"; "Bucket"="Бакет (bucket)"; "EndpointHost"="Эндпоинт S3"; "CacheSize"="Размер кэша"; "Domain"="Домен"; "Region"="Регион"; "Transfers"="Потоков"}
    $ty = 260
    foreach ($e in $sMap.GetEnumerator()) {

		$currentLabelY = $ty + 0 	 	# Отступ для текста
		$currentTextBoxY = $ty + 0		# Базовая линия для поля ввода
		
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "$($e.Value):" # Добавил двоеточие для красоты
        $lbl.Font = $fNorm
        # X=10, ширина 145 — теперь они точно влезут слева от TextBox
        $lbl.Location = New-Object System.Drawing.Point(10, $currentLabelY) 
        $lbl.Size = New-Object System.Drawing.Size(145, 20)
        $lbl.TextAlign = "MiddleRight"
        $form.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Font = $fNorm
        $tb.Location = New-Object System.Drawing.Point(160, $currentTextBoxY)
        $tb.Size = New-Object System.Drawing.Size(360, 23)
        $tb.BorderStyle = "FixedSingle"
        $tb.Text = [string]$cfg[$e.Key]
        $form.Controls.Add($tb); $tbs[$e.Key] = $tb
        
        $ty += 30
    }

	# === Отображаемый размер диска ===
    $lblDisplayed = New-Object System.Windows.Forms.Label
    $lblDisplayed.Text = "Размер диска:"
    $lblDisplayed.Font = $fNorm
    $lblDisplayed.Location = New-Object System.Drawing.Point(10, $ty)
    $lblDisplayed.Size = New-Object System.Drawing.Size(145, 20)
    $lblDisplayed.TextAlign = "MiddleRight"
    $form.Controls.Add($lblDisplayed)

    $tbDisplayed = New-Object System.Windows.Forms.TextBox
    $tbDisplayed.Font = $fNorm
    $tbDisplayed.Location = New-Object System.Drawing.Point(160, $ty)
    $tbDisplayed.Size = New-Object System.Drawing.Size(200, 23)
    $tbDisplayed.BorderStyle = "FixedSingle"
    $form.Controls.Add($tbDisplayed)

    # Ограничение ввода только цифрами 1-1024
    $tbDisplayed.Add_KeyPress({
        if (-not [char]::IsDigit($_.KeyChar) -and $_.KeyChar -ne 8) {
            $_.Handled = $true
        }
    })

    $cbUnit = New-Object System.Windows.Forms.ComboBox
    $cbUnit.Font = $fNorm
    $cbUnit.Location = New-Object System.Drawing.Point(370, $ty)
    $cbUnit.Size = New-Object System.Drawing.Size(80, 23)
    $cbUnit.DropDownStyle = "DropDownList"
    $cbUnit.Items.AddRange(@("МБ","ГБ","ТБ","ПБ"))
    $cbUnit.SelectedItem = "ГБ"
    $form.Controls.Add($cbUnit)

    # Загрузка текущего значения
    $curSize = if ($cfg["DisplayedSize"]) { $cfg["DisplayedSize"] } else { "1024G" }
    if ($curSize -match '^(\d+)([MGT P])$') {
        $tbDisplayed.Text = $Matches[1]
        $unitMap = @{M="МБ"; G="ГБ"; T="ТБ"; P="ПБ"}
        $cbUnit.SelectedItem = $unitMap[$Matches[2]]
    } else {
        $tbDisplayed.Text = "1024"
        $cbUnit.SelectedItem = "ГБ"
    }
    $ty += 40
    # ===============================================


	# 6. БЛОК: КЛЮЧИ S3 (Сообщение 1 и 2)
	$pnlKeys = New-Object System.Windows.Forms.Panel
	$pnlKeys.Location = New-Object System.Drawing.Point(12, 515); $pnlKeys.Size = New-Object System.Drawing.Size(526, 85)
	$form.Controls.Add($pnlKeys)

	$lblKeysTitle = New-Object System.Windows.Forms.Label
	$lblKeysTitle.Text = "КЛЮЧИ ДОСТУПА S3"; $lblKeysTitle.Font = $fTitle; $lblKeysTitle.ForeColor = $cAccent; $lblKeysTitle.Location = New-Object System.Drawing.Point(8, 0); $lblKeysTitle.AutoSize = $true
	$pnlKeys.Controls.Add($lblKeysTitle)

	$btnHideKeys = New-Object System.Windows.Forms.Button
	$btnHideKeys.Text = "скрыть"; $btnHideKeys.Font = $fSmall; $btnHideKeys.Location = New-Object System.Drawing.Point(450, 0); $btnHideKeys.Size = New-Object System.Drawing.Size(65, 20); $btnHideKeys.FlatStyle = "Flat"; $btnHideKeys.FlatAppearance.BorderSize = 0; $btnHideKeys.ForeColor = $cGray; $btnHideKeys.Cursor = "Hand"
	$pnlKeys.Controls.Add($btnHideKeys)

	$lblAK = New-Object System.Windows.Forms.Label
	$lblAK.Text = "Access Key"; $lblAK.Font = $fSmall; $lblAK.Location = New-Object System.Drawing.Point(5, 25); $lblAK.Size = New-Object System.Drawing.Size(75, 20)
	$pnlKeys.Controls.Add($lblAK)

	$tbAK = New-Object System.Windows.Forms.TextBox; $tbAK.Font = $fMono; $tbAK.Location = New-Object System.Drawing.Point(85, 23); $tbAK.Size = New-Object System.Drawing.Size(430, 22); $tbAK.BorderStyle = "FixedSingle"; $pnlKeys.Controls.Add($tbAK)

	$lblSK = New-Object System.Windows.Forms.Label
	$lblSK.Text = "Secret Key"; $lblSK.Font = $fSmall; $lblSK.Location = New-Object System.Drawing.Point(5, 53); $lblSK.Size = New-Object System.Drawing.Size(75, 20)
	$pnlKeys.Controls.Add($lblSK)

	$tbSK = New-Object System.Windows.Forms.TextBox; $tbSK.Font = $fMono; $tbSK.Location = New-Object System.Drawing.Point(85, 51); $tbSK.Size = New-Object System.Drawing.Size(430, 22); $tbSK.BorderStyle = "FixedSingle"; $pnlKeys.Controls.Add($tbSK)

	$keysOverlay = New-Object System.Windows.Forms.Panel
	$keysOverlay.Bounds = New-Object System.Drawing.Rectangle(0, 23, 545, 52); $keysOverlay.BackColor = $cBgLight; $keysOverlay.Cursor = "Hand"
	$pnlKeys.Controls.Add($keysOverlay); $keysOverlay.BringToFront()

	$lblOverlayText = New-Object System.Windows.Forms.Label
	$lblOverlayText.Text = "Показать ключи"; $lblOverlayText.TextAlign = "MiddleCenter"; $lblOverlayText.Dock = "Fill"; $lblOverlayText.Font = $fSmall
	$keysOverlay.Controls.Add($lblOverlayText)

	$revealKeys = { $keysOverlay.Visible = $false }
	$keysOverlay.Add_Click($revealKeys)
	$lblOverlayText.Add_Click($revealKeys)
	$btnHideKeys.Add_Click({ $keysOverlay.Visible = $true; $keysOverlay.BringToFront() })

	$keys = Get-S3Keys
	if ($keys) { $tbAK.Text = $keys.AccessKey; $tbSK.Text = $keys.SecretKey }

	# 7. БЛОК: СТАТУС ДИСКА (Сообщение 2)
	$pnlDiskInfo = New-Object System.Windows.Forms.Panel
	$pnlDiskInfo.Location = New-Object System.Drawing.Point(12, 610); $pnlDiskInfo.Size = New-Object System.Drawing.Size(526, 78); $pnlDiskInfo.BackColor = $cBgLight
	$form.Controls.Add($pnlDiskInfo)

	$lblDiskInfo = New-Object System.Windows.Forms.Label
	$lblDiskInfo.Font = $fNorm; $lblDiskInfo.Location = New-Object System.Drawing.Point(10, 12); $lblDiskInfo.Size = New-Object System.Drawing.Size(500, 68); $lblDiskInfo.Text = "💿 Диск не подключен"
	$pnlDiskInfo.Controls.Add($lblDiskInfo)

	# 8. ОПЦИИ (Сообщение 2)
	function Add-EDOption($y, $title, $hint, $checked) {
		$chk = New-Object System.Windows.Forms.CheckBox
		$chk.Text = $title; $chk.Font = $fNorm
		$chk.Location = New-Object System.Drawing.Point(17, $y)
		$chk.Size = New-Object System.Drawing.Size(450, 22)
		$chk.Checked = $checked; $chk.FlatStyle = "Flat"
		$lbl = New-Object System.Windows.Forms.Label
		$lbl.Text = $hint; $lbl.Font = $fSmall
		$lbl.ForeColor = $cGray
		$lbl.Location = New-Object System.Drawing.Point(38, $y)
		$lbl.Size = New-Object System.Drawing.Size(480, 15)
		$form.Controls.Add($chk); $form.Controls.Add($lbl)
		return $chk
	}
	$chkAuto  = Add-EDOption 665 "Запускать диск при старте Windows" "Добавляет задачу в реестр (HKCU), запуск произойдет в фоновом режиме." (Test-Autostart)
	$chkShort = Add-EDOption 705 "Создать ярлык на рабочем столе" "Позволяет быстро открывать панель управления без лишних окон." (Test-DesktopShortcut)

	# 9. КНОПКИ ДЕЙСТВИЯ (Сообщение 2)
	$pnlActionBtns = New-Object System.Windows.Forms.Panel
	$pnlActionBtns.Location = New-Object System.Drawing.Point(12, 755)
	$pnlActionBtns.Size = New-Object System.Drawing.Size(530, 40)
	$form.Controls.Add($pnlActionBtns)

	function Create-ActionButton($text, $x, $w, $color) {
		$btn = New-Object System.Windows.Forms.Button
		$btn.Text = $text; $btn.Location = New-Object System.Drawing.Point($x, 0); $btn.Size = New-Object System.Drawing.Size($w, 35); $btn.FlatStyle = "Flat"; $btn.BackColor = $color; $btn.Cursor = "Hand"
		$btn.FlatAppearance.BorderColor = [System.Drawing.Color]::Silver
		$btn.Add_MouseEnter({ $this.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray })
		$btn.Add_MouseLeave({ $this.FlatAppearance.BorderColor = [System.Drawing.Color]::Silver })
		$pnlActionBtns.Controls.Add($btn)
		return $btn
	}

	$btnSave = Create-ActionButton "Сохранить" 0 100 ([System.Drawing.Color]::FromArgb(235, 250, 235))
	$btnMount = Create-ActionButton "Подключить" 105 105 ([System.Drawing.Color]::FromArgb(235, 240, 255))
	$btnUnmount = Create-ActionButton "Отключить" 215 105 ([System.Drawing.Color]::FromArgb(255, 240, 235))
	$btnRefresh = Create-ActionButton "Обновить" 325 95 $cBgLight
	$btnUninstall = Create-ActionButton "Удалить" 425 90 [System.Drawing.Color]::White
	$btnUninstall.ForeColor = [System.Drawing.Color]::Firebrick

	# 10. STATUS BAR (Сообщение 2)
	$pnlStatus = New-Object System.Windows.Forms.Panel
	$pnlStatus.Dock = "Bottom"; $pnlStatus.Height = 85; $pnlStatus.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 252)
	$form.Controls.Add($pnlStatus)

	$pnlBorder = New-Object System.Windows.Forms.Panel
	$pnlBorder.Dock = "Top"; $pnlBorder.Height = 1; $pnlBorder.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 230)
	$pnlStatus.Controls.Add($pnlBorder)

	$barProgress = New-Object System.Windows.Forms.ProgressBar
	$barProgress.Bounds = New-Object System.Drawing.Rectangle(0, 1, 560, 4)
	$barProgress.Style = "Continuous"; $barProgress.Value = 0; $barProgress.Visible = $false
	$pnlStatus.Controls.Add($barProgress)

	$lblStatusText = New-Object System.Windows.Forms.Label
	$lblStatusText.Font = $fNorm; $lblStatusText.Location = New-Object System.Drawing.Point(15, 18); $lblStatusText.Size = New-Object System.Drawing.Size(400, 20)
	$lblStatusText.Text = "Готов к работе"; $lblStatusText.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
	$pnlStatus.Controls.Add($lblStatusText)

	$lblBlockText = New-Object System.Windows.Forms.Label
	$lblBlockText.Font = New-Object System.Drawing.Font("Consolas", 8.5); $lblBlockText.Location = New-Object System.Drawing.Point(15, 42); $lblBlockText.Size = New-Object System.Drawing.Size(350, 18)
	$lblBlockText.ForeColor = [System.Drawing.Color]::Gray
	$pnlStatus.Controls.Add($lblBlockText)


	$flowLinks = New-Object System.Windows.Forms.FlowLayoutPanel
	$flowLinks.FlowDirection = "LeftToRight"; 
    $flowLinks.Location = New-Object System.Drawing.Point(10, 58)
    $flowLinks.Size = New-Object System.Drawing.Size(300, 20)
	$flowLinks.BackColor = [System.Drawing.Color]::Transparent
	$pnlStatus.Controls.Add($flowLinks)

	function Create-FooterLink($text, $url) {
		$lnk = New-Object System.Windows.Forms.LinkLabel
		$lnk.Text = $text
		$lnk.AutoSize = $true
		$lnk.Font = New-Object System.Drawing.Font("Segoe UI", 8)
		$lnk.LinkColor = $cAccent # Убедись, что $cAccent задана выше
		$lnk.ActiveLinkColor = [System.Drawing.Color]::Red
		$lnk.LinkBehavior = "HoverUnderline"
		$lnk.Margin = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
		
		# Сохраняем URL внутрь самого объекта ссылки
		$lnk.Tag = $url 

		# Правильный способ обработки клика
		$lnk.Add_Click({
			# $this — это сама ссылка, на которую нажали. Берем её Tag.
			Start-Process $this.Tag
		})
		
		return $lnk
	}

	$lblVer = New-Object System.Windows.Forms.Label
	$lblVer.Text = "EndlessDisk v$($script:AppVersion)"; $lblVer.Font = New-Object System.Drawing.Font("Segoe UI", 8); $lblVer.ForeColor = [System.Drawing.Color]::Silver; $lblVer.AutoSize = $true

	$flowLinks.Controls.Add($lblVer)
	$flowLinks.Controls.Add((Create-FooterLink "GitHub" "https://github.com"))
	$flowLinks.Controls.Add((Create-FooterLink "Telegram" "https://t.me/cabi_dev"))

	$btnRefresh.Add_Click({
		$lblStatusText.Text = "Обновление статуса..."
		$lblStatusText.ForeColor = [System.Drawing.Color]::DarkGoldenrod
		if (Get-Command "refreshStatusAsync" -ErrorAction SilentlyContinue) { & $refreshStatusAsync }
	})



    # ---- HELPER: collect all interactive buttons ----
    $allBtns = @($btnSave, $btnMount, $btnUnmount, $btnUninstall) +
               @($stBtns.Values) + @($stBtns2.Values)

    function Set-ButtonsEnabled([bool]$Enabled) {
        foreach ($b in $allBtns) { $b.Enabled = $Enabled }
    }


$cOk = [System.Drawing.Color]::FromArgb(60, 150, 100)
$cNo = [System.Drawing.Color]::Red
$cWarn = [System.Drawing.Color]::FromArgb(255, 165, 0)
    # ---- UPDATE STATUS ----
    $applyStatus = {
        param([hashtable]$r)
        if (-not $r) { return }

        # rclone
		$item = "rclone"
		$stActions[$item].Visible = $false # Всегда скрываем оверлей при обновлении
		if ($r.HasRclone) {
			$stLabels[$item].Text = "Установлен"
			$stLabels[$item].ForeColor = [System.Drawing.Color]::SeaGreen # Тот самый мягкий зеленый
			$stBtns[$item].Text = "Переустановить"; $stBtns[$item].Visible = $true
			$stBtns2[$item].Text = "Удалить"; $stBtns2[$item].Visible = $true
		} else {
			$stLabels[$item].Text = "Не найден"
			$stLabels[$item].ForeColor = [System.Drawing.Color]::Firebrick # Мягкий красный
			$stBtns[$item].Text = "Установить"; $stBtns[$item].Visible = $true
			$stBtns2[$item].Visible = $false # Вторая кнопка не нужна, если нечего удалять
		}

        # WinFsp
        if ($r.HasWinFsp) {
            $stLabels["WinFsp"].Text = "Установлен"; $stLabels["WinFsp"].ForeColor = $cOk
            $stBtns["WinFsp"].Text = "Переустановить"; $stBtns["WinFsp"].Visible = $true
            $stBtns2["WinFsp"].Text = "Удалить"; $stBtns2["WinFsp"].Visible = $true
        } else {
            $stLabels["WinFsp"].Text = "Не найден"; $stLabels["WinFsp"].ForeColor = [System.Drawing.Color]::Red
            $stBtns["WinFsp"].Text = "Установить"; $stBtns["WinFsp"].Visible = $true
            $stBtns2["WinFsp"].Visible = $false
        }

        # S3 Config
        if ($r.HasKeys) {
            $stLabels["Конфиг S3"].Text = "Настроен"; $stLabels["Конфиг S3"].ForeColor = $cOk
            $stBtns["Конфиг S3"].Visible = $false; $stBtns2["Конфиг S3"].Visible = $false
        } else {
            $stLabels["Конфиг S3"].Text = "Не настроен"; $stLabels["Конфиг S3"].ForeColor = $cNo
            $stBtns["Конфиг S3"].Text = "Настроить"; $stBtns["Конфиг S3"].Visible = $true
            $stBtns2["Конфиг S3"].Visible = $false
        }

        # Context menu
        if ($r.HasMenu) {
            $stLabels["Контекстное меню"].Text = "Установлено"; $stLabels["Контекстное меню"].ForeColor = $cOk
            $stBtns["Контекстное меню"].Text = "Переустановить"; $stBtns["Контекстное меню"].Visible = $true
            $stBtns2["Контекстное меню"].Text = "Удалить"; $stBtns2["Контекстное меню"].Visible = $true
        } else {
            $stLabels["Контекстное меню"].Text = "Не установлено"; $stLabels["Контекстное меню"].ForeColor = $cNo
            $stBtns["Контекстное меню"].Text = "Установить"; $stBtns["Контекстное меню"].Visible = $true
            $stBtns2["Контекстное меню"].Visible = $false
        }

        # Disk
        if ($r.Mounted) {
            $stLabels["Диск"].Text = "$($script:Config.DriveLetter) подключен"
            $stLabels["Диск"].ForeColor = $cOk
            $stBtns["Диск"].Text = "Отключить"; $stBtns["Диск"].Visible = $true
            $stBtns2["Диск"].Visible = $false

            if ($r.DiskSpace) {
                $lblDiskInfo.Text = "Занято: $($r.DiskSpace.UsedGB) ГБ  |  Свободно: $($r.DiskSpace.FreeGB) ГБ"
                $lblDiskInfo.ForeColor = $cOk
            } else {
                $lblDiskInfo.Text = "Диск подключен (данные о размере недоступны)"
                $lblDiskInfo.ForeColor = $cGray
            }
			$usage = $r.BucketUsage
            if ($usage) {
                $lblDiskInfo.Text += "`n📦 Бакет VK Cloud: $($usage.TotalGB) ГБ ($($usage.Objects) объектов)"
            }
        } else {
            $stLabels["Диск"].Text = "Не подключен"; $stLabels["Диск"].ForeColor = $cGray
            $stBtns["Диск"].Text = "Подключить"; $stBtns["Диск"].Visible = $true
            $stBtns2["Диск"].Visible = $false
            $lblDiskInfo.Text = "Диск не подключен"
            $lblDiskInfo.ForeColor = $cGray
        }
    }

    $updateStatus = {
        $r = @{
            HasRclone = ($null -ne (Find-Rclone))
            HasWinFsp = [bool](Find-WinFsp)
            HasKeys   = ($null -ne (Get-S3Keys))
            HasMenu   = [bool](Test-ContextMenu)
            Mounted   = [bool](Test-DiskMounted)
            DiskSpace = (Get-DiskSpace)
        }
        & $applyStatus $r
    }

    # ---- ASYNC STATUS REFRESH (non-blocking) ----
    $script:stState = [hashtable]::Synchronized(@{
        Running = $false
        Done    = $false
        Result  = $null
    })
    $script:stRunspace = $null

    $refreshStatusAsync = {
        if ($script:stState.Running) { return }

        $script:stState.Running = $true
        $script:stState.Done    = $false
        $script:stState.Result  = $null

        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $rs = [runspacefactory]::CreateRunspace($iss)
        $rs.ApartmentState = "STA"
        $rs.Open()

        $rs.SessionStateProxy.SetVariable("stState", $script:stState)
        if ($script:LibDir) {
            $rs.SessionStateProxy.SetVariable("libDir", $script:LibDir)
        }

        $ps = [powershell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
            param($stState, $libDir)
            if ($libDir) {
                . (Join-Path $libDir "Core.ps1")
                . (Join-Path $libDir "Setup.ps1")
            }
            try {
                $stState.Result = @{
                    HasRclone = ($null -ne (Find-Rclone))
                    HasWinFsp = [bool](Find-WinFsp)
                    HasKeys   = ($null -ne (Get-S3Keys))
                    HasMenu   = [bool](Test-ContextMenu)
                    Mounted   = [bool](Test-DiskMounted)
                    DiskSpace = (Get-DiskSpace)
					BucketUsage = (Get-BucketUsage)
                }
            } catch {}
            $stState.Done = $true
        }).AddArgument($script:stState).AddArgument($script:LibDir)

        $async = $ps.BeginInvoke()
        $script:stRunspace = @{ PS = $ps; RS = $rs; Async = $async }
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
    $pollTimer.Interval = 500
	
    $script:restoreTimer = New-Object System.Windows.Forms.Timer # Таймер автоматического возврата строки "версия • GitHub • Telegram" через 10 секунд
    $script:restoreTimer.Interval = 10000
	
    $script:restoreTimer.Add_Tick({
        if ($form -and $form.Handle -and [Win32]::GetForegroundWindow() -eq $form.Handle) {
            $lblStatusText.Text = "EndlessDisk v$($script:AppVersion)"
            $lblStatusText.ForeColor = $cGray
        }
        $script:restoreTimer.Stop()
    })

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
				$script:restoreTimer.Start()   # через 10 сек вернётся версия + ссылки (если окно активно)
			}
            Set-ButtonsEnabled $true
            & $refreshStatusAsync
            if ($script:onDoneCallback) {
                $cb = $script:onDoneCallback
                $script:onDoneCallback = $null
                & $cb
            }
        }
        # Async status refresh completion
        if ($script:stState.Done -and $script:stState.Running) {
            if ($script:stRunspace) {
                try { $script:stRunspace.PS.EndInvoke($script:stRunspace.Async) } catch {}
                $script:stRunspace.PS.Dispose()
                $script:stRunspace.RS.Close()
                $script:stRunspace = $null
            }
            $script:stState.Running = $false
            if ($script:stState.Result) {
                & $applyStatus $script:stState.Result
            }
        }
    })

    # ---- BUTTON HANDLERS ----

	# rclone install
	$stBtns["rclone"].Add_Click({
		$item = "rclone"
		
		# 1. Прячем кнопки и старый статус
		$stBtns[$item].Visible = $false
		$stBtns2[$item].Visible = $false
		$stLabels[$item].Visible = $false

		# 2. Показываем надпись процесса ПОВЕРХ места кнопок
		$stActions[$item].Text = "Установка rclone..."
		$stActions[$item].ForeColor = $cAccent
		# Смещаем чуть выше бара, чтобы не перекрывал полоску
		$stActions[$item].Location = New-Object System.Drawing.Point(280, $sy - 15) 
		$stActions[$item].Visible = $true

		# 3. ВКЛЮЧАЕМ БАР В СТРОКЕ
		$stBars[$item].Visible = $true
		
		# 4. ВКЛЮЧАЕМ НИЖНИЙ БАР (синхронно)
		$mainProgressBar.Style = "Marquee"
		$mainProgressBar.Visible = $true

		# Запуск асинхронной задачи
		& $runAsync { 
			Install-RcloneAuto 
		} "Установка..." {
			# КОЛБЭК: когда всё закончилось
			$stBars["rclone"].Visible = $false
			$stActions["rclone"].Visible = $false
			$stLabels["rclone"].Visible = $true
			
			# Вызываем обновление, чтобы кнопки вернулись
			Update-AllStatuses 
		}
	})

    # rclone uninstall
	$stBtns2["rclone"].Add_Click({
		$item = "rclone"
		if (-not (Show-YesNo "EndlessDisk" "Удалить rclone?")) { return }

		# Прячем кнопки и старый статус
		$stBtns[$item].Visible = $false
		$stBtns2[$item].Visible = $false
		$stLabels[$item].Visible = $false

		# Показываем текст и прогресс-бар
		$stActions[$item].Text = "Удаление rclone..."
		$stActions[$item].ForeColor = [System.Drawing.Color]::Firebrick
		$stActions[$item].Visible = $true
		$stBars[$item].Visible = $true # ВКЛЮЧАЕМ ПОЛОСКУ

		& $runAsync { 
			Uninstall-Rclone 
		} "Удаление rclone..." {
			# КОЛБЭК: Прячем полоску и текст по завершении
			$stBars["rclone"].Visible = $false
			$stActions["rclone"].Visible = $false
			$stLabels["rclone"].Visible = $true
		}
	})

    # WinFsp install
	$stBtns["WinFsp"].Add_Click({
		$item = "WinFsp"
		$doIt = Show-YesNo "EndlessDisk — WinFsp" (
			"WinFsp — драйвер файловой системы для монтирования.`n`n" +
			"Будет скачан установщик с GitHub (winfsp/winfsp).`n" +
			"Потребуются права администратора.`n`n" +
			"Продолжить?")
		if (-not $doIt) { return }

		# Визуальный переход
		$stBtns[$item].Visible = $false
		$stBtns2[$item].Visible = $false
		$stLabels[$item].Visible = $false

		$stActions[$item].Text = "Установка WinFsp..."
		$stActions[$item].ForeColor = $cAccent
		$stActions[$item].Visible = $true
		$stBars[$item].Visible = $true # ВКЛЮЧАЕМ ПОЛОСКУ

		& $runAsync { 
			Install-WinFspAuto 
		} "Установка WinFsp..." {
			$stBars["WinFsp"].Visible = $false
			$stActions["WinFsp"].Visible = $false
			$stLabels["WinFsp"].Visible = $true
		}
	})

    # WinFsp uninstall
	$stBtns2["WinFsp"].Add_Click({
		$item = "WinFsp"
		if (-not (Show-YesNo "EndlessDisk" "Удалить WinFsp?`nПотребуются права администратора.")) { return }

		# Визуальный переход
		$stBtns[$item].Visible = $false
		$stBtns2[$item].Visible = $false
		$stLabels[$item].Visible = $false

		$stActions[$item].Text = "Удаление WinFsp..."
		$stActions[$item].ForeColor = [System.Drawing.Color]::Firebrick
		$stActions[$item].Visible = $true
		$stBars[$item].Visible = $true # ВКЛЮЧАЕМ ПОЛОСКУ

		& $runAsync { 
			Uninstall-WinFsp 
		} "Удаление WinFsp..." {
			$stBars["WinFsp"].Visible = $false
			$stActions["WinFsp"].Visible = $false
			$stLabels["WinFsp"].Visible = $true
		}
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
				& $runAsync {
					param($state)
					Do-Unmount
					if ($state) {
						$state.Status = "Диск отключен"
						$state.Percent = 100
					}
				} "Отключение диска..." $null
			}
		} else {
			$stLabels["Диск"].Text = "Подключение..."
			$stLabels["Диск"].ForeColor = $cWarn
			& $runAsync {
				param($state)
				Do-Mount
				Start-Sleep -Seconds 3
				if ($state) {
					$state.Status = "Диск подключен"
					$state.Percent = 100
				}
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
		
		$dispVal  = $tbDisplayed.Text.Trim()
		$dispUnit = $cbUnit.SelectedItem
		if ($dispVal -match '^\d+$' -and [int]$dispVal -ge 1 -and [int]$dispVal -le 1024) {
			$unitLetter = switch ($dispUnit) { "МБ"{"M"}; "ГБ"{"G"}; "ТБ"{"T"}; "ПБ"{"P"} }
			$newCfg["DisplayedSize"] = "$dispVal$unitLetter"
		} else {
			$newCfg["DisplayedSize"] = "1024G"
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

        & $refreshStatusAsync
        $lblStatusText.Text = "Настройки сохранены"
        $lblStatusText.ForeColor = $cOk
    })

    # Mount/Unmount buttons
	$btnMount.Add_Click({
		$stLabels["Диск"].Text = "Подключение..."
		$stLabels["Диск"].ForeColor = $cWarn

		& $runAsync {
			param($state)
			Do-Mount
			Start-Sleep -Seconds 3
			if ($state) {
				$state.Status = "Диск подключен"
				$state.Percent = 100
			}
		} "Подключение диска..." $null
	})
	$btnUnmount.Add_Click({
		if (Show-YesNo "EndlessDisk" "Отключить диск?") {
			$stLabels["Диск"].Text = "Отключение..."
			$stLabels["Диск"].ForeColor = $cWarn
			& $runAsync {
				param($state)
				Do-Unmount
				if ($state) {
					$state.Status = "Диск отключен"
					$state.Percent = 100
				}
			} "Отключение диска..." $null
		}
	})

    # Full uninstall
    $btnUninstall.Add_Click({
        if (-not (Show-YesNo "EndlessDisk — Полное удаление" (
            "Полное удаление программа (временно не работает)`n`n" +
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
	
    # Событие: Главное окно показано
    $form.Add_Shown({
        Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { 
            $_.MainWindowTitle -eq "ED_SPLASH" 
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        $this.Activate()
        $this.Focus()
    })

    # ПРИМЕНЕНИЕ ИКОНКИ К ПАНЕЛИ ЗАДАЧ
    if ($hLargeIcon -ne [IntPtr]::Zero) {
        try {
            # Устанавливаем иконку для объекта формы (заголовок и Alt+Tab)
            $form.Icon = [System.Drawing.Icon]::FromHandle($hLargeIcon)
            
            # Константы WinAPI
            $WM_SETICON = 0x80
            $ICON_SMALL = 0
            $ICON_BIG = 1
            
            # Принудительно отправляем иконки в окно через Handle
            [IconHelper]::SendMessage($form.Handle, $WM_SETICON, $ICON_SMALL, $hSmallIcon)
            [IconHelper]::SendMessage($form.Handle, $WM_SETICON, $ICON_BIG, $hLargeIcon)
        } catch {}
    }

    # ---- Init & Show ----
    & $updateStatus
    $pollTimer.Start()
    
    # Запуск основного интерфейса
    $form.ShowDialog() | Out-Null
		
    # Очистка после закрытия
    $pollTimer.Stop()
    $pollTimer.Dispose()
    if ($script:stRunspace) {
        try { $script:stRunspace.PS.EndInvoke($script:stRunspace.Async) } catch {}
        $script:stRunspace.PS.Dispose()
        $script:stRunspace.RS.Close()
        $script:stRunspace = $null
    }
    $form.Dispose()

}

