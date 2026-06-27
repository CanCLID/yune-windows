param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallScript = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$Source = Get-Content -Raw -LiteralPath $UninstallScript

foreach ($Required in @(
        'function Remove-YuneWindowsInstallDirectoryWithRetry',
        '[int]$Attempts = 20',
        '[int]$DelayMilliseconds = 500',
        'Remove-Item -LiteralPath $Path -Recurse -Force',
        'Start-Sleep -Milliseconds $DelayMilliseconds',
        'Failed to remove YuneWindows install directory after $Attempts attempts',
        'function Get-YuneWindowsProcessesUsingModule',
        'function Stop-YuneWindowsTsfModuleHostProcesses',
        '$SafeHostProcessNames = @("ctfmon", "TextInputHost")',
        'Stop-YuneWindowsTsfModuleHostProcesses -TsfDllPath $LockedModulePath',
        'Locking module holders',
        'Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot -LockedModulePath $TsfDll'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "uninstall script is missing bounded install-directory removal retry pattern: $Required"
    }
}

if ($Source -match 'if \(-not \$KeepFiles -and \(Test-Path -LiteralPath \$InstallRoot\)\)\s*\{\s*Remove-Item -LiteralPath \$InstallRoot -Recurse -Force\s*\}') {
    throw "uninstall script still removes the install directory with a single unbounded Remove-Item call."
}

Write-Host "Uninstall retries transient install-directory removal failures before failing cleanup evidence."
