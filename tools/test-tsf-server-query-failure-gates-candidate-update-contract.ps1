param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$CandidateQueryGuardPattern = @'
ServerResponse response = QueryInput\(buffer_, false\);
(?s:.*?)if \(!response\.ok\) \{
(?s:.*?)candidate_\.clear\(\);
(?s:.*?)last_candidates_\.clear\(\);
(?s:.*?)candidate_window_\.Hide\(\);
(?s:.*?)return S_OK;
\s+\}
\s+last_candidates_ = response\.candidates;
'@

$CandidateQueryGuards = [regex]::Matches($Source, $CandidateQueryGuardPattern)
if ($CandidateQueryGuards.Count -lt 2) {
    throw "TSF letter and backspace candidate-update paths must stop on QueryServer failure before updating candidate rows."
}

$CandidateQueryFailureConsumesPattern = @'
ServerResponse response = QueryInput\(buffer_, false\);
(?s:.*?)\*eaten = TRUE;
(?s:.*?)if \(!response\.ok\) \{
(?s:.*?)candidate_window_\.Hide\(\);
\s+return S_OK;
\s+\}
\s+last_candidates_ = response\.candidates;
'@

if ($Source -notmatch $CandidateQueryFailureConsumesPattern) {
    throw "TSF candidate query-failure paths must consume handled composition input before returning."
}

$CommitQueryGuardPattern = @'
ServerResponse response = QueryInput\(buffer_, true\);
\s+if \(!response\.ok\) \{
\s+\*eaten = TRUE;
\s+return S_OK;
\s+\}
\s+std::wstring commit = response\.commit_text;
'@

if ($Source -notmatch $CommitQueryGuardPattern) {
    throw "TSF space/enter commit must stop on QueryServer failure before falling back to cached candidate text."
}

Write-Host "TSF key handlers gate candidate update and commit fallback on successful server queries."
