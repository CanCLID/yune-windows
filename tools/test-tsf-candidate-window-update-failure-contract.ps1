param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
$ShowMatch = [regex]::Match(
    $Source,
    '(?s)bool ShowCandidates\(ITfContext\* context,\s+const std::vector<yune_windows::CandidateWindowCandidate>& candidates\) \{(?<body>.*?)\r?\n    \}\r?\n\r?\n    std::atomic<long> ref_;')
if (-not $ShowMatch.Success) {
    throw "ShowCandidates must return bool so candidate_update evidence only follows confirmed native-window updates."
}

$ShowBody = $ShowMatch.Groups["body"].Value
foreach ($Required in @(
        'candidate_window_.Hide();',
        'return false;',
        'yune_windows::CandidateWindowState state;',
        'state.candidates = candidates;',
        'candidate_window_.Update(state, true)'
    )) {
    if ($ShowBody -notmatch [regex]::Escape($Required)) {
        throw "ShowCandidates is missing required candidate-window update behavior: $Required"
    }
}

$FailurePattern = 'WriteStructuralEvent\("candidate_window_failed",\s+static_cast<int>\(candidates\.size\(\)\),\s+static_cast<int>\(candidates\.size\(\)\)\);\s+return false;'
if ($ShowBody -notmatch $FailurePattern) {
    throw "ShowCandidates must log structural candidate_window_failed with counts before returning false."
}

if ($ShowBody -notmatch 'catch \(\.\.\.\) \{(?s:.*?)candidate_window_failed(?s:.*?)return false;(?s:.*?)\}') {
    throw "ShowCandidates must catch native candidate-window update exceptions before they cross the TSF key callback."
}

if ($ShowBody -notmatch 'if \(!candidate_window_\.Update\(state, true\)\) \{(?s:.*?)candidate_window_failed(?s:.*?)return false;(?s:.*?)\}') {
    throw "ShowCandidates must treat a false native candidate-window update as structural candidate_window_failed evidence."
}

if ($ShowBody -notmatch 'return true;') {
    throw "ShowCandidates must return true after a confirmed candidate-window update."
}

$UnguardedPattern = 'ShowCandidates\(context, last_candidates_\);\s+WriteStructuralEvent\("candidate_update"'
if ($Source -match $UnguardedPattern) {
    throw "TSF key paths must not write candidate_update after an unguarded ShowCandidates call."
}

$GuardedUpdatePattern = 'if \(ShowCandidates\(context, last_candidates_\)\) \{\s+WriteStructuralEvent\("candidate_update",\s+buffer_length,\s+candidate_count\);\s+\}'
$GuardedUpdates = [regex]::Matches(
    $Source,
    $GuardedUpdatePattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($GuardedUpdates.Count -lt 2) {
    throw "Letter and Backspace candidate-update paths must gate candidate_update on ShowCandidates success."
}

Write-Host "TSF candidate_update evidence is gated on successful native candidate-window updates."
