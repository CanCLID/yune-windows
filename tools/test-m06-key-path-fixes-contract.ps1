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
        'TryAcquireLoneShiftToggle',
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
        'IsShiftHookWindow',
        'PostMessageW\(old_window, WM_CLOSE'
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

$KeyUpBody = [regex]::Match(
    $Source,
    'STDMETHODIMP OnKeyUp\(ITfContext\* context, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?s:.*?)\n    \}').Value
if ($KeyUpBody -notmatch 'PerformLoneShiftToggle\(context\)') {
    throw "F5 OnKeyUp must route the lone-Shift toggle through PerformLoneShiftToggle."
}

# The double-toggle guard must live in the single toggle entry point, and it must
# be acquired only after the not-focused early-out so a no-op path cannot spend
# the guard and suppress a real toggle.
$PerformBody = [regex]::Match(
    $Source,
    'void PerformLoneShiftToggle\(ITfContext\* context\) \{(?s:.*?)\n    \}').Value
if ($PerformBody -notmatch 'TryAcquireLoneShiftToggle\(\)') {
    throw "F5 PerformLoneShiftToggle must use the shared double-toggle guard."
}
if ($PerformBody -notmatch '(?s)!focused_(?:.*?)TryAcquireLoneShiftToggle\(\)') {
    throw "F5 PerformLoneShiftToggle must check focus before spending the toggle guard."
}

Write-Host "M06 key-path source contract covers F1/F2b/F5/F6."
