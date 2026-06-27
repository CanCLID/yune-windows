param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-screenshot-distinct-result-test"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP "yune-windows"))
if (-not $OutputDir.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to clean output directory outside $AllowedRoot"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"

function Remove-ResultLine([string]$RelativePath, [string]$LinePattern) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing synthetic result: $RelativePath"
    }
    $Text = Get-Content -Raw -LiteralPath $Path
    if ($Text -notmatch "(?m)^$LinePattern$") {
        throw "synthetic result must start with candidate/commit screenshot distinct proof: $RelativePath"
    }
    $Updated = [regex]::Replace($Text, "(?m)^$LinePattern\r?\n?", "")
    $Updated | Out-File -LiteralPath $Path -Encoding utf8
}

foreach ($ResultPath in @(
        "p2-win01-tsf-smoke\notepad-smoke-result.md",
        "p2-win01-tsf-smoke\chromium-smoke-result.md"
    )) {
    Remove-ResultLine `
        -RelativePath $ResultPath `
        -LinePattern "Candidate/commit screenshots distinct: True"
}

$JsonPath = Join-Path $OutputDir "audit-without-screenshot-distinct-result-proof.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-screenshot-distinct-result-proof.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
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
        throw "audit should reject text-smoke evidence without candidate/commit screenshot distinct result proof for $GateId, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without candidate/commit screenshot distinct result proof."
