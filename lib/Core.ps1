# ============================================================
# EndlessDisk — Core: Config, Logging, GUI Helpers, Crypto, S3
# ============================================================

# --- Config management ---
$script:AppName    = "EndlessDisk"
$script:AppVersion = "8.1"
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

function Update-GlobalVars {
    $script:DOMAIN        = $script:Config.Domain
    $script:BUCKET        = $script:Config.Bucket
    $script:DRIVE_LETTER  = $script:Config.DriveLetter
    $script:RCLONE_REMOTE = $script:Config.RcloneRemote
    $script:ENDPOINT_HOST = $script:Config.EndpointHost
    $script:REGION        = $script:Config.Region
}
Update-GlobalVars

# --- Logging ---
$script:LogFile = Join-Path $env:TEMP "EndlessDisk.log"
function Log {
    param([string]$Text)
    try { 
        $line = "[$(Get-Date -Format 'HH:mm:ss.fff')] $Text"
        $line | Out-File -Append -FilePath $script:LogFile -Encoding UTF8 -Force
    } catch {}
}


# --- GUI bootstrap ---
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

# --- Async background task (FIXED v2 — полный InitialSessionState) ---
$script:bgState = [hashtable]::Synchronized(@{
    Running    = $false
    Status     = ""
    Detail     = ""
    Block      = ""
    Percent    = -1
    Done       = $false
    Error      = $null
    Result     = $null
})
$script:bgRunspace = $null

function Start-BackgroundTask {
    param(
        [scriptblock]$Work,
        [hashtable]$Arguments
    )

    if ($script:bgState.Running) { return $false }

    $script:bgState.Running = $true
    $script:bgState.Done    = $false
    $script:bgState.Error   = $null
    $script:bgState.Result  = $null
    $script:bgState.Status  = ""
    $script:bgState.Detail  = ""
    $script:bgState.Block   = ""
    $script:bgState.Percent = -1

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = "STA"
    $rs.Open()

    $rs.SessionStateProxy.SetVariable("state", $script:bgState)

    if ($script:LibDir) {
        $rs.SessionStateProxy.SetVariable("libDir", $script:LibDir)
    }

    if ($Arguments) {
        $rs.SessionStateProxy.SetVariable("taskArgs", $Arguments)
    }

    $workText = $Work.ToString()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
        param($state, $workText, $libDir)

        $Global:state = $state
        $script:state = $state

        if ($libDir) {
            . (Join-Path $libDir "Core.ps1")
            . (Join-Path $libDir "Setup.ps1")
        }

        $Global:state = $state
        $script:state = $state

        $workBlock = [scriptblock]::Create($workText)

        try {
            & $workBlock
        }
        catch {
            if ($state) {
                $state.Error = $_.Exception.Message + "`n" + $_.ScriptStackTrace
            }
        }
        finally {
            if ($state) { $state.Done = $true }
        }
    }).AddArgument($script:bgState).AddArgument($workText).AddArgument($script:LibDir)

    $async = $ps.BeginInvoke()
    $script:bgRunspace = @{ PS = $ps; RS = $rs; Async = $async }
    return $true
}

function Complete-BackgroundTask {
    if (-not $script:bgRunspace) { return }
    try { $script:bgRunspace.PS.EndInvoke($script:bgRunspace.Async) } catch {}
    $script:bgRunspace.PS.Dispose()
    $script:bgRunspace.RS.Close()
    $script:bgRunspace = $null
    $script:bgState.Running = $false
}

# --- Progress dialog (for copylink/toggleacl non-GUI modes) ---
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

    $lblBlock = New-Object System.Windows.Forms.Label
    $lblBlock.Location = New-Object System.Drawing.Point(20, 140)
    $lblBlock.Size = New-Object System.Drawing.Size(390, 18)
    $lblBlock.Font = New-Object System.Drawing.Font("Consolas", 7.5)
    $lblBlock.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $form.Controls.Add($lblBlock)

    $syncHash = [hashtable]::Synchronized(@{
        Result = $null; Error = $null; Done = $false
        Updates = [System.Collections.ArrayList]::new()
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
            if ($info.Block) { $lblBlock.Text = $info.Block }
            if ($info.Percent -ne $null -and $info.Percent -ge 0) {
                $bar.Style = "Continuous"
                $bar.Value = [Math]::Min([int]$info.Percent, 100)
            }
        }
        if ($syncHash.Done) { $uiTimer.Stop(); $timer.Stop(); $form.Close() }
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
    $timer.Start(); $uiTimer.Start()
    $form.ShowDialog() | Out-Null
    $timer.Dispose(); $uiTimer.Dispose()
    try { $ps.EndInvoke($asyncResult) } catch {}
    $ps.Dispose(); $runspace.Close(); $form.Dispose()
    if ($syncHash.Error) { throw $syncHash.Error }
    return $syncHash.Result
}

# --- Component detection ---
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
    foreach ($p in @(
        "${env:ProgramFiles}\WinFsp\bin\winfsp-x64.dll",
        "${env:ProgramFiles(x86)}\WinFsp\bin\winfsp-x64.dll"
    )) { if (Test-Path $p) { return $true } }
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\WinFsp" -ErrorAction SilentlyContinue
    if ($reg -and $reg.InstallDir -and (Test-Path $reg.InstallDir)) { return $true }
    return $false
}

function Get-WinFspUninstallId {
    $items = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
    if (-not $items) { return $null }

    foreach ($item in $items) {
        if ($item.DisplayName -and $item.DisplayName -like "*WinFsp*") {
            return $item.PSChildName
        }
    }
    return $null
}

# --- S3 Keys ---
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
            if ($l -eq "[$($script:RCLONE_REMOTE)]") { $inSection = $true; continue }
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
    return $null
}

# --- URL utilities ---
function Get-ObjectKey([string]$FullPath) {
    $rel = $FullPath.Substring($script:DRIVE_LETTER.Length).TrimStart("\", "/")
    return ($rel -replace '\\', '/')
}
function Get-PublicUrl([string]$ObjectKey) {
    $enc = ($ObjectKey -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    return "https://$($script:DOMAIN)/$enc"
}

# --- Crypto ---
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

# --- S3 Signature ---
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
    $scope  = "$DateStamp/$($script:REGION)/s3/aws4_request"
    $sts    = "AWS4-HMAC-SHA256`n$AmzDate`n$scope`n$crHash"
    $kD = HmacSha256Bytes ([System.Text.Encoding]::UTF8.GetBytes("AWS4$($keys.SecretKey)")) $DateStamp
    $kR = HmacSha256Bytes $kD $script:REGION
    $kS = HmacSha256Bytes $kR "s3"
    $kF = HmacSha256Bytes $kS "aws4_request"
    $sig = ([BitConverter]::ToString((HmacSha256Bytes $kF $sts)) -replace '-','').ToLower()
    return "AWS4-HMAC-SHA256 Credential=$($keys.AccessKey)/$scope, SignedHeaders=$sHdrs, Signature=$sig"
}

function Test-IsPublic([string]$ObjectKey) {
    try {
        $null = Invoke-WebRequest -Uri (Get-PublicUrl $ObjectKey) -Method HEAD `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-OwnerCanonicalId([string]$ObjectKey) {
    $now = [datetime]::UtcNow
    $ds  = $now.ToString("yyyyMMdd"); $ad = $now.ToString("yyyyMMddTHHmmssZ")
    $ek  = ($ObjectKey -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
    $cu  = "/$($script:BUCKET)/$ek"; $ph = Sha256Hex ""
    $h   = @{ "host"=$script:ENDPOINT_HOST; "x-amz-content-sha256"=$ph; "x-amz-date"=$ad }
    $auth = New-S3Signature "GET" $cu "acl=" $h $ph $ds $ad
    $r = Invoke-WebRequest -Uri "https://$($script:ENDPOINT_HOST)$cu`?acl" -Method GET `
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
    $cu   = "/$($script:BUCKET)/$ek"
    $md5  = [Convert]::ToBase64String([System.Security.Cryptography.MD5]::Create().ComputeHash($body))
    $ph   = Sha256HexBytes $body
    $h    = @{
        "content-md5"=$md5; "content-type"="application/xml"
        "host"=$script:ENDPOINT_HOST; "x-amz-content-sha256"=$ph; "x-amz-date"=$ad
    }
    $auth = New-S3Signature "PUT" $cu "acl=" $h $ph $ds $ad
    $null = Invoke-WebRequest -Uri "https://$($script:ENDPOINT_HOST)$cu`?acl" -Method PUT `
        -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop `
        -ContentType "application/xml" -Body $body -Headers @{
            "Authorization"=$auth; "x-amz-date"=$ad
            "x-amz-content-sha256"=$ph; "Content-MD5"=$md5 }
}
