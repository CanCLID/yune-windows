param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallerPath = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
if (-not (Test-Path -LiteralPath $UninstallerPath)) {
    throw "missing uninstaller script: $UninstallerPath"
}
if (-not (Test-Path -LiteralPath $SupportPath)) {
    throw "missing live-smoke support script: $SupportPath"
}

$Source = Get-Content -Raw -LiteralPath $UninstallerPath
$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

foreach ($Required in @(
        'function\s+Assert-YuneWindowsMachineRegistrationAbsent',
        'function\s+Clear-YuneWindowsMachineRegistrationResidue',
        'Get-YuneWindowsMachineResidueRegistryKeys',
        'machine registration remains after unregister'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "machine-registration cleanup support is missing required pattern: $Required"
    }
}

foreach ($Required in @(
        'Invoke-YuneWindowsRegsvr32(?s:.*?)-Operation\s+"regsvr32 unregistration"',
        'Clear-YuneWindowsMachineRegistrationResidue\s+-InstallDir\s+\$InstallRoot',
        'Assert-YuneWindowsMachineRegistrationAbsent\s+-InstallDir\s+\$InstallRoot'
    )) {
    if ($Source -notmatch $Required) {
        throw "uninstaller must clear and verify YuneWindows machine registration after regsvr32 /u: $Required"
    }
}

if ($Source -match 'Assert-YuneWindowsProfileUnregistered\s+-ProfileToolPath\s+\$ProfileTool') {
    throw "uninstaller must not use elevated YuneWindowsProfileTool --state as the post-unregister verifier."
}

$AssertIndex = $Source.IndexOf("Assert-YuneWindowsMachineRegistrationAbsent")
$RemoveIndex = $Source.IndexOf("Remove-YuneWindowsInstallDirectoryWithRetry -Path `$InstallRoot")
if ($AssertIndex -lt 0 -or $RemoveIndex -lt 0 -or $AssertIndex -gt $RemoveIndex) {
    throw "uninstaller must verify machine registration is absent before removing installed files"
}

Write-Host "Uninstaller verifies YuneWindows machine registration is absent after regsvr32 /u."
