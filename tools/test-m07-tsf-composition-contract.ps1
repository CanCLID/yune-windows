param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SourcePath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $SourcePath

foreach ($Required in @(
        "public ITfCompositionSink",
        "IID_ITfCompositionSink",
        "OnCompositionTerminated(",
        "ITfContextComposition",
        "StartComposition(",
        "InlineCompositionEditSession",
        "composition_preedit",
        "JsonStringValue(json, `"preedit`")",
        "JsonStringValue(json, `"raw_input`")",
        "op=compose-begin",
        "op=compose-key",
        "op=compose-select",
        "compose-commit-raw",
        "ComposePayload(`"compose-commit`")",
        "ComposePayload(`"compose-back`")",
        "ComposePayload(`"compose-end`")",
        "PageComposition(context, page_delta)",
        "IsComposing()",
        "PunctuationInput(key, shift)"
    )) {
    if ($Source -notlike "*$Required*") {
        throw "M07 TSF composition contract missing source marker: $Required"
    }
}

foreach ($Forbidden in @(
        "CommitText(context, last_candidates_[index].text)",
        "QueryInput(buffer_, true)",
        "QueryInput(buffer_, false)",
        "buffer_.push_back(LowerAscii(key))",
        "buffer_.pop_back()",
        "PageCandidateWindow("
    )) {
    if ($Source -like "*$Forbidden*") {
        throw "M07 TSF composition contract found stale stateless key-path marker: $Forbidden"
    }
}

$SelectIndexPattern = 'op=compose-select(?s).*page_relative_index'
if ($Source -notmatch $SelectIndexPattern) {
    throw "M07 selection must send page-relative index to Rime, not cached candidate text."
}

$EnterPattern = 'key == VK_RETURN(?s).*CommitRawBuffer\(context\)(?s).*compose-commit-raw'
if ($Source -notmatch $EnterPattern) {
    throw "M07 Enter path must route to compose-commit-raw."
}

$SpacePattern = 'key == VK_SPACE(?s).*ComposePayload\("compose-commit"\)'
if ($Source -notmatch $SpacePattern) {
    throw "M07 Space path must route to compose-commit."
}

$PunctuationPattern = 'CommitCompositionForPunctuation(?s).*ComposePayload\("compose-commit"\)(?s).*QueryInput\(PunctuationInput\(key, shift\), true\)'
if ($Source -notmatch $PunctuationPattern) {
    throw "M07 punctuation path must preserve M06 behavior: commit composition first, then ask Rime for punctuation."
}

Write-Host "M07 TSF persistent inline composition contract passed."
