param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HeaderPath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.h"
$WindowPath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.cpp"
$TsfPath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$ServerPath = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
foreach ($Path in @($HeaderPath, $WindowPath, $TsfPath, $ServerPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing source for paging contract: $Path"
    }
}

$Header = Get-Content -Raw -LiteralPath $HeaderPath
$Window = Get-Content -Raw -LiteralPath $WindowPath
$Tsf = Get-Content -Raw -LiteralPath $TsfPath
$Server = Get-Content -Raw -LiteralPath $ServerPath

foreach ($Required in @(
        'int page_index = 0',
        'CandidatePageCount',
        'CandidatePageStartIndex'
    )) {
    if ($Header -notmatch $Required) {
        throw "candidate window header missing paging pattern: $Required"
    }
}

foreach ($Required in @(
        'state_\.page_index',
        'CandidatePageStartIndex',
        'L"Page "',
        'DrawTextW\([^;]+page_label'
    )) {
    if ($Window -notmatch $Required) {
        throw "candidate window implementation missing paging pattern: $Required"
    }
}

foreach ($Required in @(
        'VK_NEXT',
        'VK_PRIOR',
        'candidate_page_index_',
        'PageCandidateWindow'
    )) {
    if ($Tsf -notmatch $Required) {
        throw "TSF source missing paging-key pattern: $Required"
    }
}

foreach ($Required in @(
        'candidate_list_begin',
        'candidate_list_next',
        'candidate_list_end'
    )) {
    if ($Server -notmatch $Required) {
        throw "server must expose a candidate list large enough for client-side paging: $Required"
    }
}

Write-Host "Candidate paging contract covers page state, indicators, keys, and candidate supply."
