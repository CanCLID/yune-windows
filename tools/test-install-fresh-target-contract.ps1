param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallerPath = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"
if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "missing installer script: $InstallerPath"
}

$Source = Get-Content -Raw -LiteralPath $InstallerPath

foreach ($Required in @(
        'function\s+Assert-YuneWindowsFreshInstallTarget',
        'Test-Path -LiteralPath \$InstallRoot',
        'install directory already exists',
        'Refusing to install over existing YuneWindows files'
    )) {
    if ($Source -notmatch $Required) {
        throw "installer must refuse an existing install directory before staging files: $Required"
    }
}

$Invocation = 'Assert-YuneWindowsFreshInstallTarget -InstallRoot $InstallRoot'
$InvocationIndex = $Source.IndexOf($Invocation)
$InstallStartedIndex = $Source.IndexOf('$InstallStarted = $false')
if ($InvocationIndex -lt 0 -or $InstallStartedIndex -lt 0) {
    throw "installer source is missing expected fresh-target control flow"
}
if ($InvocationIndex -gt $InstallStartedIndex) {
    throw "installer must reject an existing install target before staging and rollback tracking begin"
}

Write-Host "Installer refuses pre-existing install targets before staging files."
