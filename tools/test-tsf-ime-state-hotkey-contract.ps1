param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSourcePath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSourcePath -PathType Leaf)) {
    throw "missing TSF source: $TsfSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $TsfSourcePath

foreach ($Required in @(
        'struct ImeState',
        'QueryServerOperation',
        'ReconcileState',
        'RefreshStateFromServer',
        'UpdateInputModeCompartment',
        'op=get-state',
        'op=set-option',
        'op=select-schema',
        'state_\.ascii_mode',
        'shift_down_',
        'shift_consumed_',
        'VK_SHIFT',
        'OnPreservedKey',
        'Ctrl\+Shift\+2',
        'Ctrl\+Shift\+3',
        'CommitOrClearCompositionBeforeStateChange',
        'ClearShiftState',
        'CancelLoneShiftToggle',
        'IsMouseButtonDown',
        'kKeyWasDownMask',
        'RefreshStateMode::ExistingServerOnly'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF IME state/hotkey contract missing pattern: $Required"
    }
}

$ShouldHandleStart = $Source.IndexOf("bool ShouldHandleKeyDown")
$ShouldHandleEnd = $Source.IndexOf("bool CommitText", $ShouldHandleStart)
if ($ShouldHandleStart -lt 0 -or $ShouldHandleEnd -le $ShouldHandleStart) {
    throw "could not locate ShouldHandleKeyDown body"
}
$ShouldHandle = $Source.Substring($ShouldHandleStart, $ShouldHandleEnd - $ShouldHandleStart)
if ($ShouldHandle -notmatch 'ascii_mode(?s:.*?)return false') {
    throw "ShouldHandleKeyDown must bypass normal ASCII input when ascii_mode is on."
}

$ActivateIndex = $Source.IndexOf("STDMETHODIMP ActivateEx")
$DeactivateIndex = $Source.IndexOf("STDMETHODIMP Deactivate", $ActivateIndex)
if ($ActivateIndex -lt 0 -or $DeactivateIndex -le $ActivateIndex) {
    throw "could not locate ActivateEx body"
}
$ActivateBody = $Source.Substring($ActivateIndex, $DeactivateIndex - $ActivateIndex)
if ($ActivateBody -notmatch 'RefreshStateFromServer\(nullptr,\s*RefreshStateMode::ExistingServerOnly\)') {
    throw "ActivateEx must refresh state only from an already-running server and must not launch/wait on focus activation."
}

$FocusIndex = $Source.IndexOf("STDMETHODIMP OnSetFocus")
$TestKeyDownIndex = $Source.IndexOf("STDMETHODIMP OnTestKeyDown", $FocusIndex)
if ($FocusIndex -lt 0 -or $TestKeyDownIndex -le $FocusIndex) {
    throw "could not locate OnSetFocus body"
}
$FocusBody = $Source.Substring($FocusIndex, $TestKeyDownIndex - $FocusIndex)
if ($FocusBody -notmatch 'RefreshStateFromServer\(nullptr,\s*RefreshStateMode::ExistingServerOnly\)') {
    throw "OnSetFocus(TRUE) must refresh state only from an already-running server and must not launch/wait on focus."
}
if ($FocusBody -notmatch 'ClearShiftState\(\)') {
    throw "OnSetFocus(FALSE) must clear stale lone-Shift state."
}

$DeactivateBody = $Source.Substring($DeactivateIndex, $FocusIndex - $DeactivateIndex)
if ($DeactivateBody -notmatch 'ClearShiftState\(\)') {
    throw "Deactivate must clear stale lone-Shift state."
}

$OnKeyDownIndex = $Source.IndexOf("STDMETHODIMP OnKeyDown")
$OnKeyUpIndex = $Source.IndexOf("STDMETHODIMP OnKeyUp")
if ($OnKeyDownIndex -lt 0 -or $OnKeyUpIndex -le $OnKeyDownIndex) {
    throw "could not locate key down/up bodies"
}
$KeyDownBody = $Source.Substring($OnKeyDownIndex, $OnKeyUpIndex - $OnKeyDownIndex)
if ($KeyDownBody -notmatch 'kKeyWasDownMask') {
    throw "OnKeyDown must not re-arm lone-Shift state on autorepeat."
}
if ($KeyDownBody -notmatch 'IsShortcutModifierDown\(\)') {
    throw "OnKeyDown must mark Ctrl/Alt/Win+Shift as consumed so preserved chords do not also toggle ascii_mode."
}

$PreservedIndex = $Source.IndexOf("STDMETHODIMP OnPreservedKey")
$PrivateIndex = $Source.IndexOf("private:", $PreservedIndex)
if ($PreservedIndex -lt 0 -or $PrivateIndex -le $PreservedIndex) {
    throw "could not locate OnPreservedKey body"
}
$PreservedBody = $Source.Substring($PreservedIndex, $PrivateIndex - $PreservedIndex)
if ($PreservedBody -notmatch 'CancelLoneShiftToggle\(\)') {
    throw "OnPreservedKey must cancel lone-Shift so Ctrl+Shift+2/3 cannot also toggle ascii_mode."
}

$KeyUpBody = $Source.Substring($OnKeyUpIndex, $PreservedIndex - $OnKeyUpIndex)
if ($KeyUpBody -notmatch '!IsMouseButtonDown\(\)' -or
    $KeyUpBody -notmatch '!IsShortcutModifierDown\(\)') {
    throw "OnKeyUp must guard lone-Shift against mouse-selection and modifier chord false toggles."
}

foreach ($FunctionName in @("ToggleBoolState", "SelectSchema", "SetOutputStandard")) {
    $FunctionIndex = $Source.IndexOf("void $FunctionName(")
    if ($FunctionIndex -lt 0) {
        throw "missing state-changing function: $FunctionName"
    }
    $QueryIndex = $Source.IndexOf("QueryOperation", $FunctionIndex)
    $FlushIndex = $Source.IndexOf("CommitOrClearCompositionBeforeStateChange(context)", $FunctionIndex)
    if ($FlushIndex -lt $FunctionIndex -or $FlushIndex -gt $QueryIndex) {
        throw "$FunctionName must commit or clear live composition before sending state-changing server op."
    }
}

Write-Host "TSF reconciles server IME state and routes M05 hotkeys."
