param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$EscapeBranchMatch = [regex]::Match(
    $Source,
    '(?s)if \(key == VK_ESCAPE\) \{(?<body>.*?)\r?\n        if \(key >= L''1'' && key <= L''9'' && !buffer_\.empty\(\)\) \{')
if (-not $EscapeBranchMatch.Success) {
    throw "could not locate TSF escape key branch"
}

$EscapeBody = $EscapeBranchMatch.Groups["body"].Value

$CancelEventPattern = @'
WriteStructuralEvent\("composition_cancel",
\s+static_cast<int>\(buffer_\.size\(\)\),
\s+static_cast<int>\(last_candidates_\.size\(\)\)\);
'@

if ($EscapeBody -notmatch $CancelEventPattern) {
    throw "TSF escape cancellation must log structural buffer and candidate counts before clearing composition."
}

$CancelIndex = $EscapeBody.IndexOf('WriteStructuralEvent("composition_cancel"', [System.StringComparison]::Ordinal)
$ClearIndex = $EscapeBody.IndexOf("buffer_.clear();", [System.StringComparison]::Ordinal)
if ($CancelIndex -lt 0 -or $ClearIndex -lt 0) {
    throw "TSF escape branch is missing cancellation logging or buffer clear."
}
if ($ClearIndex -lt $CancelIndex) {
    throw "TSF escape branch must log cancellation counts before clearing the composition buffer."
}

Write-Host "TSF escape cancellation logs structural counts before clearing composition."
