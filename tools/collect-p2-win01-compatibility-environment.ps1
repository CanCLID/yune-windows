param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

if ($OutputPath -eq "") {
    $OutputPath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\compatibility-environment.json"
}

$OperatingSystem = $null
try {
    $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
}
catch {
    $OperatingSystem = $null
}

$OsCaption = [Environment]::OSVersion.VersionString
$OsVersion = [Environment]::OSVersion.Version.ToString()
$OsBuild = [Environment]::OSVersion.Version.Build.ToString()
$OsArchitecture = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
if ($null -ne $OperatingSystem) {
    if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.Caption)) {
        $OsCaption = $OperatingSystem.Caption
    }
    if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.Version)) {
        $OsVersion = $OperatingSystem.Version
    }
    if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.BuildNumber)) {
        $OsBuild = $OperatingSystem.BuildNumber
    }
    if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.OSArchitecture)) {
        $OsArchitecture = $OperatingSystem.OSArchitecture
    }
}

$BrowserPath = Find-ChromiumBrowserPath
$InstallDir = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Yune\WindowsIme"))

$Environment = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    machine_state_changed = $false
    compatibility_target_id = "P2-WIN01-WIN11-X64"
    os_caption = $OsCaption
    os_version = $OsVersion
    os_build = $OsBuild
    os_architecture = $OsArchitecture
    process_architecture = if ([Environment]::Is64BitProcess) { "64-bit" } else { "32-bit" }
    install_dir = $InstallDir
    browser_path = $BrowserPath
    browser_available = $null -ne $BrowserPath
    approval_required_for_live_gates = $true
    live_status = "pending-approved-live-run"
    p2_win01_closes = $false
}

New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null
$Environment | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
