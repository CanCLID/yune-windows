param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

foreach ($Smoke in @(
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $Smoke
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing smoke script: $Smoke"
    }

    $Source = Get-Content -Raw -LiteralPath $Path
    foreach ($Required in @(
            'StructuralCandidateWindowFailureObserved',
            'Structural candidate window failure observed:',
            'Test-StructuralEventLine -Line $_ -EventName "candidate_window_failed"',
            '-not $StructuralCandidateWindowFailureObserved'
        )) {
        if (-not $Source.Contains($Required)) {
            throw "$Smoke must record and reject fresh candidate_window_failed structural events: $Required"
        }
    }
}

$OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-candidate-window-failure-test"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
foreach ($RelativePath in @(
        "m01\tsf-smoke\notepad-smoke-result.md",
        "m01\tsf-smoke\chromium-smoke-result.md"
    )) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $Text = [regex]::Replace(
        $Text,
        "(?m)^Structural candidate window failure observed:.*\r?\n?",
        "")
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-candidate-window-failure-proof.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-candidate-window-failure-proof.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "tsf-notepad-smoke",
        "chromium-text-field-smoke",
        "candidate-display-live"
    )) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject text-smoke evidence without explicit candidate_window_failed absence proof for $GateId, got $($Gate.status)"
    }
}

Write-Host "Live smoke and closeout audit reject fresh candidate_window_failed structural evidence."
