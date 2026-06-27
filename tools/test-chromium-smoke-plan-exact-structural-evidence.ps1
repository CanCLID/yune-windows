param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PlanPath = Join-Path $RepoRoot "docs\evidence\p2-win01-tsf-smoke\chromium-smoke-plan.md"
if (-not (Test-Path -LiteralPath $PlanPath)) {
    $Roadmap = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\roadmap.md")
    if ($Roadmap -notmatch "regenerate post-rename live evidence") {
        throw "missing Chromium smoke plan and public roadmap does not mark post-rename evidence as pending"
    }
    Write-Host "Chromium smoke plan evidence is omitted from the public baseline; post-rename evidence is pending."
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
