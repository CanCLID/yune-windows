param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$LetterStart = $Source.IndexOf("if (!shift_pressed &&", [System.StringComparison]::Ordinal)
$EatenIndex = $Source.IndexOf("*eaten = TRUE;", $LetterStart, [System.StringComparison]::Ordinal)
$EnsureIndex = $Source.IndexOf("EnsureComposeSession(context)", $LetterStart, [System.StringComparison]::Ordinal)
$ComposeKeyIndex = $Source.IndexOf("op=compose-key", $LetterStart, [System.StringComparison]::Ordinal)
$QueryIndex = $Source.IndexOf("QueryComposeOperation(payload, context)", $LetterStart, [System.StringComparison]::Ordinal)
$ApplyIndex = $Source.IndexOf("ApplyComposeResponse(context, response)", $LetterStart, [System.StringComparison]::Ordinal)
if ($LetterStart -lt 0 -or $EatenIndex -lt $LetterStart -or
    $EnsureIndex -lt $EatenIndex -or $ComposeKeyIndex -lt $EnsureIndex -or
    $QueryIndex -lt $ComposeKeyIndex -or $ApplyIndex -lt $QueryIndex) {
    throw "TSF letter-key path must consume composition input after querying Yune so raw ASCII cannot leak before candidates arrive."
}

if ($Source -match "\*eaten = !candidate_\.empty\(\);") {
    throw "TSF letter-key path must not depend on candidate presence before eating input."
}

if ($Source -notmatch "bool ShouldHandleKeyDown\(WPARAM key,\s*bool shift_pressed\) const") {
    throw "TSF key-test path must distinguish text-entry keys from active-composition control keys."
}

$TestKeyDownPattern = @'
STDMETHODIMP OnTestKeyDown\(ITfContext\*, WPARAM key, LPARAM, BOOL\* eaten\) override \{
\s+if \(!eaten\) \{
\s+return E_INVALIDARG;
\s+\}
\s+const bool shift_pressed = IsShiftPressed\(\);
\s+\*eaten = ShouldHandleKeyDown\(key, shift_pressed\);
'@

if ($Source -notmatch $TestKeyDownPattern) {
    throw "TSF key-test path must not claim composition-control keys unless a composition buffer is active."
}

$KeyDownGuardPattern = @'
STDMETHODIMP OnKeyDown\(ITfContext\* context, WPARAM key, LPARAM(?: \w+)?, BOOL\* eaten\) override \{
\s+if \(!eaten\) \{
\s+return E_INVALIDARG;
\s+\}
\s+\*eaten = FALSE;
(?s:.*?)
\s+if \(!ShouldHandleKeyDown\(key, shift_pressed\)\) \{
\s+return S_OK;
\s+\}
'@

if ($Source -notmatch $KeyDownGuardPattern) {
    throw "TSF key-down path must share the context-aware handled-key gate so composition controls pass through when no buffer exists."
}

$CompositionControlPattern = @'
if \(key == VK_SPACE \|\| key == VK_RETURN \|\| key == VK_BACK \|\|
\s+key == VK_ESCAPE \|\| key == VK_NEXT \|\| key == VK_PRIOR\) \{
\s+return IsComposing\(\);
\s+\}
'@

if ($Source -notmatch $CompositionControlPattern) {
    throw "TSF key-test path must allow space, enter, number, backspace, and escape through when no composition buffer exists."
}

$NumberSelectionPattern = @'
if \(!shift_pressed && key >= L'1' && key <= L'9' && IsComposing\(\)\) \{
\s+\*eaten = TRUE;
(?s:.*?)visible_index < static_cast<int>\(last_candidates_\.size\(\)\)
'@

if ($Source -notmatch $NumberSelectionPattern) {
    throw "TSF number-key selection must consume input whenever a composition buffer exists, even if the selected candidate index is unavailable."
}

$CommitKeyPattern = @'
if \(key == VK_SPACE && IsComposing\(\)\) \{
\s+\*eaten = TRUE;
(?s:.*?)ComposePayload\("compose-commit"\)
'@

if ($Source -notmatch $CommitKeyPattern) {
    throw "TSF space commit key must consume input whenever a composition buffer exists, before querying commit text."
}

$RawEnterPattern = @'
if \(key == VK_RETURN && IsComposing\(\)\) \{
\s+\*eaten = TRUE;
\s+\(void\)CommitRawBuffer\(context\);
'@

if ($Source -notmatch $RawEnterPattern) {
    throw "TSF enter key must consume input and commit the raw composition buffer."
}

Write-Host "TSF handled-key path consumes composition input without waiting for candidates."
