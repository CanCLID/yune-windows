param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$BackspaceBranchMatch = [regex]::Match(
    $Source,
    '(?s)if \(key == VK_BACK\) \{(?<body>.*?)\r?\n        if \(key == VK_ESCAPE\) \{')
if (-not $BackspaceBranchMatch.Success) {
    throw "could not locate TSF backspace key branch"
}

$BackspaceBody = $BackspaceBranchMatch.Groups["body"].Value

foreach ($Required in @(
        'buffer_\.pop_back\(\);',
        'if \(buffer_\.empty\(\)\) \{',
        'candidate_\.clear\(\);',
        'last_candidates_\.clear\(\);',
        'candidate_window_\.Hide\(\);',
        '\*eaten = TRUE;',
        'return S_OK;'
    )) {
    if ($BackspaceBody -notmatch $Required) {
        throw "TSF final-backspace path must clear composition before querying Yune again: $Required"
    }
}

$PopIndex = $BackspaceBody.IndexOf("buffer_.pop_back();", [System.StringComparison]::Ordinal)
$EmptyCheckIndex = $BackspaceBody.IndexOf("if (buffer_.empty())", [System.StringComparison]::Ordinal)
$QueryIndex = $BackspaceBody.IndexOf("QueryServer(buffer_, false)", [System.StringComparison]::Ordinal)

foreach ($Pair in @(
        @("buffer pop", $PopIndex),
        @("empty-buffer check", $EmptyCheckIndex),
        @("server query", $QueryIndex)
    )) {
    if ([int]$Pair[1] -lt 0) {
        throw "TSF backspace branch is missing $($Pair[0])"
    }
}

if ($EmptyCheckIndex -lt $PopIndex) {
    throw "TSF backspace branch must check for an empty composition after popping the final character."
}

if ($QueryIndex -lt $EmptyCheckIndex) {
    throw "TSF backspace branch must not query Yune before handling an empty composition."
}

Write-Host "TSF final-backspace path clears composition without querying an empty buffer."
