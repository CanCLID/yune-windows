param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TestWindowScript = Join-Path $RepoRoot "tools\dev\dev-test-window.ps1"
$ReloadTsfScript = Join-Path $RepoRoot "tools\dev\dev-reload-tsf.ps1"

foreach ($Path in @($TestWindowScript, $ReloadTsfScript)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing script for dev test-window state contract: $Path"
    }
}

$TestWindowSource = Get-Content -Raw -LiteralPath $TestWindowScript
$ReloadTsfSource = Get-Content -Raw -LiteralPath $ReloadTsfScript

foreach ($Required in @(
        'process_path',
        'process_start_time',
        'launched_at',
        'test_file'
    )) {
    if ($TestWindowSource -notmatch $Required) {
        throw "dev-test-window.ps1 must record $Required in its state file."
    }
}

foreach ($Required in @(
        'process_path',
        'process_start_time',
        'launched_at',
        'Get-YuneWindowsDevOwnedTestProcess',
        'StartTime',
        'TotalSeconds',
        'Resolve-YuneWindowsDevFullPath'
    )) {
    if ($ReloadTsfSource -notmatch $Required) {
        throw "dev-reload-tsf.ps1 must validate dev-owned process state with pattern: $Required"
    }
}

if ($ReloadTsfSource -match 'function Get-YuneWindowsDevOwnedTestProcessId') {
    throw "dev-reload-tsf.ps1 should return a validated process object, not only a PID."
}

Write-Host "Dev test-window state contract requires path and start-time validation."
