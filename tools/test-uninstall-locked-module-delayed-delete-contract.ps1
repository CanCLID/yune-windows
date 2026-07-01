param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallScript = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$Source = Get-Content -Raw -LiteralPath $UninstallScript

foreach ($Required in @(
        'EntryPoint = "MoveFileExW"',
        'IntPtr newFileName',
        '[IntPtr]::Zero',
        '$MOVEFILE_DELAY_UNTIL_REBOOT'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "uninstaller delayed-delete P/Invoke must use explicit MoveFileExW null-target pattern: $Required"
    }
}

$RemovalStart = $Source.IndexOf('if (-not $KeepFiles -and (Test-Path -LiteralPath $InstallRoot))')
if ($RemovalStart -lt 0) {
    throw "uninstaller install-directory removal block was not found."
}
$RemovalBlock = $Source.Substring($RemovalStart)

foreach ($Required in @(
        'Stop-YuneWindowsTsfModuleHostProcesses -TsfDllPath $TsfDll',
        '$CleanupResult.module_holders_before_remove =',
        'Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDll',
        'if ($CleanupResult.module_holders_before_remove.Count -gt 0)',
        '$RemovalError = "install directory contains locked YuneWindowsTSF.dll module holders',
        'Schedule-YuneWindowsDelayedDelete -InstallRoot $InstallRoot',
        'Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot -LockedModulePath $TsfDll'
    )) {
    if ($RemovalBlock -notmatch [regex]::Escape($Required)) {
        throw "uninstaller must schedule delayed delete before normal removal touches a locked TSF DLL: $Required"
    }
}

$HolderIndex = $RemovalBlock.IndexOf('if ($CleanupResult.module_holders_before_remove.Count -gt 0)')
$ScheduleIndex = $RemovalBlock.IndexOf('Schedule-YuneWindowsDelayedDelete -InstallRoot $InstallRoot')
$RemoveIndex = $RemovalBlock.IndexOf('Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot -LockedModulePath $TsfDll')
if ($HolderIndex -lt 0 -or $ScheduleIndex -lt 0 -or $RemoveIndex -lt 0 -or
    $HolderIndex -gt $ScheduleIndex -or $ScheduleIndex -gt $RemoveIndex) {
    throw "uninstaller must schedule delayed delete for known locked TSF module holders before attempting normal Remove-Item cleanup."
}

Write-Host "Uninstaller schedules delayed delete before touching a known locked TSF DLL."
