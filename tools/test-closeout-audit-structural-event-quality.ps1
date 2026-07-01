param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-structural-event-quality-test"
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
        "(?m)^Structural candidate update observed:.*\r?\n?",
        "")
    $Text = [regex]::Replace(
        $Text,
        "(?m)^Structural commit event observed:.*\r?\n?",
        "")
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-structural-events.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-structural-events.md"
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
        throw "audit should reject live text-smoke evidence without structural TSF event proof for $GateId, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without structural candidate and commit event proof."
