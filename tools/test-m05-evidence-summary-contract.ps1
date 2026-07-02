param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SummaryPath = Join-Path $RepoRoot "docs\evidence\m05\summary.md"
$JsonPath = Join-Path $RepoRoot "docs\evidence\m05\summary.json"

if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    throw "missing M05 evidence summary markdown: $SummaryPath"
}
if (-not (Test-Path -LiteralPath $JsonPath -PathType Leaf)) {
    throw "missing M05 evidence summary JSON: $JsonPath"
}

$Summary = Get-Content -Raw -LiteralPath $SummaryPath
$Evidence = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json

foreach ($RequiredSection in @(
        "## Executed Proof",
        "## Source Contracts",
        "## Holder-free Live Proof",
        "## Follow-up Coverage",
        "## Deferred"
    )) {
    if ($Summary -notmatch [regex]::Escape($RequiredSection)) {
        throw "M05 evidence summary must contain section: $RequiredSection"
    }
}

if ($Summary -match "## Proven Behaviors") {
    throw "M05 evidence summary must not use a single Proven Behaviors bucket for mixed executed and source-contract evidence."
}

foreach ($Property in @("executed_proof", "source_contracts", "live_proof", "follow_up_coverage", "deferred")) {
    if ($null -eq $Evidence.$Property -or @($Evidence.$Property).Count -eq 0) {
        throw "M05 summary JSON must include non-empty $Property."
    }
}

$ExecutedText = (@($Evidence.executed_proof) -join "`n")
foreach ($Required in @(
        "ascii_mode=true non-empty input",
        "persisted ascii_mode=true restart",
        "invalid op returns ready:false/error",
        "server remains alive after invalid op",
        "settings/schema-cycle fallback cannot kill server"
    )) {
    if ($ExecutedText -notmatch [regex]::Escape($Required)) {
        throw "M05 executed proof is missing: $Required"
    }
}

$SourceText = (@($Evidence.source_contracts) -join "`n")
foreach ($Required in @(
        "mid-composition toggle commit-or-clear",
        "lone-Shift chord/autorepeat/mouse/focus guards",
        "focus refresh existing-server-only"
    )) {
    if ($SourceText -notmatch [regex]::Escape($Required)) {
        throw "M05 source contracts are missing: $Required"
    }
}

$LiveProofText = (@($Evidence.live_proof) -join "`n")
foreach ($Required in @(
        "post-reboot dev-reload-server",
        "post-reboot dev-reload-tsf",
        "manual operator verification"
    )) {
    if ($LiveProofText -notmatch [regex]::Escape($Required)) {
        throw "M05 live proof is missing: $Required"
    }
}

$FollowUpText = (@($Evidence.follow_up_coverage) -join "`n")
if ($FollowUpText -notmatch "Chromium") {
    throw "M05 follow-up coverage must retain Chromium breadth as follow-up evidence."
}

if ($Evidence.status -ne "complete") {
    throw "M05 summary status must be complete after closeout."
}
if ($Evidence.plan_archived -ne $true) {
    throw "M05 summary must record that the plan is archived after closeout."
}

Write-Host "M05 evidence summary separates executed proof, source contracts, live proof, follow-up coverage, and deferred work."
