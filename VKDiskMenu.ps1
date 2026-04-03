<#
.SYNOPSIS
    EndlessDisk - VK Cloud S3 Manager
    v8.1: Modular GUI with async operations
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

# Load modules
$libDir = Join-Path $PSScriptRoot "lib"
. "$libDir\Core.ps1"
. "$libDir\Setup.ps1"
. "$libDir\MainForm.ps1"

Log "=== EndlessDisk v$($script:AppVersion) === Mode: $Mode | File: $FilePath"

switch ($Mode) {
    "mount"     { Do-Mount }
    "gui"       { Show-MainGui }
    "install"   { Do-Install }
    "uninstall" { Do-FullUninstallWork }
    "copylink"  { Do-CopyLink  $FilePath }
    "toggleacl" { Do-ToggleAcl $FilePath }
    default     { Show-MainGui }
}
