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
        'CommitCompositionForPunctuation',
        'QueryInput\(PunctuationInput\(key,\s*shift\)',
        'CommitText\(context,\s*punctuation_response\.commit_text\)'
    )) {
    if ($Tsf -notmatch $Required) {
        throw "TSF punctuation forwarding missing pattern: $Required"
    }
}

$ShouldHandleSource = [regex]::Match(
    $Tsf,
    'bool ShouldHandleKeyDown\(WPARAM key,\s*bool shift_pressed\) const \{(?s:.*?)\n    \}').Value
if ($ShouldHandleSource -notmatch 'if \(IsPunctuationKey\(key,\s*shift_pressed\)\) \{(?s:.*?)return true;') {
    throw "punctuation keys must be handled while composing so sentence punctuation is not passed through raw"
}

$CompositionPunctuationSource = [regex]::Match(
    $Tsf,
    'bool CommitCompositionForPunctuation\(ITfContext\* context,\s*WPARAM key,\s*bool shift\) \{(?s:.*?)\n    \}').Value
if ([string]::IsNullOrWhiteSpace($CompositionPunctuationSource)) {
    throw "missing composing punctuation helper"
}
foreach ($Required in @(
        'if \(IsComposing\(\)\)',
        'QueryComposeOperation\(ComposePayload\("compose-commit"\)',
        'ApplyComposeResponse\(context,\s*composition_response\)',
        'ServerResponse punctuation_response\s*=\s*QueryInput\(PunctuationInput\(key,\s*shift\), true\)',
        'CommitText\(context,\s*punctuation_response\.commit_text\)'
    )) {
    if ($CompositionPunctuationSource -notmatch $Required) {
        throw "composing punctuation helper missing pattern: $Required"
    }
}

$PunctuationBlock = [regex]::Match(
    $Tsf,
    'if \(IsPunctuationKey\(key,\s*shift_pressed\)\) \{(?s:.*?)\n        \}').Value
if ([string]::IsNullOrWhiteSpace($PunctuationBlock)) {
    throw "TSF punctuation forwarding block not found"
}
if ($PunctuationBlock -notmatch 'CommitCompositionForPunctuation\(context,\s*key,\s*shift_pressed\)') {
    throw "punctuation key path should route through the composing punctuation helper"
}
if ($PunctuationBlock -notmatch 'const bool was_composing = IsComposing\(\)') {
    throw "punctuation key path should remember whether composition was active"
}
if ($PunctuationBlock -match '\*eaten\s*=\s*TRUE;\s*ServerResponse') {
    throw "punctuation keys must not be eaten before a server punctuation commit is available"
}
if ($PunctuationBlock -notmatch 'if \(CommitCompositionForPunctuation\(context,\s*key,\s*shift_pressed\) \|\|(?s:.*?)was_composing\) \{(?s:.*?)\*eaten\s*=\s*TRUE;') {
    throw "composing punctuation must be eaten even if punctuation insertion cannot fall back safely"
}

Write-Host "Punctuation contract covers server get_commit and TSF key forwarding."
