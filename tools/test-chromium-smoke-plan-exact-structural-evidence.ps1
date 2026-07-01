param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PlanPath = Join-Path $RepoRoot "docs\evidence\m01\tsf-smoke\chromium-smoke-plan.md"
if (-not (Test-Path -LiteralPath $PlanPath)) {
    $SummaryPath = Join-Path $RepoRoot "docs\evidence\m01\summary.json"
    if (-not (Test-Path -LiteralPath $SummaryPath)) {
        throw "missing Chromium smoke plan and compact M01 summary"
    }
    $Summary = Get-Content -Raw -LiteralPath $SummaryPath | ConvertFrom-Json
    if (($Summary.status -ne "complete") -or
        ($Summary.evidence_policy -ne "compact-summary-only")) {
        throw "M01 summary must document complete compact-summary evidence when raw Chromium smoke plan is pruned"
    }
    $AuditSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1")
    foreach ($RequiredToken in @("candidate_update", "commit_text")) {
        if ($AuditSource -notmatch [regex]::Escape($RequiredToken)) {
            throw "closeout audit must retain exact structural event token check for $RequiredToken"
        }
    }
    Write-Host "Chromium smoke plan raw evidence is pruned; compact summary and audit token checks are present."
    return
}
$PlanText = Get-Content -Raw -LiteralPath $PlanPath
$NormalizedPlanText = [regex]::Replace($PlanText, '\s+', ' ')

$RequiredPhrases = @(
    'new TSF structural log lines for the smoke include exact `event=candidate_update` and `event=commit_text` tokens',
    'result evidence records `Structural event matcher: exact event tokens`'
)

foreach ($Phrase in $RequiredPhrases) {
    if (-not $NormalizedPlanText.Contains($Phrase)) {
        throw "Chromium smoke plan must require exact structural event evidence: $Phrase"
    }
}

Write-Host "Chromium smoke plan requires exact structural event evidence."
