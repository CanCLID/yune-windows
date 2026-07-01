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
        'Ctrl\+Shift\+3'
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
$RefreshIndex = $Source.IndexOf("RefreshStateFromServer", $ActivateIndex)
if ($ActivateIndex -lt 0 -or $RefreshIndex -lt $ActivateIndex) {
    throw "ActivateEx must refresh state from the server."
}

$FocusIndex = $Source.IndexOf("STDMETHODIMP OnSetFocus")
$FocusRefreshIndex = $Source.IndexOf("RefreshStateFromServer", $FocusIndex)
if ($FocusIndex -lt 0 -or $FocusRefreshIndex -lt $FocusIndex) {
    throw "OnSetFocus(TRUE) must refresh state from the server."
}

Write-Host "TSF reconciles server IME state and routes M05 hotkeys."
