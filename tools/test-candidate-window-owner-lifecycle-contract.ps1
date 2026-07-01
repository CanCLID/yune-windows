param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HeaderPath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.h"
$WindowPath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.cpp"
$TsfPath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
foreach ($Path in @($HeaderPath, $WindowPath, $TsfPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing source for owner lifecycle contract: $Path"
    }
}

$Header = Get-Content -Raw -LiteralPath $HeaderPath
$Window = Get-Content -Raw -LiteralPath $WindowPath
$Tsf = Get-Content -Raw -LiteralPath $TsfPath

foreach ($Required in @(
        'HWND owner = nullptr',
        'bool EnsureCreated\(HWND owner\)',
        'HWND owner_ = nullptr'
    )) {
    if ($Header -notmatch $Required) {
        throw "candidate window header missing owner pattern: $Required"
    }
}

foreach ($Required in @(
        'CreateWindowExW\([^;]+owner',
        'GWLP_HWNDPARENT',
        'GetForegroundWindow\(\)',
        'ForegroundMatchesOwner',
        'DestroyWindow\(hwnd_\)'
    )) {
    if ($Window -notmatch $Required) {
        throw "candidate window implementation missing lifecycle pattern: $Required"
    }
}

foreach ($Required in @(
        'state\.owner =',
        'candidate_window_\.Hide\(\)'
    )) {
    if ($Tsf -notmatch $Required) {
        throw "TSF source missing owner/hide pattern: $Required"
    }
}

Write-Host "Candidate window has owner-window and no-orphan lifecycle guards."
