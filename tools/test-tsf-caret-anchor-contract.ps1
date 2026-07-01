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
        'CandidateAnchorResult'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF caret anchoring contract missing pattern: $Required"
    }
}

$InsertSessionSource = [regex]::Match(
    $Source,
    'class InsertTextEditSession final : public ITfEditSession(?s:.*?)struct CandidateAnchorResult').Value
if ($InsertSessionSource -match 'GetTextExt') {
    throw "caret geometry must use a read-only edit session, not InsertTextEditSession"
}

Write-Host "TSF caret anchoring uses read-only GetSelection/GetTextExt with fallback."
