param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$EvidenceRoot = Join-Path $RepoRoot "docs\evidence\m07"
$SummaryPath = Join-Path $EvidenceRoot "summary.md"
$JsonPath = Join-Path $EvidenceRoot "summary.json"
$ChecklistPath = Join-Path $EvidenceRoot "live-checklist.md"

foreach ($Path in @($SummaryPath, $JsonPath, $ChecklistPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M07 evidence file: $Path"
    }
}

$Summary = Get-Content -Raw -LiteralPath $SummaryPath
$Checklist = Get-Content -Raw -LiteralPath $ChecklistPath
$Evidence = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json

foreach ($RequiredSection in @(
        "## Executed Proof",
        "## Holder-free Live Proof",
        "## Follow-up Coverage",
        "## Deferred"
    )) {
    if ($Summary -notmatch [regex]::Escape($RequiredSection)) {
        throw "M07 evidence summary must contain section: $RequiredSection"
    }
}

# M07 is complete: the summary must record the true root cause of the no-output
# hosts (the M06 pipe fix, not a composition defect) and the live F3/F4 proof.
foreach ($Required in @(
        "Status: complete",
        "persistent per-client Rime composition sessions",
        "ERROR_ACCESS_DENIED",
        "docs\evidence\m06-m07-live-closeout.md",
        "東突厥"
    )) {
    if ($Summary -notmatch [regex]::Escape($Required)) {
        throw "M07 summary is missing completion evidence text: $Required"
    }
}

$ExecutedText = (@($Evidence.executed_proof) -join "`n")
foreach ($Required in @(
        "persistent composition server protocol contract passed",
        "M07 TSF inline composition source contract passed",
        "M06 key-path regression contract passed after M07 rewrite",
        "TSF shell build"
    )) {
    if ($ExecutedText -notmatch [regex]::Escape($Required)) {
        throw "M07 executed proof is missing: $Required"
    }
}

if ($Evidence.status -ne "complete") {
    throw "M07 summary status must be complete."
}
if ($Evidence.manual_live_required -ne $false) {
    throw "M07 summary JSON must record manual_live_required=false once live proof lands."
}
if ($Evidence.plan_archived -ne $true) {
    throw "M07 plan must be archived once live installed-DLL proof is complete."
}
if ($Evidence.live_proof_status -ne "passed") {
    throw "M07 live proof status must be passed."
}
if (@($Evidence.live_proof).Count -lt 1) {
    throw "M07 summary JSON must record at least one passing live_proof entry."
}
if ($Evidence.operator_checklist -ne "docs/evidence/m07/live-checklist.md") {
    throw "M07 summary JSON must point at the operator live checklist."
}
if ($Evidence.combined_live_runbook -ne "docs/evidence/m06-m07-live-closeout.md") {
    throw "M07 summary JSON must point at the combined M06/M07 live runbook."
}

foreach ($Required in @(
        "Inline preedit",
        "Partial selection advances"
    )) {
    if ($Checklist -notmatch [regex]::Escape($Required)) {
        throw "M07 live checklist is missing required behavior step: $Required"
    }
}

Write-Host "M07 evidence summary records the complete milestone with live inline-composition proof."
