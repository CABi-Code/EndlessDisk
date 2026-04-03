# ============================================================
# EndlessDisk — Setup: Install, Uninstall, Mount, Autostart
# ============================================================

# --- VBS Launcher ---
function Write-VbsLauncher([string]$VbsPath) {
    $vbs = @"
Dim mode, filePath, cmd, ps1, fso
Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
ps1 = fso.BuildPath(fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName)), fso.GetBaseName(WScript.ScriptFullName) & ".ps1")
mode = "" : filePath = ""
If WScript.Arguments.Count >= 1 Then mode = WScript.Arguments(0)
If WScript.Arguments.Count >= 2 Then filePath = WScript.Arguments(1)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File " & Chr(34) & ps1 & Chr(34) & " " & Chr(34) & mode & Chr(34) & " " & Chr(34) & filePath & Chr(34)
objShell.Run cmd, 0, False
"@
    [System.IO.File]::WriteAllText($VbsPath, $vbs, [System.Text.Encoding]::ASCII)
}


function Get-VbsPath {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return Join-Path $scriptDir "EndlessDisk.vbs"
}

function Ensure-VbsLauncher {
    $vbs = Get-VbsPath
    if (-not (Test-Path $vbs)) { Write-VbsLauncher $vbs }
    return $vbs
}


function Protect-State {
    if (-not $state) {
        $state = $Global:state
        if (-not $state) { $state = $script:state }
        if (-not $state) {
            throw "CRITICAL: state variable is lost in background task!`nСообщи разработчику."
        }
    }
    return $state
}


# --- Install rclone ---
function Install-RcloneAuto {
	
	$state = Protect-State

    $rclone = Find-Rclone
    if ($rclone) { return $rclone }

    $destDir = Join-Path $env:LOCALAPPDATA "rclone"
    $zipUrl  = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $state.Status  = "Скачивание rclone..."
    $state.Detail  = $zipUrl
    $state.Block   = "Setup.ps1 -> Install-RcloneAuto -> Download"
    $state.Percent = 10

    $tempZip = Join-Path $env:TEMP "rclone-install.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

    $state.Status  = "Распаковка rclone..."
    $state.Detail  = "Извлечение файлов"
    $state.Block   = "Setup.ps1 -> Install-RcloneAuto -> Extract"
    $state.Percent = 50

    $tempExtract = Join-Path $env:TEMP "rclone-extract"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

    $rcloneDir = Get-ChildItem $tempExtract -Directory | Select-Object -First 1
    if (-not (Test-Path $destDir)) { New-Item $destDir -ItemType Directory -Force | Out-Null }

    $state.Status  = "Копирование rclone.exe..."
    $state.Detail  = $destDir
    $state.Block   = "Setup.ps1 -> Install-RcloneAuto -> Copy"
    $state.Percent = 80

    Copy-Item (Join-Path $rcloneDir.FullName "rclone.exe") (Join-Path $destDir "rclone.exe") -Force
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    $state.Status  = "rclone установлен"
    $state.Percent = 100
    return (Join-Path $destDir "rclone.exe")
}

# --- Uninstall rclone ---
function Uninstall-Rclone {

	$state = Protect-State

    $state.Status = "Остановка rclone..."
    $state.Block  = "Setup.ps1 -> Uninstall-Rclone -> StopProcess"
    $state.Percent = 10
    Get-Process rclone -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $state.Status = "Удаление rclone..."
    $state.Block  = "Setup.ps1 -> Uninstall-Rclone -> RemoveFiles"
    $state.Percent = 40

    $locations = @(
        (Join-Path $env:LOCALAPPDATA "rclone"),
        "C:\rclone"
    )
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ($scriptDir) {
        $localExe = Join-Path $scriptDir "rclone.exe"
        if (Test-Path $localExe) { Remove-Item $localExe -Force -ErrorAction SilentlyContinue }
    }
    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            Remove-Item $loc -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $state.Status = "rclone удален"
    $state.Percent = 100
}

# --- Install WinFsp ---
function Install-WinFspAuto {
    if (Find-WinFsp) { return $true }

	$state = Protect-State

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $state.Status  = "Поиск последней версии WinFsp..."
    $state.Detail  = "GitHub API"
    $state.Block   = "Setup.ps1 -> Install-WinFspAuto -> GitHubAPI"
    $state.Percent = 10

    $release = Invoke-RestMethod "https://api.github.com/repos/winfsp/winfsp/releases/latest" -UseBasicParsing
    $msiAsset = $release.assets | Where-Object { $_.name -like "*.msi" } | Select-Object -First 1
    if (-not $msiAsset) { throw "MSI не найден в последнем релизе WinFsp" }

    $state.Status  = "Скачивание WinFsp..."
    $state.Detail  = $msiAsset.name
    $state.Block   = "Setup.ps1 -> Install-WinFspAuto -> Download"
    $state.Percent = 30

    $tempMsi = Join-Path $env:TEMP $msiAsset.name
    Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $tempMsi -UseBasicParsing

    $state.Status  = "Установка WinFsp..."
    $state.Detail  = "Требуются права администратора"
    $state.Block   = "Setup.ps1 -> Install-WinFspAuto -> MSI Install"
    $state.Percent = 60

    $proc = Start-Process "msiexec.exe" -ArgumentList "/i `"$tempMsi`" /passive /norestart" `
        -Verb RunAs -Wait -PassThru
    Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) { throw "Установщик WinFsp завершился с кодом $($proc.ExitCode)" }

    $state.Status  = "WinFsp установлен"
    $state.Percent = 100
    return $true
}

# --- Uninstall WinFsp ---
function Uninstall-WinFsp {
    $state = $Global:state
    if (-not $state) { $state = $script:state }

    $productId = Get-WinFspUninstallId

    if (-not $productId) {
        if ($state) {
            $state.Status  = "WinFsp уже удалён или не найден"
            $state.Percent = 100
        }
        return
    }

    if ($state) {
        $state.Status  = "Удаление WinFsp..."
        $state.Detail  = "Требуются права администратора"
        $state.Block   = "Setup.ps1 -> Uninstall-WinFsp -> MSI Uninstall"
        $state.Percent = 30
    }

    try {
        $proc = Start-Process "msiexec.exe" -ArgumentList "/x $productId /passive /norestart" `
            -Verb RunAs -PassThru -ErrorAction Stop

        if ($proc -and -not $proc.HasExited) {
            $proc.WaitForExit(120000)
        }

        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            throw "msiexec завершился с кодом $($proc.ExitCode)"
        }

        if ($state) {
            $state.Status  = "Проверка удаления WinFsp..."
            $state.Percent = 70
        }

        $waited = 0
        while ((Find-WinFsp) -and $waited -lt 10) {
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Find-WinFsp) {
            if ($proc.ExitCode -eq 3010) {
                if ($state) {
                    $state.Status  = "WinFsp: требуется перезагрузка"
                    $state.Percent = 100
                }
            } else {
                throw "WinFsp не был полностью удалён. Попробуйте перезагрузить компьютер."
            }
        } else {
            if ($state) {
                $state.Status  = "WinFsp успешно удалён"
                $state.Percent = 100
            }
        }
    }
    catch {
        if ($state) {
            $state.Error = "Не удалось удалить WinFsp: $($_.Exception.Message)"
        }
        throw
    }
}

# --- Save rclone config ---
function Save-RcloneConfig([string]$AccessKey, [string]$SecretKey) {
    $rclone = Find-Rclone
    $cfgPath = "$env:APPDATA\rclone\rclone.conf"
    if ($rclone) {
        try {
            $p = (& $rclone config file 2>$null |
                Select-String -Pattern '[\\/]' | Select-Object -First 1).ToString().Trim()
            if ($p) { $cfgPath = $p }
        } catch {}
    }

    $cfgDir = Split-Path -Parent $cfgPath
    if (-not (Test-Path $cfgDir)) { New-Item $cfgDir -ItemType Directory -Force | Out-Null }

    $remoteName = $script:Config.RcloneRemote
    $newSection = @(
        "[$remoteName]",
        "type = s3",
        "provider = Other",
        "access_key_id = $AccessKey",
        "secret_access_key = $SecretKey",
        "endpoint = $($script:Config.EndpointHost)",
        "acl = private"
    )

    if (Test-Path $cfgPath) {
        $lines = Get-Content $cfgPath -Encoding UTF8
        $result = @()
        $inSection = $false
        foreach ($line in $lines) {
            if ($line.Trim() -eq "[$remoteName]") { $inSection = $true; continue }
            if ($inSection -and $line.Trim() -match '^\[') { $inSection = $false }
            if (-not $inSection) { $result += $line }
        }
        while ($result.Count -gt 0 -and $result[-1].Trim() -eq "") {
            $result = $result[0..($result.Count - 2)]
        }
        $result += ""
        $result += $newSection
        $result | Out-File $cfgPath -Encoding UTF8
    } else {
        $newSection | Out-File $cfgPath -Encoding UTF8
    }
    $script:cachedKeys = $null
}

# --- Remove rclone config section ---
function Remove-RcloneSection {
    $remoteName = $script:Config.RcloneRemote
    $cfgPaths = @(
        "$env:APPDATA\rclone\rclone.conf",
        "$env:USERPROFILE\.config\rclone\rclone.conf",
        "$env:LOCALAPPDATA\rclone\rclone.conf"
    )
    foreach ($cf in $cfgPaths) {
        if (-not (Test-Path $cf)) { continue }
        $lines = Get-Content $cf -Encoding UTF8
        $result = @()
        $inSection = $false
        foreach ($line in $lines) {
            if ($line.Trim() -eq "[$remoteName]") { $inSection = $true; continue }
            if ($inSection -and $line.Trim() -match '^\[') { $inSection = $false }
            if (-not $inSection) { $result += $line }
        }
        while ($result.Count -gt 0 -and $result[-1].Trim() -eq "") {
            $result = $result[0..($result.Count - 2)]
        }
        if ($result.Count -gt 0) { $result | Out-File $cf -Encoding UTF8 }
        else { Remove-Item $cf -Force -ErrorAction SilentlyContinue }
    }
}

# --- Context menu ---
function Install-ContextMenu {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { throw "Запустите из .ps1 файла." }
    $keys = Get-S3Keys
    if (-not $keys) { throw "Ключи S3 не найдены в конфиге rclone!" }

	$state = Protect-State

    $vbsPath = Ensure-VbsLauncher
    $dl = $script:DRIVE_LETTER

    $state.Status  = "Регистрация: Копировать ссылку..."
    $state.Block   = "Setup.ps1 -> Install-ContextMenu -> CopyLink"
    $state.Percent = 30

    $k1 = "HKCU:\Software\Classes\*\shell\VKDiskCopyLink"
    New-Item -Path $k1 -Force | Out-Null
    Set-ItemProperty $k1 "(Default)" "EndlessDisk: Копировать ссылку"
    Set-ItemProperty $k1 "Icon" "shell32.dll,134"
    Set-ItemProperty $k1 "AppliesTo" ('System.ItemPathDisplay:~<"' + $dl + '\"')
    New-Item -Path "$k1\command" -Force | Out-Null
    Set-ItemProperty "$k1\command" "(Default)" ('wscript.exe "' + $vbsPath + '" copylink "%1"')

    $state.Status  = "Регистрация: Открыть/Закрыть доступ..."
    $state.Block   = "Setup.ps1 -> Install-ContextMenu -> ToggleACL"
    $state.Percent = 70

    $k2 = "HKCU:\Software\Classes\*\shell\VKDiskToggleACL"
    New-Item -Path $k2 -Force | Out-Null
    Set-ItemProperty $k2 "(Default)" "EndlessDisk: Открыть/Закрыть доступ"
    Set-ItemProperty $k2 "Icon" "shell32.dll,47"
    Set-ItemProperty $k2 "AppliesTo" ('System.ItemPathDisplay:~<"' + $dl + '\"')
    New-Item -Path "$k2\command" -Force | Out-Null
    Set-ItemProperty "$k2\command" "(Default)" ('wscript.exe "' + $vbsPath + '" toggleacl "%1"')

    $state.Status  = "Контекстное меню установлено"
    $state.Percent = 100
}

function Uninstall-ContextMenu {
	
	$state = Protect-State
	
    $state.Status  = "Удаление контекстного меню..."
    $state.Block   = "Setup.ps1 -> Uninstall-ContextMenu"
    $state.Percent = 30
    Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskCopyLink" -Recurse -Force -ErrorAction SilentlyContinue
    $state.Percent = 60
    Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskToggleACL" -Recurse -Force -ErrorAction SilentlyContinue
    $state.Status  = "Контекстное меню удалено"
    $state.Percent = 100
}

function Test-ContextMenu {
    return (Test-Path "HKCU:\Software\Classes\*\shell\VKDiskCopyLink")
}

# --- Mount / Unmount ---
function Do-Mount {
    $rclone = Find-Rclone
    if (-not $rclone) { throw "rclone не найден!" }

    $remote = $script:Config.RcloneRemote
    $bucket = $script:Config.Bucket
    $letter = $script:Config.DriveLetter
    $cache  = $script:Config.CacheSize
    $xfers  = $script:Config.Transfers

    if (Test-Path $letter) { return }

    $mountArgs = @(
        "mount", "${remote}:${bucket}", $letter,
        "--vfs-cache-mode", "full",
        "--vfs-cache-max-size", $cache,
        "--vfs-read-chunk-size", "64M",
        "--buffer-size", "128M",
        "--transfers", "$xfers",
        "--no-console", "--links"
    )
    Log "Mount: $rclone $($mountArgs -join ' ')"
    Start-Process -FilePath $rclone -ArgumentList $mountArgs -WindowStyle Hidden
}

function Do-Unmount {
    $letter = $script:Config.DriveLetter
    # Kill ALL rclone processes
    Get-Process rclone -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    # Try explicit unmount if still alive
    $rclone = Find-Rclone
    if ($rclone -and (Test-Path $letter)) {
        try { Start-Process $rclone -ArgumentList "mount","--unmount",$letter -Wait -NoNewWindow -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Seconds 1
    }
}

function Test-DiskMounted {
    return (Test-Path $script:Config.DriveLetter)
}

function Get-DiskSpace {
    $letter = $script:Config.DriveLetter
    if (-not (Test-Path $letter)) { return $null }
    $driveName = $letter.TrimEnd(':')
    try {
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        return @{
            UsedGB = [Math]::Round($drive.Used / 1GB, 2)
            FreeGB = [Math]::Round($drive.Free / 1GB, 2)
        }
    } catch { return $null }
}

# --- Autostart ---
$script:AutostartRegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:AutostartName   = "EndlessDisk"

function Test-Autostart {
    $val = Get-ItemProperty $script:AutostartRegKey -Name $script:AutostartName -ErrorAction SilentlyContinue
    return ($null -ne $val.$($script:AutostartName))
}

function Add-Autostart {
    $vbs = Ensure-VbsLauncher
    Set-ItemProperty $script:AutostartRegKey -Name $script:AutostartName -Value "wscript.exe `"$vbs`" mount"
}

function Remove-Autostart {
    Remove-ItemProperty $script:AutostartRegKey -Name $script:AutostartName -ErrorAction SilentlyContinue
}

# --- Desktop shortcut ---
function Get-ShortcutPath {
    return Join-Path ([Environment]::GetFolderPath("Desktop")) "EndlessDisk.lnk"
}

function Test-DesktopShortcut { return (Test-Path (Get-ShortcutPath)) }

function Add-DesktopShortcut {
    $vbs = Ensure-VbsLauncher
    $lnk = Get-ShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnk)
    $shortcut.TargetPath = "wscript.exe"
    $shortcut.Arguments = "`"$vbs`" gui"
    $shortcut.WorkingDirectory = Split-Path -Parent $PSCommandPath
    $shortcut.IconLocation = "shell32.dll,134"
    $shortcut.Description = "EndlessDisk — VK Cloud S3 Manager"
    $shortcut.Save()
}

function Remove-DesktopShortcut {
    $lnk = Get-ShortcutPath
    if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
}

# --- CopyLink / ToggleAcl (context menu actions) ---
function Do-CopyLink([string]$Path) {
    if (-not $Path -or -not $Path.StartsWith($script:DRIVE_LETTER, [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-Msg "EndlessDisk" "Файл не на диске $($script:DRIVE_LETTER)" "Error"; return
    }
    $fileName  = [System.IO.Path]::GetFileName($Path)
    $objectKey = Get-ObjectKey $Path

    try {
        $checkResult = Invoke-WithProgress -Title "EndlessDisk — Проверка" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Проверка доступа..."; Detail=$fileName; Block="S3 -> Test-IsPublic"; Percent=50 }
            $syncHash.Result = @{ IsPublic = (Test-IsPublic $objectKey) }
            & $report @{ Status="Готово"; Percent=100 }
            Start-Sleep -Milliseconds 200
        }

        if (-not $checkResult.IsPublic) {
            if (-not (Show-YesNo "EndlessDisk" "Файл '$fileName' ПРИВАТНЫЙ.`n`nСделать публичным и скопировать ссылку?")) { return }
            Invoke-WithProgress -Title "EndlessDisk — Открытие доступа" -WorkScript {
                $report = $syncHash.Report
                & $report @{ Status="Получение Owner ID..."; Detail=$fileName; Block="S3 -> Get-OwnerCanonicalId"; Percent=25 }
                $ownerId = Get-OwnerCanonicalId $objectKey
                & $report @{ Status="Установка public-read..."; Block="S3 -> Set-ObjectAcl"; Percent=60 }
                Set-ObjectAcl $objectKey "public-read" $ownerId
                & $report @{ Status="Применение..."; Percent=85 }
                Start-Sleep -Seconds 1
                & $report @{ Status="Готово!"; Percent=100 }
                Start-Sleep -Milliseconds 300
            }
        }
        $link = Get-PublicUrl $objectKey
        [System.Windows.Forms.Clipboard]::SetText($link)
        $msg = if (-not $checkResult.IsPublic) { "Файл сделан публичным.`nСсылка скопирована:`n`n$link" }
               else { "Ссылка скопирована:`n`n$link" }
        Show-Msg "EndlessDisk" $msg
    }
    catch {
        Log "ОШИБКА CopyLink: $($_.Exception.Message)"
        Show-Msg "EndlessDisk — Ошибка" $_.Exception.Message "Error"
    }
}

function Do-ToggleAcl([string]$Path) {
    if (-not $Path -or -not $Path.StartsWith($script:DRIVE_LETTER, [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-Msg "EndlessDisk" "Файл не на диске $($script:DRIVE_LETTER)" "Error"; return
    }
    $fileName  = [System.IO.Path]::GetFileName($Path)
    $objectKey = Get-ObjectKey $Path

    try {
        $info = Invoke-WithProgress -Title "EndlessDisk — Проверка" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Проверка доступа..."; Detail=$fileName; Block="S3 -> Test-IsPublic"; Percent=30 }
            $pub = Test-IsPublic $objectKey
            & $report @{ Status="Получение Owner ID..."; Block="S3 -> Get-OwnerCanonicalId"; Percent=65 }
            $oid = Get-OwnerCanonicalId $objectKey
            $syncHash.Result = @{ IsPublic=$pub; OwnerId=$oid }
            & $report @{ Status="Готово"; Percent=100 }
            Start-Sleep -Milliseconds 200
        }

        if ($info.IsPublic) {
            if (-not (Show-YesNo "EndlessDisk" "Файл '$fileName' сейчас ПУБЛИЧНЫЙ.`n`nСделать приватным?")) { return }
            Invoke-WithProgress -Title "EndlessDisk — Закрытие доступа" -WorkScript {
                $report = $syncHash.Report
                & $report @{ Status="Установка private..."; Detail=$fileName; Block="S3 -> Set-ObjectAcl"; Percent=50 }
                Set-ObjectAcl $objectKey "private" ($info.OwnerId)
                & $report @{ Status="Готово!"; Percent=100 }
                Start-Sleep -Milliseconds 300
            }
            Show-Msg "EndlessDisk" "Файл '$fileName' теперь ПРИВАТНЫЙ." "Warning"
        }
        else {
            if (-not (Show-YesNo "EndlessDisk" "Файл '$fileName' сейчас ПРИВАТНЫЙ.`n`nСделать публичным?")) { return }
            Invoke-WithProgress -Title "EndlessDisk — Открытие доступа" -WorkScript {
                $report = $syncHash.Report
                & $report @{ Status="Установка public-read..."; Detail=$fileName; Block="S3 -> Set-ObjectAcl"; Percent=40 }
                Set-ObjectAcl $objectKey "public-read" ($info.OwnerId)
                & $report @{ Status="Применение..."; Percent=80 }
                Start-Sleep -Seconds 1
                & $report @{ Status="Готово!"; Percent=100 }
                Start-Sleep -Milliseconds 300
            }
            $link = Get-PublicUrl $objectKey
            [System.Windows.Forms.Clipboard]::SetText($link)
            Show-Msg "EndlessDisk" "Файл '$fileName' теперь ПУБЛИЧНЫЙ.`nСсылка скопирована:`n`n$link"
        }
    }
    catch {
        Log "ОШИБКА ToggleAcl: $($_.Exception.Message)"
        Show-Msg "EndlessDisk — Ошибка" $_.Exception.Message "Error"
    }
}

# --- Full uninstall (runs inside background task) ---
function Do-FullUninstallWork {
	
	$state = Protect-State
	
    $state.Status  = "Отключение диска..."
    $state.Block   = "Setup.ps1 -> Do-FullUninstallWork -> Unmount"
    $state.Percent = 5
    Do-Unmount

    $state.Status  = "Удаление контекстного меню..."
    $state.Block   = "Setup.ps1 -> Do-FullUninstallWork -> ContextMenu"
    $state.Percent = 15
    Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskCopyLink" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskToggleACL" -Recurse -Force -ErrorAction SilentlyContinue

    $state.Status  = "Удаление автозапуска..."
    $state.Block   = "Setup.ps1 -> Do-FullUninstallWork -> Autostart"
    $state.Percent = 25
    Remove-Autostart

    $state.Status  = "Удаление ярлыка..."
    $state.Block   = "Setup.ps1 -> Do-FullUninstallWork -> Shortcut"
    $state.Percent = 30
    Remove-DesktopShortcut

    $state.Status  = "Удаление VBS-лаунчера..."
    $state.Block   = "Setup.ps1 -> Do-FullUninstallWork -> VBS"
    $state.Percent = 35
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ($scriptDir) {
        $vbs = Join-Path $scriptDir "VKDiskMenu.vbs"
        if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue }
    }

    $state.Status  = "Удаление конфигурации EndlessDisk..."
    $state.Block   = "Setup.ps1 -> Do-FullUninstallWork -> AppConfig"
    $state.Percent = 40
    if (Test-Path $script:ConfigDir) {
        Remove-Item $script:ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $state.Result = @{ Phase = "config_question" }
}

function Do-FullUninstallRcloneConfig($DeleteAll) {
	
	$state = Protect-State
	
    if ($DeleteAll) {
        $state.Status  = "Удаление конфигурации rclone..."
        $state.Block   = "Setup.ps1 -> Uninstall -> RcloneConfigAll"
        $state.Percent = 50
        foreach ($p in @("$env:APPDATA\rclone", "$env:USERPROFILE\.config\rclone")) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $state.Status  = "Удаление секции remote из конфига..."
        $state.Block   = "Setup.ps1 -> Uninstall -> RcloneSectionOnly"
        $state.Percent = 50
        Remove-RcloneSection
    }
}

function Do-FullUninstallRcloneExe {
	
	$state = Protect-State
	
    $state.Status  = "Удаление rclone..."
    $state.Block   = "Setup.ps1 -> Uninstall -> RcloneExe"
    $state.Percent = 65
    Uninstall-Rclone
}

function Do-FullUninstallWinFsp {
	
	$state = Protect-State
	
    $state.Status  = "Удаление WinFsp..."
    $state.Block   = "Setup.ps1 -> Uninstall -> WinFsp"
    $state.Percent = 80
    Uninstall-WinFsp
}
