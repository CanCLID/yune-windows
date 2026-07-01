param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HeaderPath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.h"
$SourcePath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.cpp"
$TsfPath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"

foreach ($Path in @($HeaderPath, $SourcePath, $TsfPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing language bar contract input: $Path"
    }
}

$Header = Get-Content -Raw -LiteralPath $HeaderPath
$WindowSource = Get-Content -Raw -LiteralPath $SourcePath
$TsfSource = Get-Content -Raw -LiteralPath $TsfPath

foreach ($Required in @(
        'enum class LanguageBarSegment',
        'struct LanguageBarState',
        'class LanguageBarWindow',
        'SetClickHandler',
        'LanguageBarClickHandler'
    )) {
    if ($Header -notmatch $Required) {
        throw "candidate window header is missing language bar API: $Required"
    }
}

foreach ($Required in @(
        'YuneWindowsLanguageBar',
        'WS_EX_NOACTIVATE',
        'WM_LBUTTONUP',
        'WM_NCHITTEST',
        'HTCLIENT',
        'LanguageBarWindow::Update',
        'LanguageBarWindow::Hide'
    )) {
    if ($WindowSource -notmatch $Required) {
        throw "language bar window implementation missing pattern: $Required"
    }
}

foreach ($Required in @(
        'language_bar_',
        'UpdateLanguageBar',
        'HandleLanguageBarClick',
        'LanguageBarSegment::AsciiMode',
        'LanguageBarSegment::FullShape',
        'LanguageBarSegment::OutputStandard',
        'LanguageBarSegment::Schema',
        'language_bar_\.Hide\(\)'
    )) {
    if ($TsfSource -notmatch $Required) {
        throw "TSF source is missing language bar lifecycle/click wiring: $Required"
    }
}

Write-Host "Language bar window is focus-scoped, native, and clickable."
