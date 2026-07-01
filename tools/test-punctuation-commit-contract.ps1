param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerPath = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
$TsfPath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
foreach ($Path in @($ServerPath, $TsfPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing source for punctuation contract: $Path"
    }
}

$Server = Get-Content -Raw -LiteralPath $ServerPath
$Tsf = Get-Content -Raw -LiteralPath $TsfPath

foreach ($Required in @(
        'api_->get_commit',
        'api_->free_commit',
        'RimeCommit',
        'commit_text = CStringOrEmpty\(commit\.text\)'
    )) {
    if ($Server -notmatch $Required) {
        throw "server punctuation commit path missing pattern: $Required"
    }
}

foreach ($Required in @(
        'bool IsPunctuationKey',
        'PunctuationInput',
        'QueryServer\(PunctuationInput',
        'CommitText\(context,\s*response\.commit_text\)'
    )) {
    if ($Tsf -notmatch $Required) {
        throw "TSF punctuation forwarding missing pattern: $Required"
    }
}

$PunctuationBlock = [regex]::Match(
    $Tsf,
    'if \(IsPunctuationKey\(key\) && buffer_\.empty\(\)\) \{(?s:.*?)\n        \}').Value
if ([string]::IsNullOrWhiteSpace($PunctuationBlock)) {
    throw "TSF punctuation forwarding block not found"
}
if ($PunctuationBlock -match '\*eaten\s*=\s*TRUE;\s*ServerResponse response') {
    throw "punctuation keys must not be eaten before a server punctuation commit is available"
}
if ($PunctuationBlock -notmatch 'if \(response\.ok && !response\.commit_text\.empty\(\)\) \{(?s:.*?)\*eaten\s*=\s*TRUE;(?s:.*?)CommitText\(context,\s*response\.commit_text\)') {
    throw "punctuation keys should be eaten only when committed punctuation is inserted"
}

Write-Host "Punctuation contract covers server get_commit and TSF key forwarding."
