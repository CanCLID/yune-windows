param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSourcePath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSourcePath -PathType Leaf)) {
    throw "missing TSF source: $TsfSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $TsfSourcePath

foreach ($Required in @(
        'std::wstring PunctuationInput\(WPARAM key,\s*bool shift\)',
        'bool IsPunctuationKey\(WPARAM key,\s*bool shift\)',
        'bool IsShiftPressed\(\)',
        'ShouldHandleKeyDown\(key,\s*shift_pressed\)',
        'CommitCompositionForPunctuation\(context,\s*key,\s*shift_pressed\)'
    )) {
    if ($Source -notmatch $Required) {
        throw "F1 shifted punctuation contract missing pattern: $Required"
    }
}

foreach ($Required in @(
        'case VK_OEM_2:\s*return shift \? L"\?" : L"/";',
        'case VK_OEM_MINUS:\s*return shift \? L"_" : L"-";',
        'case VK_OEM_PLUS:\s*return shift \? L"\+" : L"=";',
        'case L''1'':\s*return shift \? L"!" : std::wstring\{\};',
        'case L''0'':\s*return shift \? L"\)" : std::wstring\{\};'
    )) {
    if ($Source -notmatch $Required) {
        throw "F1 shifted punctuation map missing pattern: $Required"
    }
}

$PagingBlock = [regex]::Match(
    $Source,
    'if \(!shift_pressed &&(?s:.*?)key == VK_OEM_MINUS(?s:.*?)key == VK_OEM_PLUS(?s:.*?)PageComposition\(context, page_delta\);(?s:.*?)return S_OK;').Value
if ([string]::IsNullOrWhiteSpace($PagingBlock) -or
    $PagingBlock -notmatch '!shift_pressed') {
    throw "F1 paging shortcuts for -/= must be unshifted-only so Shift+-/= reach punctuation."
}

foreach ($Required in @(
        'bool CommitRawBuffer\(ITfContext\* context\)',
        'if \(key == VK_RETURN && IsComposing\(\)\)',
        'CommitRawBuffer\(context\)',
        'if \(key == VK_SPACE && IsComposing\(\)\)',
        'ComposePayload\("compose-commit-raw"\)',
        'ComposePayload\("compose-commit"\)'
    )) {
    if ($Source -notmatch $Required) {
        throw "F6 raw Enter contract missing pattern: $Required"
    }
}

if ($Source -notmatch 'constexpr\s+DWORD\s+kServerKeyPathQueryTimeoutMs\s*=\s*(?<timeout>\d+)\s*;') {
    throw "F2b must define a capped synchronous key-path query timeout."
}
$KeyTimeout = [int]$Matches["timeout"]
if ($KeyTimeout -gt 500) {
    throw "F2b key-path query timeout must be capped at <= 500ms, got $KeyTimeout."
}

foreach ($Required in @(
        'std::atomic<bool> g_server_warmup_inflight',
        'RequestSharedServerWarmupAsync',
        'CreateThread',
        'DllAddRef\(\)',
        'DllRelease\(\)',
        'QueryServer\((?s:.*?)input,\s*commit,\s*RefreshStateMode::ExistingServerOnly,\s*kServerKeyPathQueryTimeoutMs\)',
        'RefreshStateFromServer\(nullptr,\s*RefreshStateMode::ExistingServerOnly\);(?s:.*?)RequestSharedServerWarmupAsync\(\);'
    )) {
    if ($Source -notmatch $Required) {
        throw "F2b async warm-up/no-launch key path missing pattern: $Required"
    }
}

foreach ($Required in @(
        'WH_KEYBOARD_LL',
        'SetWindowsHookExW',
        'CallNextHookEx',
        'PostMessageW',
        'WM_APP',
        'g_focused_text_service',
        'ShiftTokenArbiter',
        'ToggleParityIntent',
        'g_shift_sequence',
        'ActivateFocusedTextService\(this\)',
        'DeactivateFocusedTextService\(this\)',
        'g_focused_text_service != service',
        'kFocusedServiceSupersededMessage',
        'PrepareFocusedServiceActivation',
        'QueueSupersededFocus',
        'FocusedServiceGeneration',
        'pending_focused_service_handoffs_',
        'pending_focused_service_handoffs_\.push_back',
        'DetachFocusedServiceWindow',
        'PostMessageW\(dispatcher, kFocusedServiceSupersededMessage',
        'g_shift_hook_dispatcher',
        'PublishShiftHookDispatcherLocked',
        'g_hook_shift_snapshot',
        'g_hook_shift_history_time',
        'g_hook_shift_history_consumed',
        'g_published_focus_generation',
        'g_committed_focus_generation',
        'IsFocusedServiceWindow\(dispatcher, dispatcher_thread, service\)',
        'dispatch_message =',
        'kShiftHookToggleMessage',
        'ShiftHookRejectionMessage\(rejection\)',
        'target, dispatch_message'
    )) {
    if ($Source -notmatch $Required) {
        throw "F5 low-level Shift hook contract missing pattern: $Required"
    }
}

$ActivateFocusedBody = [regex]::Match(
    $Source,
    'bool ActivateFocusedTextService\(TextService\* service\) \{(?s:.*?)\n\}\r?\n\r?\nvoid DeactivateFocusedTextService').Value
if (-not $ActivateFocusedBody -or
    $ActivateFocusedBody -match 'old_service->Release\(\)' -or
    $ActivateFocusedBody -match 'SendNotifyMessageW') {
    throw "focused-service activation must transfer the old reference to its apartment dispatcher."
}
if ($Source -match 'SendNotifyMessageW\(dispatcher, kFocusedServiceSupersededMessage') {
    throw "focused-service handoff must not synchronously re-enter its apartment dispatcher."
}

$HookSnapshotIndex = $Source.IndexOf('g_hook_shift_snapshot.store(')
$HookDownIndex = -1
if ($HookSnapshotIndex -ge 0) {
    $HookDownIndex = $Source.IndexOf(
        'g_hook_shift_down.store(true, std::memory_order_release)',
        $HookSnapshotIndex)
}
if ($HookSnapshotIndex -lt 0 -or $HookDownIndex -lt $HookSnapshotIndex) {
    throw "F5 low-level hook must publish the coherent token/generation snapshot before Shift-down."
}

$KeyUpBody = [regex]::Match(
    $Source,
    'STDMETHODIMP OnKeyUp\(ITfContext\* context, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?s:.*?)\n    \}').Value
if ($KeyUpBody -notmatch 'HandleDeferredLoneShiftToggle' -or
    $KeyUpBody -notmatch 'shift_token_') {
    throw "F5 OnKeyUp must route the lone-Shift token through the shared arbiter."
}

# M11D supersedes the time guard with a physical token/generation arbiter so a
# legitimate fast second press is not discarded.
$PerformBody = [regex]::Match(
    $Source,
    'void PerformLoneShiftToggle\(unsigned long long token,\s*unsigned long long generation,\s*ShiftDetector detector,\s*ITfContext\* context\) \{(?s:.*?)\n    \}').Value
if (-not $PerformBody -or
    $PerformBody -notmatch 'IsCurrentFocusedTextService' -or
    $PerformBody -notmatch 'CachedToolbarOwnerMatchesForeground') {
    throw "F5 lone-Shift dispatch must fail closed on current generation and foreground owner."
}
if ($Source -match 'kLoneShiftDoubleToggleGuardMs|TryAcquireLoneShiftToggle|g_last_lone_shift_toggle_ms') {
    throw "F5 lone-Shift dispatch must not retain the retired time-based guard."
}

Write-Host "M06 key-path source contract covers F1/F2b/F5/F6."
