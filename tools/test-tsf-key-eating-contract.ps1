param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$LetterBranchPattern = @'
if \(!shift_pressed &&
\s+\(\(key >= L'A' && key <= L'Z'\) \|\| \(key >= L'a' && key <= L'z'\)\)\) \{(?s:.*?)ServerResponse response = QueryInput\(buffer_, false\);
\s+\*eaten = TRUE;
(?s:.*?)if \(ShowCandidates\(context, last_candidates_\)\) \{
\s+WriteStructuralEvent\("candidate_update", buffer_length,
\s+candidate_count\);
\s+\}
'@

if ($Source -notmatch $LetterBranchPattern) {
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
\s+return !buffer_\.empty\(\);
\s+\}
'@

if ($Source -notmatch $CompositionControlPattern) {
    throw "TSF key-test path must allow space, enter, number, backspace, and escape through when no composition buffer exists."
}

$NumberSelectionPattern = @'
if \(!shift_pressed && key >= L'1' && key <= L'9' && !buffer_\.empty\(\)\) \{
\s+\*eaten = TRUE;
(?s:.*?)if \(index < last_candidates_\.size\(\)\) \{
'@

if ($Source -notmatch $NumberSelectionPattern) {
    throw "TSF number-key selection must consume input whenever a composition buffer exists, even if the selected candidate index is unavailable."
}

$CommitKeyPattern = @'
if \(key == VK_SPACE && !buffer_\.empty\(\)\) \{
\s+\*eaten = TRUE;
\s+ServerResponse response = QueryInput\(buffer_, true\);
'@

if ($Source -notmatch $CommitKeyPattern) {
    throw "TSF space commit key must consume input whenever a composition buffer exists, before querying commit text."
}

$RawEnterPattern = @'
if \(key == VK_RETURN && !buffer_\.empty\(\)\) \{
\s+\*eaten = TRUE;
\s+\(void\)CommitRawBuffer\(context\);
'@

if ($Source -notmatch $RawEnterPattern) {
    throw "TSF enter key must consume input and commit the raw composition buffer."
}

Write-Host "TSF handled-key path consumes composition input without waiting for candidates."
