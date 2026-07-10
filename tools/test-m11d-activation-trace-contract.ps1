param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Capture = Join-Path $RepoRoot "tools\dev\capture-m11d-activation-trace.ps1"
if (-not (Test-Path -LiteralPath $Capture -PathType Leaf)) {
    throw "missing M11D activation trace capture helper"
}

$Source = Get-Content -Raw -LiteralPath $Capture -Encoding UTF8
foreach ($Required in @(
        'capture-language-bar-topology\.ps1',
        'utc_filetime',
        'monotonic_ms',
        'process_nonce',
        'toggle_token',
        'detector',
        'disposition',
        'dispatcher',
        'context_available',
        'context_source',
        'foreground_match',
        'no titles, typed text, composition text, or arbitrary key sequences'
    )) {
    if ($Source -notmatch $Required) {
        throw "M11D activation trace helper is missing: $Required"
    }
}

$TempRoot = Join-Path $env:TEMP "yune-windows\m11d-trace-contract-$PID"
$LogDir = Join-Path $TempRoot "logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null
try {
    @(
        "event=shift_disposition sequence=1 utc_filetime=10 monotonic_ms=20 pid=30 tid=40 process_nonce=50 toggle_token=60 generation=70 detector=sink disposition=accepted state_revision=80 typed_text=secret window_title=secret",
        "event=shift_disposition sequence=2 utc_filetime=11 monotonic_ms=21 pid=31 tid=41 process_nonce=51 toggle_token=60 generation=70 detector=hook disposition=rejected_repeat state_revision=80",
        "event=shift_toggle_outcome sequence=3 utc_filetime=12 monotonic_ms=22 pid=32 tid=42 process_nonce=52 generation=70 outcome=persist_failed press_count=1 desired=1 attempts=1 state_revision=80",
        "event=focus_gained sequence=4 utc_filetime=13 monotonic_ms=23 pid=33 tid=43 process_nonce=53 generation=71 dispatcher=90 context_available=1 context_source=thread_mgr_focus_top composition_text=secret",
        "event=toolbar_visibility sequence=5 utc_filetime=14 monotonic_ms=24 pid=34 tid=44 process_nonce=54 owner=100 foreground=100 foreground_match=1 context_source=cached_owner reason=eligible_show"
    ) | Set-Content -LiteralPath (Join-Path $LogDir "tsf-events.log") -Encoding UTF8

    $Json = (& $Capture -InstallDir $TempRoot -MaxEvents 10 | Out-String).Trim()
    if ($Json -match 'secret|typed_text|window_title') {
        throw "M11D activation trace leaked a non-allowlisted text field"
    }
    $Report = $Json | ConvertFrom-Json
    if ($Report.schema_version -ne 1 -or $Report.event_count -ne 5) {
        throw "M11D activation trace returned an unexpected schema/count"
    }
    if ([string]$Report.events[0].toggle_token -ne "60" -or
        [string]$Report.events[0].detector -ne "sink" -or
        [string]$Report.events[1].detector -ne "hook" -or
        [string]$Report.events[1].disposition -ne "rejected_repeat" -or
        [string]$Report.events[2].outcome -ne "persist_failed" -or
        [string]$Report.events[3].context_source -ne "thread_mgr_focus_top" -or
        [string]$Report.events[3].context_available -ne "1" -or
        [string]$Report.events[4].context_source -ne "cached_owner" -or
        [string]$Report.events[4].reason -ne "eligible_show") {
        throw "M11D activation trace dropped required allowlisted fields"
    }
    if ($null -eq $Report.topology -or $null -eq $Report.topology.window_count) {
        throw "M11D activation trace did not correlate toolbar topology"
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

Write-Host "M11D activation trace is privacy-safe and topology-correlated."
