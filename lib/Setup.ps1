# ============================================================
# EndlessDisk — Setup: Install, Uninstall, Mount, Autostart
# ============================================================

# --- VBS Launcher ---
function Write-VbsLauncher([string]$VbsPath) {
    $vbs = @"
Dim mode, filePath, cmd, ps1, fso
Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
' Исправлено: VBS и PS1 лежат в одной папке
ps1 = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), fso.GetBaseName(WScript.ScriptFullName) & ".ps1")
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
    $debug = "Debug-Protect-Final: `$state=$($null -ne $state) | `$script:state=$($null -ne $script:state) | `$Global:state=$($null -ne $Global:state) | Line=$($MyInvocation.ScriptLineNumber) | Caller=$($MyInvocation.MyCommand.Name) | PSVersion=$($PSVersionTable.PSVersion) | RunspaceId=$([runspace]::DefaultRunspace.InstanceId) | ThreadId=$([System.Threading.Thread]::CurrentThread.ManagedThreadId)"

    if ($state -and $state -is [hashtable]) { return $state }
    if ($script:state -and $script:state -is [hashtable]) { $state = $script:state; return $state }
    if ($Global:state -and $Global:state -is [hashtable]) { $state = $Global:state; $script:state = $Global:state; return $state }

    throw "CRITICAL: state variable is lost in background task!`nСообщи разработчику.`n$debug"
}


# --- Install Rclone ---
function Install-RcloneAuto {
    param($PassedState)
    if (-not $PassedState) { $PassedState = $script:bgState }
    $state = $PassedState

    # Проверка наличия rclone через прямой поиск файла (замена Find-Rclone)
    $destDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, "rclone")
    $exePath = [System.IO.Path]::Combine($destDir, "rclone.exe")
    if ([System.IO.File]::Exists($exePath)) { 
        $state.Status = "rclone уже установлен"
        $state.Percent = 100
        return $true 
    }

    # Папка проекта для хранения дистрибутива
    $workDir = [System.IO.Path]::Combine($PSScriptRoot, "bin")
    if (-not [System.IO.Directory]::Exists($workDir)) { 
        [System.IO.Directory]::CreateDirectory($workDir) | Out-Null 
    }
    
    $zipPath = [System.IO.Path]::Combine($workDir, "rclone-windows-amd64.zip")
    $zipUrl  = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"

    # --- 1. СКАЧИВАНИЕ (.NET WebClient) ---
    if (-not [System.IO.File]::Exists($zipPath)) {
        $state.Status = "Загрузка rclone..."
        $state.Percent = 10
        $webClient = $null
        try {
            $state.Block = "Источник: downloads.rclone.org"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($zipUrl, $zipPath)
        } catch {
            $state.Error = "Ошибка загрузки rclone: $($_.Exception.Message)"
            return $false
        } finally {
            if ($null -ne $webClient) { $webClient.Dispose() }
        }
    }

    # --- 2. РАСПАКОВКА (.NET ZipFile) ---
    $state.Status = "Распаковка архива..."
    $state.Percent = 40
    $tempExtract = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "rclone_temp_$(Get-Random)")
    
    try {
        if ([System.IO.Directory]::Exists($tempExtract)) { 
            [System.IO.Directory]::Delete($tempExtract, $true) 
        }
        [System.IO.Directory]::CreateDirectory($tempExtract) | Out-Null
        
        $state.Block = "Распаковка в временную папку..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tempExtract)
        
        $state.Block = "Архив успешно извлечен"
    } catch {
        $state.Error = "Ошибка распаковки: $($_.Exception.Message)"
        return $false
    }

    # --- 3. КОПИРОВАНИЕ ФАЙЛОВ ---
    $state.Status = "Установка исполняемых файлов..."
    $state.Percent = 70
    if (-not [System.IO.Directory]::Exists($destDir)) { 
        [System.IO.Directory]::CreateDirectory($destDir) | Out-Null 
    }

    # Ищем вложенную папку rclone-v*-windows-amd64
    $extractedDirs = [System.IO.Directory]::GetDirectories($tempExtract)
    if ($extractedDirs.Length -gt 0) {
        $rcloneSourceDir = $extractedDirs[0]
        $files = [System.IO.Directory]::GetFiles($rcloneSourceDir)
        
        $totalFiles = $files.Count
        $currentFile = 0

        foreach ($filePath in $files) {
            $currentFile++
            $fileName = [System.IO.Path]::GetFileName($filePath)
            $state.Block = "Копирование: $fileName"
            
            $targetPath = [System.IO.Path]::Combine($destDir, $fileName)
            [System.IO.File]::Copy($filePath, $targetPath, $true)
            
            $state.Percent = 70 + [int](($currentFile / $totalFiles) * 20)
            [System.Threading.Thread]::Sleep(800) # Даем пользователю увидеть прогресс
        }
    }

    # Очистка временной папки через .NET
    if ([System.IO.Directory]::Exists($tempExtract)) { 
        [System.IO.Directory]::Delete($tempExtract, $true) 
    }

    $state.Status = "rclone успешно установлен"
    $state.Block  = "Путь: $destDir"
    $state.Percent = 100
    return $true
}

# --- Uninstall Rclone ---
function Uninstall-Rclone {
    param($PassedState)
    if (-not $PassedState) { $PassedState = $script:bgState }
    $state = $PassedState

    # 1. Остановка процессов
    $state.Status = "Завершение процессов rclone..."
    $state.Percent = 10
    $procs = Get-Process rclone -ErrorAction SilentlyContinue
    if ($procs) {
        foreach ($p in $procs) {
            $state.Block = "Остановка PID: $($p.Id)"
            $p | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        [System.Threading.Thread]::Sleep(2000)
    }

    # --- 2. Удаление файлов (Защищенная версия) ---
    $state.Status = "Очистка файлов rclone..."
    $state.Percent = 40
    
    $locations = @(
        [System.IO.Path]::Combine($env:LOCALAPPDATA, "rclone"),
        "C:\rclone"
    )

    foreach ($loc in $locations) {
        if (-not [string]::IsNullOrWhiteSpace($loc) -and [System.IO.Directory]::Exists($loc)) {
            try {
                $state.Block = "Полное удаление: $loc"
                
                # -Recurse удаляет вложенные папки
                # -Force удаляет файлы только для чтения
                # -Confirm:$false ПРЕДОТВРАЩАЕТ запрос подтверждения, который вызвал ошибку
                Remove-Item $loc -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                
                # Если стандартный метод не сработал (папка занята), пробуем через .NET
                if ([System.IO.Directory]::Exists($loc)) {
                    [System.IO.Directory]::Delete($loc, $true)
                }
            } catch {
                $state.Block = "Ошибка доступа к $loc (возможно, файл занят)"
            }
            [System.Threading.Thread]::Sleep(1000)
        }
    }

    $state.Status = "rclone полностью удален"
    $state.Block  = "Система очищена"
    $state.Percent = 100
}

# --- Install WinFsp ---
function Install-WinFspAuto {
    param($PassedState)
    if (-not $PassedState) { $PassedState = $script:bgState }
    $state = $PassedState

    # 1. Проверка установки через реестр
    $regPath = "SOFTWARE\WinFsp"
    $isInstalled = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regPath)
    if ($isInstalled) { 
        $state.Status = "WinFsp уже установлен"
        $state.Percent = 100
        return $true 
    }

    $workDir = [System.IO.Path]::Combine($PSScriptRoot, "bin")
    if (-not [System.IO.Directory]::Exists($workDir)) { [System.IO.Directory]::CreateDirectory($workDir) | Out-Null }
    $msiPath = [System.IO.Path]::Combine($workDir, "winfsp_installer.msi")
    $logPath = [System.IO.Path]::Combine($workDir, "install_log.txt")

    # --- СКАЧИВАНИЕ (Надежный метод через .NET) ---
    if (-not [System.IO.File]::Exists($msiPath)) {
        $state.Status = "Загрузка WinFsp с GitHub..."
        $state.Percent = 10
        $webClient = $null
        try {
            # 1. Получаем данные о релизе (API GitHub)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $apiUrl = "https://github.com"
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            
            $msiAsset = $release.assets | Where-Object { $_.name -like "*.msi" } | Select-Object -First 1
            if (-not $msiAsset) { throw "MSI-файл не найден в релизе GitHub" }
            
            $state.Block = "Файл: $($msiAsset.name) ($([Math]::Round($msiAsset.size / 1MB, 2)) MB)"
            
            # 2. Скачивание через .NET (вместо Invoke-WebRequest)
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($msiAsset.browser_download_url, $msiPath)
            
            $state.Block = "Загрузка завершена успешно"
        } catch {
            $state.Error = "Ошибка загрузки: $($_.Exception.Message)"
            return $false
        } finally {
            if ($null -ne $webClient) { $webClient.Dispose() }
        }
        [System.Threading.Thread]::Sleep(500)
    }


    # --- ГЛУБОКАЯ ЧИСТКА ---
    $state.Status = "Очистка системных блокировок..."
    $state.Block = "Остановка служб и удаление ключей..."
    $state.Percent = 20
    
    & sc.exe stop WinFsp 2>$null | Out-Null
    & sc.exe delete WinFsp 2>$null | Out-Null
    & reg delete "HKLM\SOFTWARE\WinFsp" /f 2>$null | Out-Null
    & reg delete "HKLM\SOFTWARE\WOW6432Node\WinFsp" /f 2>$null | Out-Null
    [System.Threading.Thread]::Sleep(1500)

    # --- ЗАПУСК УСТАНОВКИ ---
    $state.Status = "Запуск инсталлятора WinFsp..."
    $state.Block = "Ожидание подтверждения UAC (если прошло больше 30 секунд, перезапустите программу)"
    $state.Percent = 30
    $msiArgs = "/i `"$msiPath`" /qn /norestart ALLUSERS=1 ADDLOCAL=ALL /L*V `"$logPath`""
    
    try {
        $process = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Verb RunAs -PassThru
    } catch {
        $state.Error = "Установка отменена пользователем"
        return $false
    }

    # --- МОНИТОРИНГ (С ЗАЩИТОЙ ОТ ЗАВИСАНИЯ) ---
    $state.Status = "Установка компонентов..."
    $startTime = Get-Date

    while ($true) {
        # 1. Проверяем, не завершился ли процесс
        if ($process.HasExited) { break }

        # 2. Проверяем, не появился ли реестр (признак успеха)
        $checkReg = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regPath)
        if ($checkReg) { 
            $state.Block = "Реестр WinFsp успешно обновлен"
            [System.Threading.Thread]::Sleep(2000) # Даем MSI дописать хвосты
            break 
        }

        # 3. Тайм-аут 3 минуты
        if (((Get-Date) - $startTime).TotalMinutes -gt 3) { break }

        # 4. Чтение лога
        if ([System.IO.File]::Exists($logPath)) {
            try {
                $fileStream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $reader = New-Object System.IO.StreamReader($fileStream)
                $logContent = $reader.ReadToEnd()
                $reader.Close(); $fileStream.Close()

                $lastAction = $logContent.Split("`n") | Where-Object { $_ -match "Executing op:" } | Select-Object -Last 1
                if ($lastAction) {
                    $detail = ($lastAction -replace ".*Executing op: ", "").Trim()
                    $state.Block = "MSI: $detail"
                    if ($detail -match "FileCopy|FileMove") { $state.Status = "Копирование файлов..." }
                    if ($detail -match "ServiceControl")   { $state.Status = "Настройка служб..." }
                }
            } catch { }
        }
        
        if ($state.Percent -lt 98) { $state.Percent += 1 }
        [System.Threading.Thread]::Sleep(1000)
    }

    # --- ФИНАЛИЗАЦИЯ ---
    $finalReg = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regPath)
    if ($finalReg -or $process.ExitCode -in @(0, 3010)) {
        $state.Status = "WinFsp успешно установлен!"
        $state.Percent = 100
        return $true
    } else {
        $state.Error = "Ошибка (Код: $($process.ExitCode))"
        $state.Block = "Проверьте лог в папке bin"
        return $false
    }
}

# --- Uninstall WinFsp ---
function Uninstall-WinFsp {
    param($PassedState)

    if (-not $PassedState) { $PassedState = $script:bgState }
    $state = $PassedState

    # --- 1. Пути через .NET (замена Join-Path и Test-Path) ---
    $workDir = [System.IO.Path]::Combine($PSScriptRoot, "bin")
    if (-not [System.IO.Directory]::Exists($workDir)) {
        [System.IO.Directory]::CreateDirectory($workDir) | Out-Null
    }
    
    $msiPath = [System.IO.Path]::Combine($workDir, "winfsp_installer.msi")
    $logPath = [System.IO.Path]::Combine($workDir, "uninstall_log.txt")

    # --- 2. Скачивание (если файла нет) ---
    if (-not [System.IO.File]::Exists($msiPath)) {
        $state.Status  = "Загрузка MSI для удаления..."
        $state.Percent = 10
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod "https://github.com" -UseBasicParsing
            $msiAsset = $release.assets | Where-Object { $_.name -like "*.msi" } | Select-Object -First 1
            
            if ($msiAsset) {
                Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $msiPath -UseBasicParsing
            } else { throw "MSI не найден" }
        } catch {
            $state.Error = "Ошибка подготовки MSI: $($_.Exception.Message)"
            return
        }
    }

    # Очистка старого лога через .NET
    if ([System.IO.File]::Exists($logPath)) { [System.IO.File]::Delete($logPath) }
    [System.IO.File]::WriteAllText($logPath, "Starting Uninstall...")

    # --- 3. Запуск MSI (Админ-права) ---
    $state.Status  = "Запуск деинсталляции..."
    $state.Percent = 30
    $msiArgs = "/x `"$msiPath`" /qn /norestart /L*V `"$logPath`""
    
    try {
        $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Verb RunAs -PassThru
    } catch {
        $state.Error = "Ошибка запуска (UAC?): $($_.Exception.Message)"
        return
    }

    # --- 4. Чтение лога в реальном времени через .NET ---
    $state.Status = "Процесс удаления компонентов..."
    while (-not $proc.HasExited) {
        if ([System.IO.File]::Exists($logPath)) {
            try {
                # Читаем все строки лога
                $lines = [System.IO.File]::ReadAllLines($logPath)
                if ($lines.Count -gt 0) {
                    # Ищем последние действия MSI
                    $lastAction = $lines | Where-Object { $_ -match "Executing op:" -or $_ -match "Action start" } | Select-Object -Last 1
                    
                    if ($lastAction) {
                        $cleanLine = $lastAction -replace ".*Executing op: ", "" -replace "Action start \d+: ", ""
                        $state.Block = "MSI: $cleanLine"
                    }
                }
            } catch { } # Игнорируем ошибки доступа к файлу во время записи
        }
        
        if ($state.Percent -lt 95) { $state.Percent += 1 }
        [System.Threading.Thread]::Sleep(500) # Замена Start-Sleep
    }

    # --- 5. Завершение ---
    if ($proc.ExitCode -in @(0, 3010)) {
        $state.Status  = "WinFsp успешно удален"
        $state.Block   = "MSI завершен (код 0)"
        $state.Percent = 100
        if ([System.IO.File]::Exists($logPath)) { [System.IO.File]::Delete($logPath) }
    } else {
        $state.Status  = "Ошибка при удалении"
        $state.Block   = "MSI Exit Code: $($proc.ExitCode)"
        $state.Percent = 100
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

# --- Context menu Install ---
function Install-ContextMenu {
    param($PassedState)

    if (-not $PassedState) { $PassedState = $script:bgState }
    $state = $PassedState

    # --- 1. Подготовка и проверки ---
    $state.Status = "Подготовка контекстного меню..."
    $state.Percent = 5
    
    $keys = Get-S3Keys
    if (-not $keys) { 
        $state.Error = "Ключи S3 не найдены в конфиге rclone!"
        return 
    }

    $state.Block = "Проверка VBS-лаунчера..."
    $vbsPath = Ensure-VbsLauncher
    $dl = $script:DRIVE_LETTER
    [System.Threading.Thread]::Sleep(300)

    # --- 2. Регистрация: Копировать ссылку ---
    $state.Status = "Настройка меню: Копировать ссылку"
    $state.Percent = 20
    
    $k1 = "HKCU:\Software\Classes\*\shell\VKDiskCopyLink"
    
    $state.Block = "Создание раздела: VKDiskCopyLink"
    if (-not (Test-Path $k1)) { New-Item -Path $k1 -Force | Out-Null }
    
    $state.Block = "Установка заголовка: EndlessDisk: Копировать ссылку"
    Set-ItemProperty $k1 "(Default)" "EndlessDisk: Копировать ссылку"
    
    $state.Block = "Настройка иконки и фильтра диска ($dl)"
    Set-ItemProperty $k1 "Icon" "shell32.dll,134"
    Set-ItemProperty $k1 "AppliesTo" ('System.ItemPathDisplay:~<"' + $dl + '\"')
    
    $state.Block = "Регистрация команды запуска WScript"
    $c1 = "$k1\command"
    if (-not (Test-Path $c1)) { New-Item -Path $c1 -Force | Out-Null }
    Set-ItemProperty $c1 "(Default)" ('wscript.exe "' + $vbsPath + '" copylink "%1"')
    
    $state.Percent = 50
    [System.Threading.Thread]::Sleep(400)

    # --- 3. Регистрация: Открыть/Закрыть доступ ---
    $state.Status = "Настройка меню: Управление доступом"
    $state.Percent = 60
    
    $k2 = "HKCU:\Software\Classes\*\shell\VKDiskToggleACL"
    
    $state.Block = "Создание раздела: VKDiskToggleACL"
    if (-not (Test-Path $k2)) { New-Item -Path $k2 -Force | Out-Null }
    
    $state.Block = "Установка заголовка: EndlessDisk: Доступ"
    Set-ItemProperty $k2 "(Default)" "EndlessDisk: Открыть/Закрыть доступ"
    
    $state.Block = "Настройка иконки (Security)"
    Set-ItemProperty $k2 "Icon" "shell32.dll,47"
    Set-ItemProperty $k2 "AppliesTo" ('System.ItemPathDisplay:~<"' + $dl + '\"')
    
    $state.Block = "Привязка скрипта к команде"
    $c2 = "$k2\command"
    if (-not (Test-Path $c2)) { New-Item -Path $c2 -Force | Out-Null }
    Set-ItemProperty $c2 "(Default)" ('wscript.exe "' + $vbsPath + '" toggleacl "%1"')

    # --- 4. Финализация ---
    $state.Status = "Применение настроек проводника..."
    $state.Percent = 90
    $state.Block = "Обновление кэша иконок..."
    [System.Threading.Thread]::Sleep(500)

    $state.Status  = "Контекстное меню успешно установлено"
    $state.Block   = "Меню доступно для диска $dl"
    $state.Percent = 100
}

# --- Context menu Uninstall ---
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
	
	if ($script:Config.DisplayedSize) {
		$mountArgs += "--vfs-disk-space-total-size", $script:Config.DisplayedSize
	}
	
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
    $shortcut.IconLocation = "shell32.dll,149"
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
        $vbs = Join-Path $scriptDir "EndlessDisk.vbs"
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

function Do-FullUninstallRcloneConfig([bool]$DeleteAll) {
	
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
