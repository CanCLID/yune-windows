param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HeaderPath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.h"
$SourcePath = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.cpp"
$SmokePath = Join-Path $RepoRoot "src\candidate_window\yune_windows_language_bar_smoke.cpp"
$TsfPath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"

foreach ($Path in @($HeaderPath, $SourcePath, $SmokePath, $TsfPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing language bar contract input: $Path"
    }
}

$Header = Get-Content -Raw -LiteralPath $HeaderPath
$WindowSource = Get-Content -Raw -LiteralPath $SourcePath
$SmokeSource = Get-Content -Raw -LiteralPath $SmokePath
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
        '--supersession-child',
        'CreateProcessW',
        'CREATE_SUSPENDED',
        'AllowSetForegroundWindow',
        'RegisterWindowMessageW',
        'RunCrossProcessSupersessionSmoke',
        'set_ignore_activate_app_for_testing\(true\)',
        'activate_app_bypass_count_for_testing',
        'LanguageBarWindowsForProcess',
        'WM_DPICHANGED',
        'WM_CANCELMODE',
        'DestroyWindow\(bar_hwnd\)',
        'render_count_for_testing\(\) != 0',
        'render_count_for_testing\(\) != 1'
    )) {
    if ($SmokeSource -notmatch $Required) {
        throw "language bar smoke is missing topology/drag coverage: $Required"
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
        'YuneWindows\.ToolbarSuperseded\.v1',
        'RegisterWindowMessageW',
        'SetTimer',
        'KillTimer',
        'WM_TIMER',
        'WM_ACTIVATEAPP',
        'WM_CANCELMODE',
        'WM_CAPTURECHANGED',
        'WM_NCDESTROY',
        'RootOwnerWindow',
        'GetWindow\(hwnd_, GW_OWNER\)',
        'ForegroundMatchesOwner',
        'ClaimVisibleToolbar',
        'ReleaseVisibleToolbar',
        'QueueRender',
        'FinishPointerInteraction',
        'HideForSupersededFocus',
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
        'language_bar_\.Hide\(\)',
        'thread_mgr_->GetFocus',
        'document_mgr->GetTop',
        'last_toolbar_owner_',
        'ActivateFocusedTextService\(this\)',
        'DeactivateFocusedTextService\(this\)',
        'g_focused_text_service != service',
        'PrepareFocusedServiceActivation',
        'QueueSupersededFocus',
        'FocusedServiceWindowProc',
        'contextless_update',
        'else if \(!contextless_update\)'
    )) {
    if ($TsfSource -notmatch $Required) {
        throw "TSF source is missing language bar lifecycle/click wiring: $Required"
    }
}

$MoveBody = [regex]::Match(
    $WindowSource,
    'void LanguageBarWindow::ContinuePointerInteraction\(POINT client_point\) \{(?s:.*?)\n\}').Value
if (-not $MoveBody -or $MoveBody -notmatch 'SetWindowPos') {
    throw "language bar drag movement must move the existing HWND with SetWindowPos."
}
foreach ($Forbidden in @('(?m)^\s*Render\s*\(', 'PresentLanguageBar', 'BeginDraw', 'Commit\(')) {
    if ($MoveBody -match $Forbidden) {
        throw "language bar drag movement must not render or present: $Forbidden"
    }
}

Write-Host "Language bar window is focus-scoped, native, D2D-rendered, draggable, and clickable."
