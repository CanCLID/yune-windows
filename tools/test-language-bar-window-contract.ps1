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
        'WS_EX_NOREDIRECTIONBITMAP',
        'ModuleScopedClassName',
        'ModuleHandleFromAddress',
        'LanguageBarClassName\(\)\.c_str\(\)',
        'CandidateWindowClassName\(\)\.c_str\(\)',
        'D2D1CreateFactory',
        'DWriteCreateFactory',
        'DCompositionCreateDevice',
        'CreateTargetForHwnd',
        'D2D1_BITMAP_OPTIONS_CANNOT_DRAW',
        'D2DERR_RECREATE_TARGET',
        'DXGI_ERROR_DEVICE_REMOVED',
        'WM_DPICHANGED',
        'TrackMouseEvent',
        'TME_LEAVE',
        'SetCapture',
        'ReleaseCapture',
        'kLanguageBarDragThreshold',
        'SWP_NOACTIVATE',
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

foreach ($Forbidden in @(
        'WS_EX_LAYERED',
        'UpdateLayeredWindow'
    )) {
    if ($WindowSource -match $Forbidden) {
        throw "language bar window must use the DComp model, not the old ULW/layered path: $Forbidden"
    }
}

if ($WindowSource -match 'HTCAPTION') {
    throw "language bar drag must not use HTCAPTION because it can activate the host window."
}

foreach ($Required in @(
        'language_bar_',
        'SetPositionChangedHandler',
        'UpdateLanguageBar',
        'HandleLanguageBarClick',
        'HandleLanguageBarPositionChanged',
        'op=set-toolbar-position',
        'LanguageBarSegment::AsciiMode',
        'LanguageBarSegment::FullShape',
        'LanguageBarSegment::OutputStandard',
        'LanguageBarSegment::Schema',
        'LanguageBarSegment::Settings',
        'LaunchOrFocusSettings',
        'YuneWindowsSettings\.exe',
        'language_bar_\.Hide\(\)'
    )) {
    if ($TsfSource -notmatch $Required) {
        throw "TSF source is missing language bar lifecycle/click wiring: $Required"
    }
}

Write-Host "Language bar window is focus-scoped, native, D2D-rendered, draggable, and clickable."
