param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile([string]$RelativePath) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M11D contract input: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$Tsf = Read-RepoFile "src\tsf\yune_windows_tsf.cpp"
$Server = Read-RepoFile "src\server\yune_windows_server.cpp"
$Settings = Read-RepoFile "src\tools\yune_windows_settings.cpp"
$Core = Read-RepoFile "src\tsf\yune_windows_reliability_core.h"
$CoreSmoke = Read-RepoFile "src\tsf\yune_windows_reliability_smoke.cpp"
$Build = Read-RepoFile "tools\build-tsf-shell.ps1"
$Plan = Read-RepoFile "docs\plans\active\m11-activation-state-reliability.md"

foreach ($Required in @(
        'boot_id',
        'revision',
        'expect_boot_id',
        'expect_revision',
        'RequestRevisionConflict',
        'epoch_conflict',
        'revision_conflict',
        'MutationResponseJson',
        'PersistState\(const YuneState& state\)',
        'MoveFileExW',
        'MOVEFILE_REPLACE_EXISTING',
        'CommitStateMutation',
        'class StatePersistenceError',
        'catch \(const StatePersistenceError& error\)',
        'ErrorResponseJson\(error\.what\(\), "persist_failed"\)',
        '--test-persist-failure-once',
        'ConsumeTestPersistFailure',
        'test persistence failure injection is forbidden on the production pipe'
)) {
    Require-Text $Server $Required "server is missing M11D CAS/transaction pattern: $Required"
}
if ($Server -match 'error\.find\("IME state file"\)') {
    throw "server must classify persistence failures by type, not message text."
}
$PersistenceThrows = [regex]::Matches(
    $Server,
    'throw StatePersistenceError\(').Count
if ($PersistenceThrows -lt 5) {
    throw "every state-directory/open/write/flush/replace failure must use the typed persistence error."
}

foreach ($Required in @(
        'ExchangeOperationPipe',
        'FILE_FLAG_OVERLAPPED',
        'CompletePipeIoWithinDeadline',
        'CancelIoEx',
        'struct PipeCall',
        'PipeWorkerProc',
        'WaitForMultipleObjects',
        'GetOverlappedResult\(pipe, overlapped, &ignored, TRUE\)',
        'kMaxPipeWorkers = 4',
        'transport_unknown',
        'AppendStateExpectation',
        'state_\.present = false',
        'kFocusedServiceWatchdogIntervalMs = 250',
        'HandleFocusedServiceWatchdog',
        'IsCurrentFocusedTextService',
        'CachedToolbarOwnerMatchesForeground',
        'ReconcileLanguageBarVisibility',
        'focused_service_dispatcher_dead',
        'ShiftTokenArbiter',
        'ToggleParityIntent',
        'kPendingAsciiToggleDeadlineMs = 1500',
        'deadline_expired',
        'g_hook_shift_snapshot',
        'g_hook_shift_history_time',
        'g_hook_shift_history_consumed',
        'g_hook_shift_rejection_reason',
        'kShiftHookRepeatMessage',
        'kShiftHookModifiedMessage',
        'kShiftHookMouseMessage',
        'kShiftHookConsumedMessage',
        'ShiftHookRejectionMessage\(rejection\)',
        'ShiftHookRejectionReason\(message\)',
        'ShiftRejectionDisposition\(hook_rejection\)',
        'ShiftDetector::Sink',
        'ShiftDetector::Hook',
        'detector=',
        'rejected_repeat',
        'rejected_modified',
        'rejected_mouse_or_capture',
        'rejected_consumed',
        'focus_gained',
        'context_available=',
        'context_source=',
        'rejected_expired_intent',
        'response\.outcome == L"persist_failed"',
        'GetMessageTime\(\)',
        'g_published_focus_generation',
        'g_committed_focus_generation',
        'acknowledged_state_generation_',
        'PublishShiftHookDispatcherLocked',
        'shift_disposition',
        'shift_toggle_outcome',
        'utc_filetime=',
        'monotonic_ms=',
        'process_nonce=',
        'FILE_APPEND_DATA'
)) {
    Require-Text $Tsf $Required "TSF is missing M11D reliability pattern: $Required"
}
Require-Text $Tsf 'EvaluateToolbarEligibility' `
    "production toolbar reconciliation must call the tested eligibility evaluator."

$OperationQuery = [regex]::Match(
    $Tsf,
    'ServerResponse QueryServerOperation\((?s:.*?)\n\}').Value
if (-not $OperationQuery -or $OperationQuery -match 'CallNamedPipeW') {
    throw "M11D operation transport must not use unbounded CallNamedPipeW."
}
if ($Tsf -match 'WaitForSingleObject\(overlapped->hEvent, 1000\)' -or
    $Tsf -match 'CancelIo\(pipe\)') {
    throw "M11D pipe timeout must return on the STA deadline and drain owned I/O on the worker."
}

$LowLevelHook = [regex]::Match(
    $Tsf,
    'LRESULT CALLBACK LowLevelKeyboardProc\([^;]*\)\s*\{(?s:.*?)\n\}').Value
if (-not $LowLevelHook) {
    throw "M11D low-level hook implementation was not found."
}
foreach ($Forbidden in @('lock_guard', 'WriteStructuralEvent', 'new ', 'CallNamedPipeW', 'SendMessage')) {
    if ($LowLevelHook -match $Forbidden) {
        throw "M11D low-level hook must stay bounded and lock-free: $Forbidden"
    }
}
if ([regex]::Matches($LowLevelHook, 'PostMessageW').Count -ne 1) {
    throw "M11D low-level hook must post at most one terminal dispatcher message per callback path."
}
$HookRejectHelper = [regex]::Match(
    $Tsf,
    'void SetHookShiftRejectionIfNone\(ShiftRejectionReason reason\) \{(?s:.*?)\n\}').Value
if (-not $HookRejectHelper -or
    $HookRejectHelper -notmatch 'compare_exchange_strong') {
    throw "M11D hook rejection handoff must use bounded atomic state."
}
foreach ($Forbidden in @('lock_guard', 'WriteStructuralEvent', 'new ', 'PostMessage', 'SendMessage')) {
    if ($HookRejectHelper -match $Forbidden) {
        throw "M11D hook rejection helper must stay callback-safe: $Forbidden"
    }
}

$Activation = [regex]::Match(
    $Tsf,
    'bool ActivateFocusedTextService\(TextService\* service\) \{(?s:.*?)\n\}\r?\n\r?\nvoid DeactivateFocusedTextService').Value
if (-not $Activation -or
    $Activation -notmatch 'g_focused_text_service = service' -or
    $Activation -notmatch 'QueueSupersededFocus' -or
    $Activation -notmatch 'RetainOrphanedFocusReference') {
    throw "M11D focus activation must commit new identity and tolerate dead old dispatchers."
}
$QueueIndex = $Activation.IndexOf('QueueSupersededFocus')
$CommitIndex = $Activation.IndexOf('g_focused_text_service = service')
if ($QueueIndex -lt 0 -or $CommitIndex -lt 0 -or $QueueIndex -lt $CommitIndex) {
    throw "M11D must publish the new focus identity before best-effort old-apartment cleanup."
}

$PerformStart = $Tsf.IndexOf(
    'void PerformLoneShiftToggle(',
    [System.StringComparison]::Ordinal)
$PerformEnd = if ($PerformStart -ge 0) {
    $Tsf.IndexOf(
        'void HideLanguageBarForSupersededFocus()',
        $PerformStart,
        [System.StringComparison]::Ordinal)
}
else { -1 }
if ($PerformStart -lt 0 -or $PerformEnd -le $PerformStart) {
    throw "M11D lone-Shift terminal admission function was not found."
}
$PerformToggle = $Tsf.Substring($PerformStart, $PerformEnd - $PerformStart)
$ForegroundGuard = $PerformToggle.IndexOf(
    'CachedToolbarOwnerMatchesForeground',
    [System.StringComparison]::Ordinal)
$AcceptedDisposition = $PerformToggle.IndexOf(
    'detector, "accepted"',
    [System.StringComparison]::Ordinal)
$MutationQueue = $PerformToggle.IndexOf(
    'QueueAsciiToggle',
    [System.StringComparison]::Ordinal)
if ($ForegroundGuard -lt 0 -or $AcceptedDisposition -le $ForegroundGuard -or
    $MutationQueue -le $AcceptedDisposition -or
    $PerformToggle -notmatch
        'if \(detector == ShiftDetector::Sink\)\s*\{\s*ClearShiftState\(\)') {
    throw "M11D must record accepted only after current/foreground admission and preserve a pending sink report after hook-first acceptance."
}

$HandleStart = $Tsf.IndexOf(
    'void HandleDeferredLoneShiftToggle(',
    [System.StringComparison]::Ordinal)
$HandleEnd = if ($HandleStart -ge 0) {
    $Tsf.IndexOf(
        'void RecordShiftDisposition(',
        $HandleStart,
        [System.StringComparison]::Ordinal)
}
else { -1 }
if ($HandleStart -lt 0 -or $HandleEnd -le $HandleStart -or
    $Tsf.Substring($HandleStart, $HandleEnd - $HandleStart) -match
        'detector, "accepted"') {
    throw "M11D must not pre-record acceptance before the terminal current/foreground guard."
}
if ($Tsf -notmatch 'WriteStructuralEvent\("shift_parity_coalesced"' -or
    $Tsf -match 'RecordShiftDisposition\([^;]*"parity_coalesced"') {
    throw "M11D parity aggregation must not emit a second detector disposition for one report."
}

foreach ($Required in @('boot_id', 'revision', 'AppendStateExpectation')) {
    Require-Text $Settings $Required "settings client is missing M11D CAS field: $Required"
}
foreach ($Required in @(
        'SettingsPipeWorkerProc',
        'kMaxSettingsPipeWorkers = 2',
        'ClassifyMutationEnvelope',
        'kSettingsServerTimeoutMs = 750'
    )) {
    Require-Text $Settings $Required "settings client is missing bounded IPC/envelope pattern: $Required"
}

foreach ($Required in @(
        'class ShiftTokenArbiter',
        'class ToggleParityIntent',
        'EvaluateToolbarEligibility',
        'ToolbarEligibilityReasonName',
        'ShiftClaimDisposition::Duplicate',
        'generation != generation_'
    )) {
    Require-Text ($Core + $CoreSmoke) $Required "M11D reliability core/smoke is missing: $Required"
}
foreach ($Required in @(
        'YuneWindowsReliabilitySmoke.exe',
        'yune_windows_reliability_smoke.cpp'
    )) {
    Require-Text $Build ([regex]::Escape($Required)) "build is missing M11D smoke artifact: $Required"
}

foreach ($Required in @(
        'paced',
        'rapid burst',
        'revision',
        'foreground-owner',
        'dead dispatcher',
        'approval-gated installed'
    )) {
    Require-Text $Plan $Required "canonical M11 plan is missing reviewed semantic: $Required"
}

Write-Host "M11D activation, CAS, token, parity, and visibility contract passed."
