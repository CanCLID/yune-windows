param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallerPath = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$Source = Get-Content -Raw -LiteralPath $UninstallerPath

foreach ($Required in @(
        'function Test-YuneWindowsInstalledProfileToolAvailable',
        '$InstalledProfileToolAvailable = Test-YuneWindowsInstalledProfileToolAvailable -ProfileToolPath $ProfileTool',
        'if ($InstalledProfileToolAvailable -and (Test-Path -LiteralPath $TsfDll))',
        'Assert-YuneWindowsMachineRegistrationAbsent -InstallDir $InstallRoot',
        'Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot -LockedModulePath $TsfDll'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "uninstaller must support already-unregistered partial cleanup: $Required"
    }
}

$AvailabilityIndex = $Source.IndexOf('$InstalledProfileToolAvailable = Test-YuneWindowsInstalledProfileToolAvailable -ProfileToolPath $ProfileTool')
$DeactivationGateIndex = $Source.IndexOf('if ($InstalledProfileToolAvailable -and (Test-Path -LiteralPath $TsfDll))')
$AbsentCheckIndex = $Source.IndexOf('Assert-YuneWindowsMachineRegistrationAbsent -InstallDir $InstallRoot', $DeactivationGateIndex)
$RemoveIndex = $Source.IndexOf('Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot -LockedModulePath $TsfDll')

if ($AvailabilityIndex -lt 0 -or $DeactivationGateIndex -lt 0 -or
    $AbsentCheckIndex -lt 0 -or $RemoveIndex -lt 0) {
    throw "uninstaller source is missing expected already-unregistered partial cleanup ordering."
}
if ($AvailabilityIndex -gt $DeactivationGateIndex -or
    $DeactivationGateIndex -gt $AbsentCheckIndex -or
    $AbsentCheckIndex -gt $RemoveIndex) {
    throw "uninstaller must verify already-unregistered partial state before removing remaining files."
}

Write-Host "Uninstaller can remove already-unregistered partial install files after verifying registration is absent."
