param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Required in @(
        'STDMETHODIMP OnSetFocus\(BOOL focused\) override',
        'WriteStructuralEvent\("focus_lost"',
        'candidate_window_\.Hide\(\)'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF focus-loss path is missing required candidate transition behavior: $Required"
    }
}

$FocusLossPattern = @'
if \(!focused\) \{
(?s:.*?)WriteStructuralEvent\("focus_lost", static_cast<int>\(buffer_\.size\(\)\),
\s+static_cast<int>\(last_candidates_\.size\(\)\)\);
\s+buffer_\.clear\(\);
\s+candidate_\.clear\(\);
\s+last_candidates_\.clear\(\);
\s+candidate_window_\.Hide\(\);
\s+\}
'@

if ($Source -notmatch $FocusLossPattern) {
    throw "TSF focus-loss path must clear buffered composition, selected candidate, and candidate rows before leaving the target context."
}

Write-Host "TSF focus loss clears composition state before the next target app receives input."
