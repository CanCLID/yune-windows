param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallerPath = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"
if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "missing installer script: $InstallerPath"
}

$Source = Get-Content -Raw -LiteralPath $InstallerPath

foreach ($Required in @(
        'function\s+Invoke-YuneWindowsInstallRollback',
        'function\s+Assert-YuneWindowsProfileUnregisteredForRollback',
        'Assert-JsonBooleanProperty\s+-Object\s+\$ProfileState\s+-Name\s+"registered"\s+-Expected\s+\$false',
        'Assert-JsonBooleanProperty\s+-Object\s+\$ProfileState\s+-Name\s+"active"\s+-Expected\s+\$false',
        'Invoke-YuneWindowsRegsvr32',
        '"/u"',
        '"/s"',
        'Assert-YuneWindowsProfileUnregisteredForRollback\s+-ProfileToolPath',
        'Remove-Item\s+-LiteralPath\s+\$InstallRoot\s+-Recurse\s+-Force',
        'rollback completed',
        'rollback failed'
    )) {
    if ($Source -notmatch $Required) {
        throw "installer must roll back copied files and TSF registration if approved install fails after staging begins: $Required"
    }
}

$TryIndex = $Source.IndexOf('$InstallStarted = $false')
$RollbackCallIndex = $Source.IndexOf('$Rollback = Invoke-YuneWindowsInstallRollback')
$SuccessIndex = $Source.IndexOf('Write-Host "Installed and registered Yune Windows IME')
if ($TryIndex -lt 0 -or $RollbackCallIndex -lt 0 -or $SuccessIndex -lt 0) {
    throw "installer source is missing expected rollback control flow"
}
if ($RollbackCallIndex -lt $TryIndex -or $RollbackCallIndex -gt $SuccessIndex) {
    throw "installer rollback must be part of the install attempt before the success message"
}

Write-Host "Installer has rollback behavior for failed approved install attempts."
