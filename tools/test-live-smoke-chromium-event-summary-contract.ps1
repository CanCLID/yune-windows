param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

$Title = "YuneWindows Chromium Smoke - Textarea Focused - keydown=6 beforeinput=0 input=0 compositionstart=1 compositionupdate=2 compositionend=0 value_len=0"
$Summary = Get-YuneWindowsChromiumSmokeEventSummary -Title $Title
$Expected = "focused=true, keydown=6, beforeinput=0, input=0, compositionstart=1, compositionupdate=2, compositionend=0, value_len=0"
if ($Summary -ne $Expected) {
    throw "unexpected Chromium event summary: $Summary"
}

$MissingSummary = Get-YuneWindowsChromiumSmokeEventSummary -Title ""
if ($MissingSummary -ne "focused=false, keydown=unknown, beforeinput=unknown, input=unknown, compositionstart=unknown, compositionupdate=unknown, compositionend=unknown, value_len=unknown") {
    throw "unexpected missing-title summary: $MissingSummary"
}

foreach ($Forbidden in @("ngohaig", "æˆ‘ä¿‚å€‹", "event.key", "data=")) {
    if ($Summary -match [regex]::Escape($Forbidden)) {
        throw "Chromium event summary must not include typed content: $Forbidden"
    }
}

$ChromiumSmokePath = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$Source = Get-Content -Raw -LiteralPath $ChromiumSmokePath
foreach ($Required in @(
        '$ChromiumEventSummaryAfterTyping',
        '$ChromiumEventSummaryAfterCommit',
        'Get-YuneWindowsChromiumSmokeEventSummary -Title $ChromiumEventTitleAfterTyping',
        'Get-YuneWindowsChromiumSmokeEventSummary -Title $ChromiumEventTitleAfterCommit',
        'Chromium event summary after typing: $ChromiumEventSummaryAfterTyping',
        'Chromium event summary after commit: $ChromiumEventSummaryAfterCommit'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "Chromium smoke result must record parsed event diagnostics: $Required"
    }
}

Write-Host "Chromium smoke records parsed DOM event summaries without typed content."
