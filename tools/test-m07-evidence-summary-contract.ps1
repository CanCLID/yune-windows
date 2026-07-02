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

foreach ($Required in @(
        "implementation complete; holder-free live TSF proof pending",
        "persistent per-client Rime composition sessions",
        "manual holder-free live verification remains required",
        "Yune engine internals and the default rime_get_api() ABI unchanged",
        "docs\evidence\m07\live-checklist.md"
    )) {
    if ($Summary -notmatch [regex]::Escape($Required)) {
        throw "M07 summary is missing boundary text: $Required"
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

if ($Evidence.status -ne "implementation_complete_live_pending") {
    throw "M07 summary status must be implementation_complete_live_pending until live TSF proof lands."
}
if ($Evidence.manual_live_required -ne $true) {
    throw "M07 summary JSON must record manual_live_required=true."
}
if ($Evidence.plan_archived -ne $false) {
    throw "M07 plan must stay active until live installed-DLL proof is complete."
}
if ($Evidence.live_proof_status -ne "pending_holder_free_installed_tsf_verification") {
    throw "M07 live proof status must remain pending until operator evidence lands."
}
if ($Evidence.operator_checklist -ne "docs/evidence/m07/live-checklist.md") {
    throw "M07 summary JSON must point at the operator live checklist."
}

foreach ($Required in @(
        "Inline preedit",
        "Partial selection advances",
        "powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -RefreshSchema",
        "powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1 -RestartExplorer",
        "tools\capture-m06-tsf-events-window.ps1 -Label m07-<host> -OutputDir docs\evidence\m07\logs",
        "do not mark M07 complete"
    )) {
    if ($Checklist -notmatch [regex]::Escape($Required)) {
        throw "M07 live checklist is missing required operator step: $Required"
    }
}

Write-Host "M07 evidence summary keeps local proof separate from pending holder-free live TSF evidence."
