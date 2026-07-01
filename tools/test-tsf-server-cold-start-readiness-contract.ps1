$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $TsfSource

if ($Source -notmatch 'constexpr\s+DWORD\s+kServerLaunchReadyWaitMs\s*=\s*(?<value>\d+)\s*;') {
    throw "TSF source must define kServerLaunchReadyWaitMs as a bounded constant."
}

$ReadyWaitMs = [int]$Matches["value"]
if ($ReadyWaitMs -lt 10000) {
    throw "TSF server launch readiness wait must cover measured cold Yune startup; expected at least 10000ms, got $ReadyWaitMs."
}

if ($ReadyWaitMs -ge 180000) {
    throw "TSF server launch readiness wait must stay below the diagnostic 180-second readiness window, got $ReadyWaitMs."
}

if ($Source -notmatch 'WaitForSharedServerPipe\(kServerLaunchReadyWaitMs\)') {
    throw "TSF launch path must use kServerLaunchReadyWaitMs for the post-CreateProcess readiness probe."
}

Write-Host "TSF server launch readiness wait covers cold Yune startup without using the diagnostic readiness window."
