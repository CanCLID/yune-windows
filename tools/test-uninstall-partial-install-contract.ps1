param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallerPath = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
if (-not (Test-Path -LiteralPath $UninstallerPath)) {
    throw "missing uninstaller script: $UninstallerPath"
}

$Source = Get-Content -Raw -LiteralPath $UninstallerPath

foreach ($Required in @(
        'function\s+Assert-YuneWindowsUninstallPreconditions',
        '\(Test-Path -LiteralPath \$ProfileToolPath\)\s+-and\s+-not\s+\(Test-Path -LiteralPath \$TsfDllPath\)',
        'YuneWindowsTSF\.dll is missing',
        'refusing to remove installed files before TSF profile unregistration can be verified'
    )) {
    if ($Source -notmatch $Required) {
        throw "uninstaller must reject partial installs that still have YuneWindowsProfileTool.exe but are missing YuneWindowsTSF.dll: $Required"
    }
}

$Invocation = 'Assert-YuneWindowsUninstallPreconditions -TsfDllPath $TsfDll -ProfileToolPath $ProfileTool'
if ($Source -notmatch [regex]::Escape($Invocation)) {
    throw "uninstaller must run partial-install preconditions before optional unregister/removal"
}

$InvocationIndex = $Source.IndexOf($Invocation)
$UnregisterGateIndex = $Source.IndexOf('if (Test-Path -LiteralPath $TsfDll)')
$RemoveIndex = $Source.IndexOf('Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot')
if ($InvocationIndex -lt 0 -or $UnregisterGateIndex -lt 0 -or $RemoveIndex -lt 0) {
    throw "uninstaller source is missing expected unregister/removal gates"
}
if ($InvocationIndex -gt $UnregisterGateIndex -or $InvocationIndex -gt $RemoveIndex) {
    throw "uninstaller must reject partial installs before it can skip unregister or remove installed files"
}

Write-Host "Uninstaller rejects partial installs that cannot verify TSF profile unregistration."
