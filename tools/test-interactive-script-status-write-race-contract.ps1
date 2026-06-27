param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$Source = Get-Content -Raw -LiteralPath $SupportPath

foreach ($Required in @(
        '$InteractiveStatusReadErrors',
        'catch {',
        '$InteractiveStatusReadErrors.Add($_.Exception.Message)',
        'Start-Sleep -Milliseconds 250',
        'timed out waiting for valid interactive child status',
        '$null -eq $Status')) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "interactive script status reader must tolerate transient empty or partial status files: $Required"
    }
}

$LoopIndex = $Source.IndexOf('$InteractiveStatusReadErrors', [System.StringComparison]::Ordinal)
$AssertIndex = $Source.IndexOf('Assert-YuneWindowsInteractiveScriptResult', $LoopIndex, [System.StringComparison]::Ordinal)
$TimeoutIndex = $Source.IndexOf('timed out waiting for valid interactive child status', [System.StringComparison]::Ordinal)
if ($LoopIndex -lt 0 -or $AssertIndex -lt 0 -or $TimeoutIndex -lt 0) {
    throw "interactive script status reader is missing expected retry structure."
}
if ($LoopIndex -gt $AssertIndex -or $AssertIndex -gt $TimeoutIndex) {
    throw "interactive script status reader must retry status parsing until timeout."
}

Write-Host "Interactive script status reader tolerates transient empty status files."
