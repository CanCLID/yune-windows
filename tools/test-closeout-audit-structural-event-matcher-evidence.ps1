param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-structural-event-matcher-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"
foreach ($RelativePath in @(
        "m01\tsf-smoke\notepad-smoke-result.md",
        "m01\tsf-smoke\chromium-smoke-result.md"
    )) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $Text = [regex]::Replace(
        $Text,
        "(?m)^Structural event matcher:.*\r?\n?",
        "")
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-structural-event-matcher.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-structural-event-matcher.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

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
        throw "audit should reject text-smoke evidence without exact structural-event matcher proof for $GateId, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without exact structural-event matcher proof."
