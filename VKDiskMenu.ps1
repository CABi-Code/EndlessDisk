<#
.SYNOPSIS
    EndlessDisk — VK Cloud S3 Manager для Windows
    v8.0: GUI-менеджер с автоустановкой, настройками, автозапуском
#>

param(
    [string]$Mode,
    [string]$FilePath
)

if (-not $Mode -and $args.Count -ge 1) { $Mode = $args[0] }
if (-not $FilePath -and $args.Count -ge 2) {
    $FilePath = ($args[1..($args.Count - 1)]) -join " "
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# ============================================================
# КОНФИГУРАЦИЯ (JSON в %APPDATA%\EndlessDisk\)
# ============================================================
$script:AppName    = "EndlessDisk"
$script:AppVersion = "8.0"
$script:ConfigDir  = Join-Path $env:APPDATA $script:AppName
$script:ConfigFile = Join-Path $script:ConfigDir "config.json"

$script:DefaultConfig = @{
    Domain       = "storage.cabi.world"
    Bucket       = "vk-disk"
    DriveLetter  = "V:"
    RcloneRemote = "VKDisk"
    EndpointHost = "hb.bizmrg.com"
    Region       = "ru-msk"
    CacheSize    = "20G"
    Transfers    = 16
}

function Load-Config {
    if (Test-Path $script:ConfigFile) {
        try {
            $json = Get-Content $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg = @{}
            foreach ($key in $script:DefaultConfig.Keys) {
                if ($json.PSObject.Properties[$key]) { $cfg[$key] = $json.$key }
                else { $cfg[$key] = $script:DefaultConfig[$key] }
            }
            return $cfg
        } catch {}
    }
    return $script:DefaultConfig.Clone()
}

function Save-Config([hashtable]$Cfg) {
    if (-not (Test-Path $script:ConfigDir)) {
        New-Item -Path $script:ConfigDir -ItemType Directory -Force | Out-Null
    }
    $Cfg | ConvertTo-Json -Depth 5 | Out-File -FilePath $script:ConfigFile -Encoding UTF8 -Force
}

$script:Config = Load-Config

# Глобальные переменные из конфига
$DOMAIN        = $script:Config.Domain
$BUCKET        = $script:Config.Bucket
$DRIVE_LETTER  = $script:Config.DriveLetter
$RCLONE_REMOTE = $script:Config.RcloneRemote
$ENDPOINT_HOST = $script:Config.EndpointHost
$REGION        = $script:Config.Region

# ============================================================
# ЛОГ
# ============================================================
$script:LogFile = Join-Path $env:TEMP "EndlessDisk.log"
function Log {
    param([string]$Text)
    try { "[$(Get-Date -Format 'HH:mm:ss.fff')] $Text" |
          Out-File -Append -FilePath $script:LogFile -Encoding UTF8 } catch {}
}

# ============================================================
# GUI bootstrap
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Msg {
    param([string]$Title, [string]$Text, [string]$Icon = "Information")
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, "OK", $Icon) | Out-Null
}
function Show-YesNo {
    param([string]$Title, [string]$Text)
    return ([System.Windows.Forms.MessageBox]::Show($Text, $Title, "YesNo", "Question") -eq "Yes")
}

# ============================================================
# ПРОГРЕСС-ОКНО + фоновый Runspace
# ============================================================
function Invoke-WithProgress {
    param(
        [string]$Title = "EndlessDisk",
        [scriptblock]$WorkScript
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(440, 210)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::White
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
            [System.IO.Path]::Combine($env:SystemRoot, "System32", "shell32.dll"))
    } catch {}

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(20, 18)
    $lblStatus.Size = New-Object System.Drawing.Size(390, 26)
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblStatus.Text = "Подготовка..."
    $form.Controls.Add($lblStatus)

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.Location = New-Object System.Drawing.Point(20, 48)
    $lblDetail.Size = New-Object System.Drawing.Size(390, 20)
    $lblDetail.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblDetail.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $form.Controls.Add($lblDetail)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(20, 78)
    $bar.Size = New-Object System.Drawing.Size(390, 26)
    $bar.Style = "Marquee"
    $bar.MarqueeAnimationSpeed = 30
    $form.Controls.Add($bar)

    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Location = New-Object System.Drawing.Point(20, 114)
    $lblTime.Size = New-Object System.Drawing.Size(390, 18)
    $lblTime.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblTime.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $lblTime.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $form.Controls.Add($lblTime)

    $lblFooter = New-Object System.Windows.Forms.Label
    $lblFooter.Location = New-Object System.Drawing.Point(20, 140)
    $lblFooter.Size = New-Object System.Drawing.Size(390, 18)
    $lblFooter.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblFooter.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $lblFooter.Text = "EndlessDisk v$($script:AppVersion)"
    $form.Controls.Add($lblFooter)

    $syncHash = [hashtable]::Synchronized(@{
        Result   = $null
        Error    = $null
        Done     = $false
        Updates  = [System.Collections.ArrayList]::new()
    })
    $syncHash.Report = {
        param($Info)
        [void]$syncHash.Updates.Add($Info)
    }.GetNewClosure()

    $startTime = [datetime]::Now
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200
    $timer.Add_Tick({
        $sec = ([datetime]::Now - $startTime).TotalSeconds
        $lblTime.Text = "Прошло: $([Math]::Round($sec, 1)) сек"
    })

    $uiTimer = New-Object System.Windows.Forms.Timer
    $uiTimer.Interval = 80
    $uiTimer.Add_Tick({
        while ($syncHash.Updates.Count -gt 0) {
            $info = $syncHash.Updates[0]
            $syncHash.Updates.RemoveAt(0)
            if ($info.Status) { $lblStatus.Text = $info.Status }
            if ($info.Detail -ne $null) { $lblDetail.Text = $info.Detail }
            if ($info.Percent -ne $null -and $info.Percent -ge 0) {
                $bar.Style = "Continuous"
                $bar.Value = [Math]::Min([int]$info.Percent, 100)
            }
        }
        if ($syncHash.Done) {
            $uiTimer.Stop()
            $timer.Stop()
            $form.Close()
        }
    })

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("syncHash", $syncHash)
    $runspace.SessionStateProxy.SetVariable("workScript", $WorkScript)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        try   { & $workScript }
        catch { $syncHash.Error = $_.Exception.Message }
        finally { $syncHash.Done = $true }
    })
    $asyncResult = $ps.BeginInvoke()

    $timer.Start()
    $uiTimer.Start()
    $form.ShowDialog() | Out-Null

    $timer.Dispose()
    $uiTimer.Dispose()
    try { $ps.EndInvoke($asyncResult) } catch {}
    $ps.Dispose()
    $runspace.Close()
    $form.Dispose()

    if ($syncHash.Error) { throw $syncHash.Error }
    return $syncHash.Result
}

# ============================================================
# ПОИСК КОМПОНЕНТОВ
# ============================================================
function Find-Rclone {
    $scriptDir = Split-Path -Parent $PSCommandPath
    foreach ($c in @(
        (Join-Path $scriptDir "rclone.exe"),
        "C:\rclone\rclone.exe",
        "$env:LOCALAPPDATA\rclone\rclone.exe",
        (Join-Path $script:ConfigDir "rclone\rclone.exe")
    )) {
        if (Test-Path $c) { return $c }
    }
    $p = Get-Command "rclone.exe" -ErrorAction SilentlyContinue
    if ($p) { return $p.Source }
    return $null
}

function Find-WinFsp {
    $paths = @(
        "${env:ProgramFiles}\WinFsp\bin\winfsp-x64.dll",
        "${env:ProgramFiles(x86)}\WinFsp\bin\winfsp-x64.dll"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\WinFsp" -ErrorAction SilentlyContinue
    if ($reg -and $reg.InstallDir -and (Test-Path $reg.InstallDir)) { return $true }
    return $false
}

# ============================================================
# КЛЮЧИ S3
# ============================================================
$script:cachedKeys = $null
function Get-S3Keys {
    if ($script:cachedKeys) { return $script:cachedKeys }

    $configPaths = @(
        "$env:APPDATA\rclone\rclone.conf",
        "$env:USERPROFILE\.config\rclone\rclone.conf",
        "$env:LOCALAPPDATA\rclone\rclone.conf"
    )
    $rclone = Find-Rclone
    if ($rclone) {
        try {
            $cfgPath = (& $rclone config file 2>$null |
                Select-String -Pattern '[\\/]' | Select-Object -First 1).ToString().Trim()
            if ($cfgPath -and (Test-Path $cfgPath)) {
                $configPaths = @($cfgPath) + $configPaths
            }
        } catch {}
    }

    foreach ($cfgFile in $configPaths) {
        if (-not (Test-Path $cfgFile)) { continue }
        $lines = Get-Content $cfgFile -Encoding UTF8
        $inSection = $false; $ak = ""; $sk = ""
        foreach ($line in $lines) {
            $l = $line.Trim()
            if ($l -eq "[$RCLONE_REMOTE]") { $inSection = $true; continue }
            if ($l -match '^\[' -and $inSection) { break }
            if (-not $inSection) { continue }
            if ($l -match '^access_key_id\s*=\s*(.+)$')     { $ak = $Matches[1].Trim() }
            if ($l -match '^secret_access_key\s*=\s*(.+)$') { $sk = $Matches[1].Trim() }
        }
        if ($ak -and $sk) {
            $script:cachedKeys = @{ AccessKey = $ak; SecretKey = $sk }
            return $script:cachedKeys
        }
    }

    if ($rclone) {
        $output = & $rclone config show $RCLONE_REMOTE 2>&1 | Out-String
        $ak = ""; $sk = ""
        foreach ($line in ($output -split "`n")) {
            $l = $line.Trim()
            if ($l -match '^access_key_id\s*=\s*(.+)$')     { $ak = $Matches[1].Trim() }
            if ($l -match '^secret_access_key\s*=\s*(.+)$') { $sk = $Matches[1].Trim() }
        }
        if ($ak -and $sk) {
            $script:cachedKeys = @{ AccessKey = $ak; SecretKey = $sk }
            return $script:cachedKeys
        }
    }
    return $null
}

# ============================================================
# УТИЛИТЫ
# ============================================================
function Get-ObjectKey([string]$FullPath) {
    $rel = $FullPath.Substring($DRIVE_LETTER.Length).TrimStart("\", "/")
    return ($rel -replace '\\', '/')
}
function Get-PublicUrl([string]$ObjectKey) {
    $enc = ($ObjectKey -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    return "https://$DOMAIN/$enc"
}

# ============================================================
# CRYPTO
# ============================================================
function HmacSha256Bytes([byte[]]$Key, [string]$Data) {
    $h = New-Object System.Security.Cryptography.HMACSHA256; $h.Key = $Key
    return $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Data))
}
function Sha256Hex([string]$Data) {
    $b = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($Data))
    return ([BitConverter]::ToString($b) -replace '-','').ToLower()
}
function Sha256HexBytes([byte[]]$Data) {
    $b = [System.Security.Cryptography.SHA256]::Create().ComputeHash($Data)
    return ([BitConverter]::ToString($b) -replace '-','').ToLower()
}

# ============================================================
# S3 ОПЕРАЦИИ
# ============================================================
function Test-IsPublic([string]$ObjectKey) {
    try {
        $null = Invoke-WebRequest -Uri (Get-PublicUrl $ObjectKey) -Method HEAD `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        return $true
    } catch { return $false }
}

function New-S3Signature {
    param([string]$Method, [string]$CanonicalUri, [string]$QueryString,
          [hashtable]$Headers, [string]$PayloadHash,
          [string]$DateStamp, [string]$AmzDate)
    $keys = Get-S3Keys
    if (-not $keys) { throw "Ключи S3 не найдены." }
    $sorted = ($Headers.Keys | Sort-Object)
    $cHdrs  = ($sorted | ForEach-Object { "$($_):$($Headers[$_])" }) -join "`n"
    $sHdrs  = $sorted -join ";"
    $cr     = "$Method`n$CanonicalUri`n$QueryString`n$cHdrs`n`n$sHdrs`n$PayloadHash"
    $crHash = Sha256Hex $cr
    $scope  = "$DateStamp/$REGION/s3/aws4_request"
    $sts    = "AWS4-HMAC-SHA256`n$AmzDate`n$scope`n$crHash"
    $kD = HmacSha256Bytes ([System.Text.Encoding]::UTF8.GetBytes("AWS4$($keys.SecretKey)")) $DateStamp
    $kR = HmacSha256Bytes $kD $REGION
    $kS = HmacSha256Bytes $kR "s3"
    $kF = HmacSha256Bytes $kS "aws4_request"
    $sig = ([BitConverter]::ToString((HmacSha256Bytes $kF $sts)) -replace '-','').ToLower()
    return "AWS4-HMAC-SHA256 Credential=$($keys.AccessKey)/$scope, SignedHeaders=$sHdrs, Signature=$sig"
}

function Get-OwnerCanonicalId([string]$ObjectKey) {
    $now = [datetime]::UtcNow
    $ds  = $now.ToString("yyyyMMdd"); $ad = $now.ToString("yyyyMMddTHHmmssZ")
    $ek  = ($ObjectKey -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $cu  = "/$BUCKET/$ek"; $ph = Sha256Hex ""
    $h   = @{ "host"=$ENDPOINT_HOST; "x-amz-content-sha256"=$ph; "x-amz-date"=$ad }
    $auth = New-S3Signature "GET" $cu "acl=" $h $ph $ds $ad
    $r = Invoke-WebRequest -Uri "https://$ENDPOINT_HOST$cu`?acl" -Method GET `
        -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop -Headers @{
            "Authorization"=$auth; "x-amz-date"=$ad; "x-amz-content-sha256"=$ph }
    return ([xml]$r.Content).AccessControlPolicy.Owner.ID
}

function Set-ObjectAcl([string]$ObjectKey, [string]$Acl, [string]$OwnerId) {
    $allUsersGrant = ""
    if ($Acl -eq "public-read") {
        $allUsersGrant = @"

    <Grant>
      <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Group">
        <URI>http://acs.amazonaws.com/groups/global/AllUsers</URI>
      </Grantee>
      <Permission>READ</Permission>
    </Grant>
"@
    }
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<AccessControlPolicy>
  <Owner><ID>$OwnerId</ID></Owner>
  <AccessControlList>
    <Grant>
      <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="CanonicalUser">
        <ID>$OwnerId</ID>
      </Grantee>
      <Permission>FULL_CONTROL</Permission>
    </Grant>$allUsersGrant
  </AccessControlList>
</AccessControlPolicy>
"@
    $body = [System.Text.Encoding]::UTF8.GetBytes($xml)
    $now  = [datetime]::UtcNow
    $ds   = $now.ToString("yyyyMMdd"); $ad = $now.ToString("yyyyMMddTHHmmssZ")
    $ek   = ($ObjectKey -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $cu   = "/$BUCKET/$ek"
    $md5  = [Convert]::ToBase64String([System.Security.Cryptography.MD5]::Create().ComputeHash($body))
    $ph   = Sha256HexBytes $body
    $h    = @{
        "content-md5"=$md5; "content-type"="application/xml"
        "host"=$ENDPOINT_HOST; "x-amz-content-sha256"=$ph; "x-amz-date"=$ad
    }
    $auth = New-S3Signature "PUT" $cu "acl=" $h $ph $ds $ad
    $null = Invoke-WebRequest -Uri "https://$ENDPOINT_HOST$cu`?acl" -Method PUT `
        -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop `
        -ContentType "application/xml" -Body $body -Headers @{
            "Authorization"=$auth; "x-amz-date"=$ad
            "x-amz-content-sha256"=$ph; "Content-MD5"=$md5 }
}

# ============================================================
# VBS ЛАУНЧЕР (без BOM)
# ============================================================
function Write-VbsLauncher([string]$VbsPath) {
    $vbs = @"
Dim mode, filePath, cmd, ps1
Set objShell = CreateObject("WScript.Shell")
ps1 = Replace(WScript.ScriptFullName, ".vbs", ".ps1")
mode = "" : filePath = ""
If WScript.Arguments.Count >= 1 Then mode = WScript.Arguments(0)
If WScript.Arguments.Count >= 2 Then filePath = WScript.Arguments(1)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ """ & mode & """ """ & filePath & """
objShell.Run cmd, 0, False
"@
    [System.IO.File]::WriteAllText($VbsPath, $vbs, [System.Text.Encoding]::ASCII)
}

# ============================================================
# УСТАНОВКА RCLONE (автоматическая)
# ============================================================
function Install-RcloneAuto {
    $rclone = Find-Rclone
    if ($rclone) {
        Show-Msg "EndlessDisk" "rclone уже установлен:`n$rclone"
        return $true
    }

    $confirmed = Show-YesNo "EndlessDisk — Установка rclone" (
        "rclone не найден на компьютере.`n`n" +
        "Будет скачан rclone (официальный сайт rclone.org).`n" +
        "Файлы будут установлены в:`n  $env:LOCALAPPDATA\rclone\`n`n" +
        "Продолжить скачивание и установку?")
    if (-not $confirmed) { return $false }

    try {
        $destDir = Join-Path $env:LOCALAPPDATA "rclone"
        $zipUrl  = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"

        Invoke-WithProgress -Title "EndlessDisk — Установка rclone" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Скачивание rclone..."; Detail=$zipUrl; Percent=10 }

            $tempZip = Join-Path $env:TEMP "rclone-install.zip"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

            & $report @{ Status="Распаковка..."; Detail="Извлечение файлов"; Percent=50 }
            $tempExtract = Join-Path $env:TEMP "rclone-extract"
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

            $rcloneDir = Get-ChildItem $tempExtract -Directory | Select-Object -First 1
            $destDir = Join-Path $env:LOCALAPPDATA "rclone"
            if (-not (Test-Path $destDir)) { New-Item $destDir -ItemType Directory -Force | Out-Null }

            & $report @{ Status="Копирование файлов..."; Detail=$destDir; Percent=75 }
            Copy-Item (Join-Path $rcloneDir.FullName "rclone.exe") (Join-Path $destDir "rclone.exe") -Force

            & $report @{ Status="Очистка..."; Detail=""; Percent=90 }
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

            & $report @{ Status="Готово!"; Detail="rclone установлен"; Percent=100 }
            Start-Sleep -Milliseconds 500
            $syncHash.Result = $true
        }

        Show-Msg "EndlessDisk" "rclone успешно установлен!`n`nПуть: $destDir\rclone.exe"
        return $true
    }
    catch {
        Show-Msg "EndlessDisk — Ошибка" "Не удалось установить rclone:`n$($_.Exception.Message)" "Error"
        return $false
    }
}

# ============================================================
# УСТАНОВКА WINFSP (автоматическая)
# ============================================================
function Install-WinFspAuto {
    if (Find-WinFsp) {
        Show-Msg "EndlessDisk" "WinFsp уже установлен."
        return $true
    }

    $confirmed = Show-YesNo "EndlessDisk — Установка WinFsp" (
        "WinFsp не найден на компьютере.`n`n" +
        "WinFsp — драйвер файловой системы, необходимый для`n" +
        "монтирования облачного хранилища как диска Windows.`n`n" +
        "Будет скачан установщик WinFsp с GitHub (winfsp/winfsp).`n" +
        "Потребуются права администратора для установки.`n`n" +
        "Продолжить скачивание и установку?")
    if (-not $confirmed) { return $false }

    try {
        Invoke-WithProgress -Title "EndlessDisk — Установка WinFsp" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Поиск последней версии..."; Detail="GitHub API"; Percent=10 }

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod "https://api.github.com/repos/winfsp/winfsp/releases/latest" -UseBasicParsing
            $msiAsset = $release.assets | Where-Object { $_.name -like "*.msi" } | Select-Object -First 1
            if (-not $msiAsset) { throw "Не найден MSI-файл в последнем релизе WinFsp" }

            & $report @{ Status="Скачивание WinFsp..."; Detail=$msiAsset.name; Percent=25 }
            $tempMsi = Join-Path $env:TEMP $msiAsset.name
            Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $tempMsi -UseBasicParsing

            & $report @{ Status="Установка WinFsp..."; Detail="Требуются права администратора"; Percent=60 }
            $proc = Start-Process "msiexec.exe" -ArgumentList "/i `"$tempMsi`" /passive /norestart" `
                -Verb RunAs -Wait -PassThru
            if ($proc.ExitCode -ne 0) { throw "Установщик завершился с кодом $($proc.ExitCode)" }

            & $report @{ Status="Очистка..."; Detail=""; Percent=90 }
            Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue

            & $report @{ Status="Готово!"; Detail="WinFsp установлен"; Percent=100 }
            Start-Sleep -Milliseconds 500
            $syncHash.Result = $true
        }

        Show-Msg "EndlessDisk" "WinFsp успешно установлен!"
        return $true
    }
    catch {
        Show-Msg "EndlessDisk — Ошибка" "Не удалось установить WinFsp:`n$($_.Exception.Message)" "Error"
        return $false
    }
}

# ============================================================
# СОХРАНЕНИЕ КОНФИГА RCLONE (S3 ключи + remote)
# ============================================================
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
    $section = @"
[$remoteName]
type = s3
provider = Other
access_key_id = $AccessKey
secret_access_key = $SecretKey
endpoint = $($script:Config.EndpointHost)
acl = private
"@

    if (Test-Path $cfgPath) {
        $content = Get-Content $cfgPath -Raw -Encoding UTF8
        if ($content -match "(?ms)^\[$remoteName\].*?(^\[|\z)") {
            $content = $content -replace "(?ms)^\[$remoteName\]\r?\n(.*?)(^\[|\z)", "$section`n`$2"
        } else {
            $content = $content.TrimEnd() + "`n`n" + $section + "`n"
        }
        $content | Out-File $cfgPath -Encoding UTF8 -NoNewline
    } else {
        $section | Out-File $cfgPath -Encoding UTF8
    }

    $script:cachedKeys = $null
}

# ============================================================
# КОНТЕКСТНОЕ МЕНЮ — INSTALL
# ============================================================
function Do-Install {
    $scriptPath   = $PSCommandPath
    $rcloneRemote = $RCLONE_REMOTE
    $driveLetter  = $DRIVE_LETTER

    if (-not $scriptPath) { Show-Msg "Ошибка" "Запустите из .ps1 файла." "Error"; return }
    $rclone = Find-Rclone
    if (-not $rclone) { Show-Msg "Ошибка" "rclone.exe не найден!" "Error"; return }

    try {
        Invoke-WithProgress -Title "EndlessDisk — Установка меню" -WorkScript {
            $report = $syncHash.Report

            & $report @{ Status="Проверка ключей S3..."; Detail="Чтение конфига rclone"; Percent=15 }
            $configPaths = @(
                "$env:APPDATA\rclone\rclone.conf",
                "$env:USERPROFILE\.config\rclone\rclone.conf",
                "$env:LOCALAPPDATA\rclone\rclone.conf"
            )
            $foundKeys = $false
            foreach ($cf in $configPaths) {
                if (-not (Test-Path $cf)) { continue }
                $lines = Get-Content $cf -Encoding UTF8
                $inSec = $false; $ak = ""; $sk = ""
                foreach ($ln in $lines) {
                    $l = $ln.Trim()
                    if ($l -eq "[$rcloneRemote]") { $inSec = $true; continue }
                    if ($l -match '^\[' -and $inSec) { break }
                    if (-not $inSec) { continue }
                    if ($l -match '^access_key_id\s*=\s*(.+)$')     { $ak = $Matches[1].Trim() }
                    if ($l -match '^secret_access_key\s*=\s*(.+)$') { $sk = $Matches[1].Trim() }
                }
                if ($ak -and $sk) { $foundKeys = $true; break }
            }
            if (-not $foundKeys) { throw "Ключи S3 не найдены в конфиге rclone!" }

            & $report @{ Status="Создание VBS-лаунчера..."; Detail="Для скрытия консоли"; Percent=35 }
            $scriptDir = Split-Path -Parent $scriptPath
            $vbsPath = Join-Path $scriptDir "VKDiskMenu.vbs"

            $vbs = "Dim mode, filePath, cmd, ps1" + "`r`n" +
                   "Set objShell = CreateObject(""WScript.Shell"")" + "`r`n" +
                   "ps1 = Replace(WScript.ScriptFullName, "".vbs"", "".ps1"")" + "`r`n" +
                   "mode = """" : filePath = """"" + "`r`n" +
                   "If WScript.Arguments.Count >= 1 Then mode = WScript.Arguments(0)" + "`r`n" +
                   "If WScript.Arguments.Count >= 2 Then filePath = WScript.Arguments(1)" + "`r`n" +
                   "cmd = ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """""" & ps1 & """""" """""" & mode & """""" """""" & filePath & """"""" + "`r`n" +
                   "objShell.Run cmd, 0, False" + "`r`n"
            [System.IO.File]::WriteAllText($vbsPath, $vbs, (New-Object System.Text.UTF8Encoding $false))

            & $report @{ Status="Регистрация в реестре..."; Detail="Копировать ссылку"; Percent=55 }
            $k1 = "HKCU:\Software\Classes\*\shell\VKDiskCopyLink"
            New-Item -Path $k1 -Force | Out-Null
            Set-ItemProperty $k1 "(Default)" "EndlessDisk: Копировать ссылку"
            Set-ItemProperty $k1 "Icon" "shell32.dll,134"
            Set-ItemProperty $k1 "AppliesTo" ('System.ItemPathDisplay:~<"' + $driveLetter + '\"')
            New-Item -Path "$k1\command" -Force | Out-Null
            Set-ItemProperty "$k1\command" "(Default)" ('wscript.exe "' + $vbsPath + '" copylink "%1"')

            & $report @{ Status="Регистрация в реестре..."; Detail="Открыть/Закрыть доступ"; Percent=75 }
            $k2 = "HKCU:\Software\Classes\*\shell\VKDiskToggleACL"
            New-Item -Path $k2 -Force | Out-Null
            Set-ItemProperty $k2 "(Default)" "EndlessDisk: Открыть/Закрыть доступ"
            Set-ItemProperty $k2 "Icon" "shell32.dll,47"
            Set-ItemProperty $k2 "AppliesTo" ('System.ItemPathDisplay:~<"' + $driveLetter + '\"')
            New-Item -Path "$k2\command" -Force | Out-Null
            Set-ItemProperty "$k2\command" "(Default)" ('wscript.exe "' + $vbsPath + '" toggleacl "%1"')

            & $report @{ Status="Готово!"; Detail="Установка завершена"; Percent=100 }
            Start-Sleep -Milliseconds 600
            $syncHash.Result = "ok"
        }

        Show-Msg "EndlessDisk" ("Контекстное меню установлено!`n`n" +
            "В ПКМ на файлах $($DRIVE_LETTER)\:`n" +
            "  Копировать ссылку`n" +
            "  Открыть/Закрыть доступ")
    }
    catch {
        Show-Msg "EndlessDisk — Ошибка" $_.Exception.Message "Error"
    }
}

# ============================================================
# КОНТЕКСТНОЕ МЕНЮ — UNINSTALL
# ============================================================
function Do-UninstallMenu {
    try {
        Invoke-WithProgress -Title "EndlessDisk — Удаление меню" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Удаление из реестра..."; Detail="Копировать ссылку"; Percent=25 }
            Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskCopyLink" -Recurse -Force -ErrorAction SilentlyContinue
            & $report @{ Status="Удаление из реестра..."; Detail="Открыть/Закрыть доступ"; Percent=50 }
            Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskToggleACL" -Recurse -Force -ErrorAction SilentlyContinue
            & $report @{ Status="Удаление лаунчера..."; Detail=""; Percent=75 }
            $scriptDir = Split-Path -Parent $PSCommandPath
            if ($scriptDir) {
                $vbs = Join-Path $scriptDir "VKDiskMenu.vbs"
                if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue }
            }
            & $report @{ Status="Готово!"; Detail="Удаление завершено"; Percent=100 }
            Start-Sleep -Milliseconds 500
        }
    }
    catch { Log "Ошибка при удалении меню: $($_.Exception.Message)" }
}

# ============================================================
# МОНТИРОВАНИЕ ДИСКА
# ============================================================
function Do-Mount {
    $rclone = Find-Rclone
    if (-not $rclone) {
        Log "Mount: rclone не найден"
        if ($Mode -ne "mount") { Show-Msg "EndlessDisk" "rclone не найден!" "Error" }
        return
    }

    $remote   = $script:Config.RcloneRemote
    $bucket   = $script:Config.Bucket
    $letter   = $script:Config.DriveLetter
    $cache    = $script:Config.CacheSize
    $transfers = $script:Config.Transfers

    if (Test-Path $letter) {
        Log "Mount: диск $letter уже занят"
        if ($Mode -ne "mount") { Show-Msg "EndlessDisk" "Диск $letter уже подключен или занят." "Warning" }
        return
    }

    $mountArgs = @(
        "mount", "${remote}:${bucket}", $letter,
        "--vfs-cache-mode", "full",
        "--vfs-cache-max-size", $cache,
        "--vfs-read-chunk-size", "64M",
        "--buffer-size", "128M",
        "--transfers", "$transfers",
        "--no-console",
        "--links"
    )

    Log "Mount: $rclone $($mountArgs -join ' ')"
    Start-Process -FilePath $rclone -ArgumentList $mountArgs -WindowStyle Hidden
}

function Do-Unmount {
    $letter = $script:Config.DriveLetter
    $rclone = Find-Rclone
    if (-not $rclone) { return }

    try {
        $proc = Get-Process rclone -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$letter*" }
        if ($proc) { $proc | Stop-Process -Force }
    } catch {}

    if (Test-Path $letter) {
        try { & $rclone mount --unmount $letter 2>$null } catch {}
    }
}

# ============================================================
# АВТОЗАПУСК
# ============================================================
$script:AutostartRegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:AutostartName   = "EndlessDisk"

function Test-Autostart {
    $val = Get-ItemProperty $script:AutostartRegKey -Name $script:AutostartName -ErrorAction SilentlyContinue
    return ($null -ne $val)
}

function Add-Autostart {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { return $false }
    $scriptDir = Split-Path -Parent $scriptPath
    $vbsPath = Join-Path $scriptDir "VKDiskMenu.vbs"
    if (-not (Test-Path $vbsPath)) { Write-VbsLauncher $vbsPath }
    $cmd = "wscript.exe `"$vbsPath`" mount"
    Set-ItemProperty $script:AutostartRegKey -Name $script:AutostartName -Value $cmd
    return $true
}

function Remove-Autostart {
    Remove-ItemProperty $script:AutostartRegKey -Name $script:AutostartName -ErrorAction SilentlyContinue
}

# ============================================================
# ЯРЛЫК НА РАБОЧЕМ СТОЛЕ
# ============================================================
function Get-ShortcutPath {
    return Join-Path ([Environment]::GetFolderPath("Desktop")) "EndlessDisk.lnk"
}

function Test-DesktopShortcut {
    return (Test-Path (Get-ShortcutPath))
}

function Add-DesktopShortcut {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { return $false }
    $scriptDir = Split-Path -Parent $scriptPath
    $vbsPath = Join-Path $scriptDir "VKDiskMenu.vbs"
    if (-not (Test-Path $vbsPath)) { Write-VbsLauncher $vbsPath }

    $lnkPath = Get-ShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = "wscript.exe"
    $shortcut.Arguments = "`"$vbsPath`" gui"
    $shortcut.WorkingDirectory = $scriptDir
    $shortcut.IconLocation = "shell32.dll,134"
    $shortcut.Description = "EndlessDisk — VK Cloud S3 Manager"
    $shortcut.Save()
    return $true
}

function Remove-DesktopShortcut {
    $lnk = Get-ShortcutPath
    if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
}

# ============================================================
# ПОЛНОЕ УДАЛЕНИЕ
# ============================================================
function Do-FullUninstall {
    if (-not (Show-YesNo "EndlessDisk — Удаление" (
        "Вы собираетесь полностью удалить EndlessDisk.`n`n" +
        "Будут удалены:`n" +
        "  - Контекстное меню Windows`n" +
        "  - Автозапуск`n" +
        "  - Ярлык на рабочем столе`n" +
        "  - VBS-лаунчер`n" +
        "  - Конфигурация EndlessDisk`n`n" +
        "Продолжить?"))) { return }

    # Отключаем диск
    Do-Unmount

    # Удаляем контекстное меню
    Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskCopyLink" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Classes\*\shell\VKDiskToggleACL" -Recurse -Force -ErrorAction SilentlyContinue

    # Удаляем автозапуск
    Remove-Autostart

    # Удаляем ярлык
    Remove-DesktopShortcut

    # Удаляем VBS-лаунчер
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ($scriptDir) {
        $vbs = Join-Path $scriptDir "VKDiskMenu.vbs"
        if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue }
    }

    # Удаляем конфигурацию приложения
    if (Test-Path $script:ConfigDir) {
        Remove-Item $script:ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Спрашиваем про конфиг rclone
    $deleteRcloneConfig = Show-YesNo "EndlessDisk — Конфиг rclone" (
        "Удалить конфигурацию rclone?`n`n" +
        "Это удалит файл rclone.conf с вашими`n" +
        "ключами доступа S3 и настройками remote.`n`n" +
        "Если вы используете rclone для других целей,`n" +
        "выберите 'Нет' — будет удалена только секция [$RCLONE_REMOTE].`n`n" +
        "Удалить ВЕСЬ конфиг rclone?")

    if ($deleteRcloneConfig) {
        $rcloneCfgPaths = @(
            "$env:APPDATA\rclone",
            "$env:USERPROFILE\.config\rclone",
            "$env:LOCALAPPDATA\rclone"
        )
        foreach ($p in $rcloneCfgPaths) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } else {
        # Удаляем только секцию remote из конфига
        $cfgPaths = @(
            "$env:APPDATA\rclone\rclone.conf",
            "$env:USERPROFILE\.config\rclone\rclone.conf",
            "$env:LOCALAPPDATA\rclone\rclone.conf"
        )
        foreach ($cf in $cfgPaths) {
            if (-not (Test-Path $cf)) { continue }
            $content = Get-Content $cf -Raw -Encoding UTF8
            $remoteName = $script:Config.RcloneRemote
            $content = $content -replace "(?ms)^\[$remoteName\]\r?\n((?!\[).)*", ""
            $content = $content.Trim()
            if ($content) { $content | Out-File $cf -Encoding UTF8 }
            else { Remove-Item $cf -Force -ErrorAction SilentlyContinue }
        }
    }

    # Спрашиваем про rclone.exe
    $rcloneLocalDir = Join-Path $env:LOCALAPPDATA "rclone"
    $rcloneExe = Join-Path $rcloneLocalDir "rclone.exe"
    if (Test-Path $rcloneExe) {
        if (Show-YesNo "EndlessDisk — rclone" "Удалить rclone.exe из $rcloneLocalDir?") {
            try {
                Get-Process rclone -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Remove-Item $rcloneLocalDir -Recurse -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    Show-Msg "EndlessDisk" "Программа полностью удалена.`n`nФайл скрипта VKDiskMenu.ps1 можно удалить вручную."
}

# ============================================================
# COPYLINK
# ============================================================
function Do-CopyLink {
    param([string]$Path)
    if (-not $Path -or -not $Path.StartsWith($DRIVE_LETTER, [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-Msg "EndlessDisk" "Файл не на диске $DRIVE_LETTER" "Error"; return
    }
    $fileName  = [System.IO.Path]::GetFileName($Path)
    $objectKey = Get-ObjectKey $Path

    try {
        $checkResult = Invoke-WithProgress -Title "EndlessDisk — Проверка" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Проверка доступа..."; Detail=$fileName; Percent=50 }
            $syncHash.Result = @{ IsPublic = (Test-IsPublic $objectKey) }
            & $report @{ Status="Готово"; Percent=100 }
            Start-Sleep -Milliseconds 200
        }
        $isPublic = $checkResult.IsPublic

        if (-not $isPublic) {
            if (-not (Show-YesNo "EndlessDisk" "Файл '$fileName' ПРИВАТНЫЙ.`n`nСделать публичным и скопировать ссылку?")) { return }
            Invoke-WithProgress -Title "EndlessDisk — Открытие доступа" -WorkScript {
                $report = $syncHash.Report
                & $report @{ Status="Получение Owner ID..."; Detail=$fileName; Percent=25 }
                $ownerId = Get-OwnerCanonicalId $objectKey
                & $report @{ Status="Установка public-read..."; Detail="Отправка ACL"; Percent=60 }
                Set-ObjectAcl $objectKey "public-read" $ownerId
                & $report @{ Status="Применение..."; Detail=""; Percent=85 }
                Start-Sleep -Seconds 1
                & $report @{ Status="Готово!"; Percent=100 }
                Start-Sleep -Milliseconds 300
            }
        }

        $link = Get-PublicUrl $objectKey
        [System.Windows.Forms.Clipboard]::SetText($link)
        $msg = if (-not $isPublic) { "Файл сделан публичным.`nСсылка скопирована:`n`n$link" }
               else { "Ссылка скопирована:`n`n$link" }
        Show-Msg "EndlessDisk" $msg
    }
    catch {
        Log "ОШИБКА CopyLink: $($_.Exception.Message)"
        Show-Msg "EndlessDisk — Ошибка" $_.Exception.Message "Error"
    }
}

# ============================================================
# TOGGLEACL
# ============================================================
function Do-ToggleAcl {
    param([string]$Path)
    if (-not $Path -or -not $Path.StartsWith($DRIVE_LETTER, [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-Msg "EndlessDisk" "Файл не на диске $DRIVE_LETTER" "Error"; return
    }
    $fileName  = [System.IO.Path]::GetFileName($Path)
    $objectKey = Get-ObjectKey $Path

    try {
        $info = Invoke-WithProgress -Title "EndlessDisk — Проверка доступа" -WorkScript {
            $report = $syncHash.Report
            & $report @{ Status="Проверка доступа..."; Detail=$fileName; Percent=30 }
            $pub = Test-IsPublic $objectKey
            & $report @{ Status="Получение Owner ID..."; Detail=""; Percent=65 }
            $oid = Get-OwnerCanonicalId $objectKey
            $syncHash.Result = @{ IsPublic=$pub; OwnerId=$oid }
            & $report @{ Status="Готово"; Percent=100 }
            Start-Sleep -Milliseconds 200
        }

        if ($info.IsPublic) {
            if (-not (Show-YesNo "EndlessDisk" "Файл '$fileName' сейчас ПУБЛИЧНЫЙ.`n`nСделать приватным?")) { return }
            Invoke-WithProgress -Title "EndlessDisk — Закрытие доступа" -WorkScript {
                $report = $syncHash.Report
                & $report @{ Status="Установка private..."; Detail=$fileName; Percent=50 }
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
                & $report @{ Status="Установка public-read..."; Detail=$fileName; Percent=40 }
                Set-ObjectAcl $objectKey "public-read" ($info.OwnerId)
                & $report @{ Status="Применение..."; Detail=""; Percent=80 }
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

# ============================================================
# ГЛАВНОЕ ОКНО — GUI МЕНЕДЖЕР
# ============================================================
function Show-MainGui {
    $cfg = $script:Config

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "EndlessDisk v$($script:AppVersion) — VK Cloud S3"
    $form.Size = New-Object System.Drawing.Size(540, 740)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
            [System.IO.Path]::Combine($env:SystemRoot, "System32", "shell32.dll"))
    } catch {}

    $fontTitle  = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $fontNormal = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontSmall  = New-Object System.Drawing.Font("Segoe UI", 8)
    $colorOk    = [System.Drawing.Color]::FromArgb(34, 139, 34)
    $colorNo    = [System.Drawing.Color]::FromArgb(200, 60, 60)
    $colorGray  = [System.Drawing.Color]::FromArgb(130, 130, 130)

    # --- СТАТУС ---
    $grpStatus = New-Object System.Windows.Forms.GroupBox
    $grpStatus.Text = "Статус компонентов"
    $grpStatus.Font = $fontTitle
    $grpStatus.Location = New-Object System.Drawing.Point(12, 8)
    $grpStatus.Size = New-Object System.Drawing.Size(500, 135)
    $form.Controls.Add($grpStatus)

    $statusLabels = @{}
    $statusBtns = @{}
    $statusItems = @("rclone", "WinFsp", "Конфиг S3", "Контекстное меню")
    $sy = 22
    foreach ($item in $statusItems) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "${item}:"
        $lbl.Font = $fontNormal
        $lbl.Location = New-Object System.Drawing.Point(15, $sy)
        $lbl.Size = New-Object System.Drawing.Size(120, 22)
        $grpStatus.Controls.Add($lbl)

        $lblSt = New-Object System.Windows.Forms.Label
        $lblSt.Font = $fontNormal
        $lblSt.Location = New-Object System.Drawing.Point(140, $sy)
        $lblSt.Size = New-Object System.Drawing.Size(200, 22)
        $grpStatus.Controls.Add($lblSt)
        $statusLabels[$item] = $lblSt

        $btn = New-Object System.Windows.Forms.Button
        $btn.Font = $fontSmall
        $btn.Location = New-Object System.Drawing.Point(370, ($sy - 2))
        $btn.Size = New-Object System.Drawing.Size(115, 24)
        $btn.FlatStyle = "Flat"
        $grpStatus.Controls.Add($btn)
        $statusBtns[$item] = $btn

        $sy += 27
    }

    # --- НАСТРОЙКИ ---
    $grpSettings = New-Object System.Windows.Forms.GroupBox
    $grpSettings.Text = "Настройки диска"
    $grpSettings.Font = $fontTitle
    $grpSettings.Location = New-Object System.Drawing.Point(12, 150)
    $grpSettings.Size = New-Object System.Drawing.Size(500, 225)
    $form.Controls.Add($grpSettings)

    $textboxes = @{}
    $settingsMap = [ordered]@{
        "DriveLetter"  = "Буква диска"
        "RcloneRemote" = "Имя remote"
        "Bucket"       = "Бакет (bucket)"
        "Domain"       = "Домен (для ссылок)"
        "EndpointHost"  = "Эндпоинт S3"
        "Region"       = "Регион"
        "CacheSize"    = "Размер кэша"
        "Transfers"    = "Потоков загрузки"
    }
    $ty = 22
    foreach ($entry in $settingsMap.GetEnumerator()) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "$($entry.Value):"
        $lbl.Font = $fontNormal
        $lbl.Location = New-Object System.Drawing.Point(15, ($ty + 3))
        $lbl.Size = New-Object System.Drawing.Size(155, 20)
        $grpSettings.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Font = $fontNormal
        $tb.Location = New-Object System.Drawing.Point(175, $ty)
        $tb.Size = New-Object System.Drawing.Size(310, 22)
        $tb.Text = [string]$cfg[$entry.Key]
        $grpSettings.Controls.Add($tb)
        $textboxes[$entry.Key] = $tb

        $ty += 25
    }

    # --- КЛЮЧИ S3 ---
    $grpKeys = New-Object System.Windows.Forms.GroupBox
    $grpKeys.Text = "Ключи S3 (rclone)"
    $grpKeys.Font = $fontTitle
    $grpKeys.Location = New-Object System.Drawing.Point(12, 382)
    $grpKeys.Size = New-Object System.Drawing.Size(500, 82)
    $form.Controls.Add($grpKeys)

    $lblAK = New-Object System.Windows.Forms.Label
    $lblAK.Text = "Access Key:"
    $lblAK.Font = $fontNormal
    $lblAK.Location = New-Object System.Drawing.Point(15, 25)
    $lblAK.Size = New-Object System.Drawing.Size(85, 20)
    $grpKeys.Controls.Add($lblAK)
    $tbAccessKey = New-Object System.Windows.Forms.TextBox
    $tbAccessKey.Font = $fontNormal
    $tbAccessKey.Location = New-Object System.Drawing.Point(105, 22)
    $tbAccessKey.Size = New-Object System.Drawing.Size(380, 22)
    $grpKeys.Controls.Add($tbAccessKey)

    $lblSK = New-Object System.Windows.Forms.Label
    $lblSK.Text = "Secret Key:"
    $lblSK.Font = $fontNormal
    $lblSK.Location = New-Object System.Drawing.Point(15, 52)
    $lblSK.Size = New-Object System.Drawing.Size(85, 20)
    $grpKeys.Controls.Add($lblSK)
    $tbSecretKey = New-Object System.Windows.Forms.TextBox
    $tbSecretKey.Font = $fontNormal
    $tbSecretKey.Location = New-Object System.Drawing.Point(105, 49)
    $tbSecretKey.Size = New-Object System.Drawing.Size(380, 22)
    $tbSecretKey.UseSystemPasswordChar = $true
    $grpKeys.Controls.Add($tbSecretKey)

    # Загрузить текущие ключи
    $keys = Get-S3Keys
    if ($keys) {
        $tbAccessKey.Text = $keys.AccessKey
        $tbSecretKey.Text = $keys.SecretKey
    }

    # --- ОПЦИИ ---
    $chkAutostart = New-Object System.Windows.Forms.CheckBox
    $chkAutostart.Text = "Запускать диск при старте Windows (без окон)"
    $chkAutostart.Font = $fontNormal
    $chkAutostart.Location = New-Object System.Drawing.Point(15, 472)
    $chkAutostart.Size = New-Object System.Drawing.Size(400, 22)
    $chkAutostart.Checked = (Test-Autostart)
    $form.Controls.Add($chkAutostart)

    $lblAutoWarn = New-Object System.Windows.Forms.Label
    $lblAutoWarn.Text = "Добавит запись в автозапуск Windows. Диск подключится автоматически без видимых окон."
    $lblAutoWarn.Font = $fontSmall
    $lblAutoWarn.ForeColor = $colorGray
    $lblAutoWarn.Location = New-Object System.Drawing.Point(33, 494)
    $lblAutoWarn.Size = New-Object System.Drawing.Size(470, 18)
    $form.Controls.Add($lblAutoWarn)

    $chkShortcut = New-Object System.Windows.Forms.CheckBox
    $chkShortcut.Text = "Создать ярлык на рабочем столе"
    $chkShortcut.Font = $fontNormal
    $chkShortcut.Location = New-Object System.Drawing.Point(15, 516)
    $chkShortcut.Size = New-Object System.Drawing.Size(400, 22)
    $chkShortcut.Checked = (Test-DesktopShortcut)
    $form.Controls.Add($chkShortcut)

    $lblShortWarn = New-Object System.Windows.Forms.Label
    $lblShortWarn.Text = "Ярлык откроет это окно настроек. Консольное окно не будет показано."
    $lblShortWarn.Font = $fontSmall
    $lblShortWarn.ForeColor = $colorGray
    $lblShortWarn.Location = New-Object System.Drawing.Point(33, 538)
    $lblShortWarn.Size = New-Object System.Drawing.Size(470, 18)
    $form.Controls.Add($lblShortWarn)

    # --- КНОПКИ ---
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Сохранить настройки"
    $btnSave.Font = $fontNormal
    $btnSave.Location = New-Object System.Drawing.Point(12, 568)
    $btnSave.Size = New-Object System.Drawing.Size(160, 34)
    $btnSave.FlatStyle = "Flat"
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 230)
    $form.Controls.Add($btnSave)

    $btnMount = New-Object System.Windows.Forms.Button
    $btnMount.Text = "Подключить диск"
    $btnMount.Font = $fontNormal
    $btnMount.Location = New-Object System.Drawing.Point(180, 568)
    $btnMount.Size = New-Object System.Drawing.Size(160, 34)
    $btnMount.FlatStyle = "Flat"
    $btnMount.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 250)
    $form.Controls.Add($btnMount)

    $btnUnmount = New-Object System.Windows.Forms.Button
    $btnUnmount.Text = "Отключить диск"
    $btnUnmount.Font = $fontNormal
    $btnUnmount.Location = New-Object System.Drawing.Point(348, 568)
    $btnUnmount.Size = New-Object System.Drawing.Size(164, 34)
    $btnUnmount.FlatStyle = "Flat"
    $btnUnmount.BackColor = [System.Drawing.Color]::FromArgb(250, 235, 230)
    $form.Controls.Add($btnUnmount)

    $btnFullUninstall = New-Object System.Windows.Forms.Button
    $btnFullUninstall.Text = "Полное удаление программы"
    $btnFullUninstall.Font = $fontSmall
    $btnFullUninstall.Location = New-Object System.Drawing.Point(12, 612)
    $btnFullUninstall.Size = New-Object System.Drawing.Size(500, 30)
    $btnFullUninstall.FlatStyle = "Flat"
    $btnFullUninstall.ForeColor = [System.Drawing.Color]::FromArgb(180, 50, 50)
    $form.Controls.Add($btnFullUninstall)

    $lblFooter = New-Object System.Windows.Forms.Label
    $lblFooter.Text = "EndlessDisk v$($script:AppVersion) — VK Cloud S3 Manager"
    $lblFooter.Font = $fontSmall
    $lblFooter.ForeColor = $colorGray
    $lblFooter.Location = New-Object System.Drawing.Point(12, 650)
    $lblFooter.Size = New-Object System.Drawing.Size(500, 18)
    $lblFooter.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($lblFooter)

    # --- ФУНКЦИЯ ОБНОВЛЕНИЯ СТАТУСА ---
    $updateStatus = {
        $hasRclone = $null -ne (Find-Rclone)
        $hasWinFsp = Find-WinFsp
        $hasKeys = $null -ne (Get-S3Keys)
        $hasMenu = Test-Path "HKCU:\Software\Classes\*\shell\VKDiskCopyLink"

        if ($hasRclone) {
            $statusLabels["rclone"].Text = "Установлен"
            $statusLabels["rclone"].ForeColor = $colorOk
            $statusBtns["rclone"].Text = "Переустановить"
        } else {
            $statusLabels["rclone"].Text = "Не найден"
            $statusLabels["rclone"].ForeColor = $colorNo
            $statusBtns["rclone"].Text = "Установить"
        }

        if ($hasWinFsp) {
            $statusLabels["WinFsp"].Text = "Установлен"
            $statusLabels["WinFsp"].ForeColor = $colorOk
            $statusBtns["WinFsp"].Text = "Переустановить"
        } else {
            $statusLabels["WinFsp"].Text = "Не найден"
            $statusLabels["WinFsp"].ForeColor = $colorNo
            $statusBtns["WinFsp"].Text = "Установить"
        }

        if ($hasKeys) {
            $statusLabels["Конфиг S3"].Text = "Настроен"
            $statusLabels["Конфиг S3"].ForeColor = $colorOk
            $statusBtns["Конфиг S3"].Text = ""
            $statusBtns["Конфиг S3"].Visible = $false
        } else {
            $statusLabels["Конфиг S3"].Text = "Не настроен"
            $statusLabels["Конфиг S3"].ForeColor = $colorNo
            $statusBtns["Конфиг S3"].Text = "Настроить"
            $statusBtns["Конфиг S3"].Visible = $true
        }

        if ($hasMenu) {
            $statusLabels["Контекстное меню"].Text = "Установлено"
            $statusLabels["Контекстное меню"].ForeColor = $colorOk
            $statusBtns["Контекстное меню"].Text = "Удалить меню"
        } else {
            $statusLabels["Контекстное меню"].Text = "Не установлено"
            $statusLabels["Контекстное меню"].ForeColor = $colorNo
            $statusBtns["Контекстное меню"].Text = "Установить меню"
        }
    }

    # --- ОБРАБОТЧИКИ ---
    $statusBtns["rclone"].Add_Click({
        Install-RcloneAuto
        & $updateStatus
    })

    $statusBtns["WinFsp"].Add_Click({
        Install-WinFspAuto
        & $updateStatus
    })

    $statusBtns["Конфиг S3"].Add_Click({
        # Перевести фокус на поля ключей
        $tbAccessKey.Focus()
        Show-Msg "EndlessDisk" "Введите Access Key и Secret Key в поля ниже, затем нажмите 'Сохранить настройки'."
    })

    $statusBtns["Контекстное меню"].Add_Click({
        $hasMenu = Test-Path "HKCU:\Software\Classes\*\shell\VKDiskCopyLink"
        if ($hasMenu) {
            if (Show-YesNo "EndlessDisk" "Удалить контекстное меню?") {
                Do-UninstallMenu
                & $updateStatus
            }
        } else {
            Do-Install
            & $updateStatus
        }
    })

    $btnSave.Add_Click({
        # Собираем настройки
        $newCfg = @{}
        foreach ($entry in $settingsMap.GetEnumerator()) {
            $val = $textboxes[$entry.Key].Text.Trim()
            if ($entry.Key -eq "Transfers") {
                $newCfg[$entry.Key] = [int]$val
            } else {
                $newCfg[$entry.Key] = $val
            }
        }

        Save-Config $newCfg
        $script:Config = $newCfg

        # Обновляем глобальные переменные
        $script:DOMAIN        = $newCfg.Domain
        $script:BUCKET        = $newCfg.Bucket
        $script:DRIVE_LETTER  = $newCfg.DriveLetter
        $script:RCLONE_REMOTE = $newCfg.RcloneRemote
        $script:ENDPOINT_HOST = $newCfg.EndpointHost
        $script:REGION        = $newCfg.Region

        # Сохраняем ключи S3 если введены
        $ak = $tbAccessKey.Text.Trim()
        $sk = $tbSecretKey.Text.Trim()
        if ($ak -and $sk) {
            Save-RcloneConfig $ak $sk
        }

        # Обработка автозапуска
        if ($chkAutostart.Checked) {
            $wasAutostart = Test-Autostart
            if (-not $wasAutostart) {
                $confirmAuto = Show-YesNo "EndlessDisk — Автозапуск" (
                    "Вы включаете автозапуск.`n`n" +
                    "При старте Windows диск будет автоматически`n" +
                    "подключаться без видимых окон и консолей.`n`n" +
                    "Запись будет добавлена в:`n" +
                    "  HKCU\...\Run\EndlessDisk`n`n" +
                    "Продолжить?")
                if ($confirmAuto) { Add-Autostart }
                else { $chkAutostart.Checked = $false }
            }
        } else {
            Remove-Autostart
        }

        # Обработка ярлыка
        if ($chkShortcut.Checked) {
            $wasShortcut = Test-DesktopShortcut
            if (-not $wasShortcut) {
                $confirmShort = Show-YesNo "EndlessDisk — Ярлык" (
                    "Создать ярлык EndlessDisk на рабочем столе?`n`n" +
                    "Ярлык откроет это окно настроек.`n" +
                    "Консольное окно не будет показано.")
                if ($confirmShort) { Add-DesktopShortcut }
                else { $chkShortcut.Checked = $false }
            }
        } else {
            Remove-DesktopShortcut
        }

        & $updateStatus
        Show-Msg "EndlessDisk" "Настройки сохранены!"
    })

    $btnMount.Add_Click({
        Do-Mount
        Start-Sleep -Seconds 2
        $letter = $textboxes["DriveLetter"].Text.Trim()
        if (Test-Path $letter) {
            Show-Msg "EndlessDisk" "Диск $letter успешно подключен!"
        } else {
            Show-Msg "EndlessDisk" "Диск $letter пока не появился.`nПодождите несколько секунд или проверьте настройки." "Warning"
        }
    })

    $btnUnmount.Add_Click({
        if (Show-YesNo "EndlessDisk" "Отключить диск $($textboxes['DriveLetter'].Text.Trim())?") {
            Do-Unmount
            Show-Msg "EndlessDisk" "Диск отключен."
        }
    })

    $btnFullUninstall.Add_Click({
        Do-FullUninstall
        $form.Close()
    })

    # --- Инициализация статуса ---
    & $updateStatus

    $form.ShowDialog() | Out-Null
    $form.Dispose()
}

# ============================================================
# MAIN
# ============================================================
Log "=== EndlessDisk v$($script:AppVersion) === Режим: $Mode | Файл: $FilePath"

switch ($Mode) {
    "mount"       { Do-Mount }
    "gui"         { Show-MainGui }
    "install"     { Do-Install }
    "uninstall"   { Do-FullUninstall }
    "copylink"    { Do-CopyLink  $FilePath }
    "toggleacl"   { Do-ToggleAcl $FilePath }
    default       { Show-MainGui }
}
