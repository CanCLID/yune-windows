param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ChromiumSmokePath = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

if (-not (Test-Path -LiteralPath $ChromiumSmokePath)) {
    throw "missing Chromium smoke script: $ChromiumSmokePath"
}

$Source = Get-Content -Raw -LiteralPath $ChromiumSmokePath

foreach ($Required in @(
        'const smokeEventState',
        'function recordSmokeEvent',
        "input.addEventListener('keydown'",
        "input.addEventListener('beforeinput'",
        "input.addEventListener('input'",
        "input.addEventListener('compositionstart'",
        "input.addEventListener('compositionupdate'",
        "input.addEventListener('compositionend'",
        'keydown=',
        'beforeinput=',
        'input=',
        'compositionstart=',
        'compositionupdate=',
        'compositionend=',
        'value_len='
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "Chromium smoke page must expose DOM keyboard/input/composition event diagnostics without typed content: $Required"
    }
}

foreach ($Required in @(
        '$ChromiumEventTitleAfterTyping',
        '$ChromiumEventTitleAfterCommit',
        'Chromium event title after typing: $ChromiumEventTitleAfterTyping',
        'Chromium event title after commit: $ChromiumEventTitleAfterCommit',
        '$ChromiumEventTitleAfterTyping = Get-YuneWindowsWindowTitle',
        '$ChromiumEventTitleAfterCommit = Get-YuneWindowsWindowTitle'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "Chromium smoke result must preserve DOM event diagnostics for live failure triage: $Required"
    }
}

if ($Source -match 'last_key|event\.key|data=|yune_windowsSmokeEventText') {
    throw "Chromium DOM event diagnostics must not record typed key or input text."
}

Write-Host "Chromium smoke records DOM keyboard/input/composition event diagnostics without typed content."
