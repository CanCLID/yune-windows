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
        'g_language_bar_class_filter',
        'YuneWindows\.ToolbarSuperseded\.v1\.Smoke',
        'WM_DPICHANGED',
        'WM_CANCELMODE',
        'DestroyWindow\(bar_hwnd\)',
        'stale cached toolbar position was shown before refresh',
        'cross-process stale state moved or exposed parent toolbar',
        'cross-process supersession did not require a fresh state',
        'same-process supersession did not require a fresh state',
        'RequiresForegroundStateRefresh',
        'AcknowledgeForegroundStateRefresh',
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
        'YuneWindows\.ToolbarSuperseded\.v1\.Smoke',
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
        'HideForForegroundLoss',
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

$SupersessionHandler = [regex]::Match(
    $WindowSource,
    'if \(message == ToolbarSupersededMessage\(\)\) \{(?s:.*?)\n    \}').Value
if (-not $SupersessionHandler -or
    $SupersessionHandler -notmatch 'WindowOwnerMatchesForeground\(claimant\)' -or
    $SupersessionHandler -notmatch 'HideForSupersededFocus\(\)') {
    throw "validated cross-process supersession must latch a refresh before re-show."
}

$SupersessionHideBody = [regex]::Match(
    $WindowSource,
    'void LanguageBarWindow::HideForSupersededFocus\(\) \{(?s:.*?)\n\}').Value
if (-not $SupersessionHideBody -or
    $SupersessionHideBody -notmatch 'HideForForegroundLoss\(\)') {
    throw "same-process and focused-service supersession must latch a refresh before re-show."
}

$UpdateBody = [regex]::Match(
    $WindowSource,
    'bool LanguageBarWindow::Update\(const LanguageBarState& state, bool show\) \{(?s:.*?)\n\}').Value
if (-not $UpdateBody -or
    $UpdateBody -notmatch 'if \(!ForegroundMatchesOwner\(\)\) \{\s*HideForForegroundLoss\(\);') {
    throw "foreground-mismatched updates must latch a refresh before re-show."
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
        'else if \(!contextless_update\)',
        'ForegroundRootBelongsToCurrentProcess'
    )) {
    if ($TsfSource -notmatch $Required) {
        throw "TSF source is missing language bar lifecycle/click wiring: $Required"
    }
}

$WatchdogBody = [regex]::Match(
    $TsfSource,
    'void HandleFocusedServiceWatchdog\(HWND dispatcher\) \{(?s:.*?)\n    \}').Value
if (-not $WatchdogBody -or
    $WatchdogBody -notmatch 'if \(language_bar_\.RequiresForegroundStateRefresh\(\)\) \{(?s:.*?)UpdateLanguageBar\(nullptr\);(?s:.*?)if \(!CachedToolbarOwnerMatchesForeground\(\)\) \{(?s:.*?)if \(!ForegroundRootBelongsToCurrentProcess\(\) \|\|\s*StateAcknowledgedForCurrentGeneration\(\)\) \{(?s:.*?)language_bar_\.Hide\(\);(?s:.*?)return;(?s:.*?)RefreshStateFromServer\(nullptr,\s*RefreshStateMode::ExistingServerOnly\)' -or
    $WatchdogBody -notmatch 'RefreshStateFromServer\(nullptr,\s*RefreshStateMode::ExistingServerOnly\);\s*if \(language_bar_\.RequiresForegroundStateRefresh\(\)\) \{\s*return;' -or
    $WatchdogBody -match 'RefreshStateMode::AllowLaunch') {
    throw "focused-service watchdog must refresh an existing server and fail closed before foreground re-show."
}

$ForegroundProcessBody = [regex]::Match(
    $TsfSource,
    'bool ForegroundRootBelongsToCurrentProcess\(\) const \{(?s:.*?)\n    \}').Value
if (-not $ForegroundProcessBody -or
    $ForegroundProcessBody -notmatch 'GetForegroundWindow\(\)' -or
    $ForegroundProcessBody -notmatch 'GetAncestor\(foreground, GA_ROOTOWNER\)' -or
    $ForegroundProcessBody -notmatch 'GetWindowThreadProcessId\(foreground_root,\s*&foreground_process_id\)' -or
    $ForegroundProcessBody -notmatch 'foreground_process_id == GetCurrentProcessId\(\)') {
    throw "foreground retry discrimination must compare the foreground root PID with the current process."
}

$RefreshBody = [regex]::Match(
    $TsfSource,
    'void RefreshStateFromServer\((?s:.*?)\n    \}').Value
foreach ($Required in @(
        'mode == RefreshStateMode::ExistingServerOnly',
        'RequiresForegroundStateRefresh\(\)',
        'CachedToolbarOwnerMatchesForeground\(\)',
        'AcknowledgeForegroundStateRefresh\(\)',
        'UpdateLanguageBar\(context\)'
    )) {
    if (-not $RefreshBody -or $RefreshBody -notmatch $Required) {
        throw "state refresh does not gate foreground toolbar reacquisition: $Required"
    }
}
if ($RefreshBody -notmatch 'acknowledged_state_generation_ = 0;(?s:.*?)QueryOperation\("op=get-state\\n\.\\n", context, mode, timeout_ms\);(?s:.*?)if \(mode == RefreshStateMode::ExistingServerOnly &&\s*StateAcknowledgedForCurrentGeneration\(\) &&\s*language_bar_\.RequiresForegroundStateRefresh\(\) &&\s*CachedToolbarOwnerMatchesForeground\(\)\) \{(?s:.*?)language_bar_\.AcknowledgeForegroundStateRefresh\(\);\s*UpdateLanguageBar\(context\);') {
    throw "foreground reacquisition must remain closed until the non-launching query is acknowledged, then apply only the fresh state."
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
