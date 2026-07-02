param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RunbookPath = Join-Path $RepoRoot "docs\evidence\m06-m07-live-closeout.md"
$M06SummaryPath = Join-Path $RepoRoot "docs\evidence\m06\summary.json"
$M07SummaryPath = Join-Path $RepoRoot "docs\evidence\m07\summary.json"
$M06MatrixPath = Join-Path $RepoRoot "docs\evidence\m06\matrix.md"
$M07ChecklistPath = Join-Path $RepoRoot "docs\evidence\m07\live-checklist.md"

foreach ($Path in @($RunbookPath, $M06SummaryPath, $M07SummaryPath, $M06MatrixPath, $M07ChecklistPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M06/M07 closeout artifact: $Path"
    }
}

$Runbook = Get-Content -Raw -LiteralPath $RunbookPath
$M06Summary = Get-Content -Raw -LiteralPath $M06SummaryPath | ConvertFrom-Json
$M07Summary = Get-Content -Raw -LiteralPath $M07SummaryPath | ConvertFrom-Json
$M06Matrix = Get-Content -Raw -LiteralPath $M06MatrixPath
$M07Checklist = Get-Content -Raw -LiteralPath $M07ChecklistPath

foreach ($Required in @(
        "Do not force-close non-dev holder applications.",
        "Do not run elevated install/register/unregister/cleanup/AppVerifier/PageHeap",
        "Do not mark M06 or M07 complete until the required live evidence is recorded.",
        "tools\dev\dev-reload-server.ps1 -RefreshSchema",
        "tools\dev\dev-reload-tsf.ps1 -RestartExplorer",
        "docs/evidence/m06/matrix.md",
        "docs/evidence/m07/live-checklist.md",
        "## Pre-live Readiness Commands",
        "pre-live guard: it asserts that M06 and M07 remain active, live-pending, and not",
        "Do not use that readiness contract as the final post-live closeout",
        "## Post-live Closeout Commands",
        "tools\test-m06-evidence-summary-contract.ps1",
        "tools\test-m07-evidence-summary-contract.ps1",
        "tools\test-milestone-naming-contract.ps1"
    )) {
    if ($Runbook -notmatch [regex]::Escape($Required)) {
        throw "M06/M07 closeout runbook is missing required text: $Required"
    }
}

if ($M06Summary.status -ne "implementation_complete_live_pending") {
    throw "M06 must stay live-pending until the holder-free matrix is recorded."
}
if ($M06Summary.combined_live_runbook -ne "docs/evidence/m06-m07-live-closeout.md") {
    throw "M06 summary JSON must point at the combined M06/M07 live runbook."
}
if ($M07Summary.status -ne "implementation_complete_live_pending") {
    throw "M07 must stay live-pending until holder-free inline-composition proof is recorded."
}
if ($M06Summary.manual_live_required -ne $true -or $M07Summary.manual_live_required -ne $true) {
    throw "M06 and M07 must both require manual live verification before completion."
}
if ($M06Summary.plan_archived -ne $false -or $M07Summary.plan_archived -ne $false) {
    throw "M06/M07 plans must remain active until live proof is recorded."
}

foreach ($RequiredHost in @("Notepad", "Chromium browser", "Telegram Desktop")) {
    if ($M06Matrix -notmatch [regex]::Escape($RequiredHost)) {
        throw "M06 matrix is missing required host: $RequiredHost"
    }
}
foreach ($Required in @("Inline preedit", "Partial selection advances", "do not mark M07 complete")) {
    if ($M07Checklist -notmatch [regex]::Escape($Required)) {
        throw "M07 checklist is missing required live proof item: $Required"
    }
}

Write-Host "M06/M07 live closeout readiness contract keeps pending live proof explicit."
