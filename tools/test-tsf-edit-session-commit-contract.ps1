param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Required in @(
        'bool CommitText\(ITfContext\* context, const std::wstring& text\)',
        'WriteStructuralEvent\("commit_text_failed"',
        'return false;',
        'return true;'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF edit-session commit path is missing failure-aware behavior: $Required"
    }
}

$RequestFailurePattern = @'
const HRESULT request_hr =
(?s:.*?)context->RequestEditSession\(client_id_, session,
(?s:.*?)TF_ES_SYNC \| TF_ES_READWRITE, &edit_hr\);
\s+session->Release\(\);
\s+if \(FAILED\(request_hr\) \|\| FAILED\(edit_hr\)\) \{
\s+WriteStructuralEvent\("commit_text_failed",
\s+static_cast<int>\(text\.size\(\)\)\);
\s+return false;
\s+\}
\s+WriteStructuralEvent\("commit_text",
\s+static_cast<int>\(text\.size\(\)\)\);
\s+return true;
'@

if ($Source -notmatch $RequestFailurePattern) {
    throw "TSF edit-session commit path must check RequestEditSession and edit-session HRESULTs before logging success."
}

$NumberSelectionPattern = @'
if \(CommitText\(context, last_candidates_\[index\]\.text\)\) \{
\s+buffer_\.clear\(\);
\s+candidate_\.clear\(\);
\s+last_candidates_\.clear\(\);
\s+candidate_window_\.Hide\(\);
\s+\}
'@

if ($Source -notmatch $NumberSelectionPattern) {
    throw "TSF number-key selection must clear composition state only after edit-session commit succeeds."
}

$DefaultCommitPattern = @'
if \(CommitText\(context, commit\)\) \{
\s+buffer_\.clear\(\);
\s+candidate_\.clear\(\);
\s+last_candidates_\.clear\(\);
\s+candidate_window_\.Hide\(\);
\s+\}
'@

if ($Source -notmatch $DefaultCommitPattern) {
    throw "TSF space/enter commit must clear composition state only after edit-session commit succeeds."
}

Write-Host "TSF edit-session commit logs failures and clears composition only after commit succeeds."
