param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfPath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfPath -PathType Leaf)) {
    throw "missing TSF source: $TsfPath"
}

$Source = Get-Content -Raw -LiteralPath $TsfPath
foreach ($Required in @(
        'class CandidateAnchorEditSession final : public ITfEditSession',
        'TF_ES_SYNC \| TF_ES_READ',
        'context_->GetSelection\(cookie,\s*TF_DEFAULT_SELECTION',
        'view->GetTextExt\(cookie,\s*selection\.range',
        'view->GetScreenExt',
        'CandidateAnchorResult',
        'candidate_anchor_failed'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF caret anchoring contract missing pattern: $Required"
    }
}

if ($Source -match 'RECT anchor = \{80,\s*80,\s*96,\s*104\}') {
    throw "candidate anchoring must not retain the old top-left default rectangle"
}
if ($Source -match 'text_ext\.right\s*>=\s*text_ext\.left') {
    throw "zero-width GetTextExt rectangles must not be accepted as valid caret anchors"
}
if ($Source -match 'text_ext\.bottom\s*>=\s*text_ext\.top') {
    throw "zero-height GetTextExt rectangles must not be accepted as valid caret anchors"
}
if ($Source -notmatch 'clipped\s*==\s*FALSE') {
    throw "clipped GetTextExt rectangles should fall back instead of anchoring the candidate window"
}
if ($Source -notmatch 'if \(!anchor_result\.has_anchor\) \{(?s:.*?)candidate_window_\.Hide\(\)(?s:.*?)return false;') {
    throw "candidate window must hide and return false when no valid anchor is available"
}

$InsertSessionSource = [regex]::Match(
    $Source,
    'class InsertTextEditSession final : public ITfEditSession(?s:.*?)struct CandidateAnchorResult').Value
if ($InsertSessionSource -match 'GetTextExt') {
    throw "caret geometry must use a read-only edit session, not InsertTextEditSession"
}

Write-Host "TSF caret anchoring uses read-only GetSelection/GetTextExt with fallback."
