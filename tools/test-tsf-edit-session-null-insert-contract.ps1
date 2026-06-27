param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
$DoEditSessionMatch = [regex]::Match(
    $Source,
    '(?s)STDMETHODIMP DoEditSession\(TfEditCookie cookie\) override \{(?<body>.*?)\r?\n    \}\r?\n\r?\nprivate:')
if (-not $DoEditSessionMatch.Success) {
    throw "could not locate InsertTextEditSession::DoEditSession body"
}

$Body = $DoEditSessionMatch.Groups["body"].Value
foreach ($Required in @(
        'ITfInsertAtSelection* insert = nullptr;',
        'QueryInterface(IID_ITfInsertAtSelection',
        'InsertTextAtSelection(',
        'insert->Release();',
        'SetSelectionText(cookie, E_FAIL)'
    )) {
    if ($Body -notmatch [regex]::Escape($Required)) {
        throw "DoEditSession is missing expected edit-session insert pattern: $Required"
    }
}

if ($Body -notmatch 'const HRESULT query_hr =') {
    throw "DoEditSession must store the ITfInsertAtSelection QueryInterface HRESULT before deciding failure."
}

$QueryIndex = $Body.IndexOf("QueryInterface(IID_ITfInsertAtSelection", [System.StringComparison]::Ordinal)
$InsertIndex = $Body.IndexOf("InsertTextAtSelection(", [System.StringComparison]::Ordinal)
$SelectionIndex = $Body.IndexOf("SetSelectionText(cookie, E_FAIL)", [System.StringComparison]::Ordinal)
if ($SelectionIndex -lt 0 -or $SelectionIndex -gt $QueryIndex) {
    throw "DoEditSession must try selection-range SetText before the InsertTextAtSelection fallback."
}
$InsertGuardMatch = [regex]::Match(
    $Body,
    'if \(SUCCEEDED\(query_hr\) && insert\) \{(?<guard>.*?)InsertTextAtSelection',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)

if (-not $InsertGuardMatch.Success) {
    throw "DoEditSession must guard InsertTextAtSelection behind a successful ITfInsertAtSelection query."
}
if ($InsertGuardMatch.Index -lt $QueryIndex -or $InsertGuardMatch.Index -gt $InsertIndex) {
    throw "DoEditSession must validate the insert interface after QueryInterface and before InsertTextAtSelection."
}

foreach ($Required in @(
        'HRESULT SetSelectionText(TfEditCookie cookie, HRESULT prior_hr)',
        'TF_SELECTION selection = {};',
        'context_->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection',
        'selection.range->SetText(',
        'selection.range->Collapse(cookie, TF_ANCHOR_END)',
        'selection.range->Release();'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "InsertTextAtSelection fallback is missing expected selection-range commit pattern: $Required"
    }
}

Write-Host "TSF edit session uses selection-range SetText before the InsertTextAtSelection fallback."
