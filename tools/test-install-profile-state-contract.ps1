param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallerPath = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "missing installer script: $InstallerPath"
}
if (-not (Test-Path -LiteralPath $SupportPath)) {
    throw "missing live-smoke support script: $SupportPath"
}

$Source = Get-Content -Raw -LiteralPath $InstallerPath
$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

foreach ($Required in @(
        'function\s+Get-YuneWindowsMachineRegistrationState',
        'function\s+Assert-YuneWindowsMachineRegistration',
        'machine_registration_verified',
        'machine_registration_registered',
        'machine_registration_missing_keys',
        'Registry::HKEY_CLASSES_ROOT\\CLSID\\\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567\}',
        'LanguageProfile\\0x00000c04\\\$ProfileGuid'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "machine-registration support is missing required pattern: $Required"
    }
}

foreach ($Required in @(
        'Invoke-YuneWindowsRegsvr32(?s:.*?)-Operation\s+"regsvr32 registration"',
        'Assert-YuneWindowsMachineRegistration\s+-InstallDir\s+\$InstallRoot'
    )) {
    if ($Source -notmatch $Required) {
        throw "installer must verify durable YuneWindows machine registration after regsvr32: $Required"
    }
}

if ($Source -match 'Assert-YuneWindowsProfileRegistered\s+-ProfileToolPath\s+\$ProfileTool') {
    throw "installer must not use elevated YuneWindowsProfileTool --state as the post-regsvr32 registration verifier."
}

Write-Host "Installer verifies durable YuneWindows machine registration after regsvr32."
