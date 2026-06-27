param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-failed-cleanup-result-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
$CleanupResultPath = Join-Path $EvidenceRoot "p2-win01-installer\cleanup-result.md"
if (-not (Test-Path -LiteralPath $CleanupResultPath)) {
    throw "missing synthetic cleanup-result.md"
}

$Text = Get-Content -Raw -LiteralPath $CleanupResultPath
if ($Text -notmatch "Pass:\s*True") {
    throw "synthetic cleanup result must start with pass markers so this test isolates Status: failed"
}
$Text = $Text -replace "(Date:\s*\d{4}-\d{2}-\d{2}T\S+\s*)", "`$1`r`nStatus: failed`r`n`r`nFailure stage: cleanup`r`n"
$Text | Out-File -LiteralPath $CleanupResultPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-failed-cleanup.json"
$MarkdownPath = Join-Path $OutputDir "audit-failed-cleanup.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$CleanupGate = $Audit.gates | Where-Object { $_.id -eq "uninstall-cleanup" } | Select-Object -First 1
if (-not $CleanupGate) {
    throw "audit did not emit uninstall-cleanup gate"
}
if ($CleanupGate.status -ne "invalid") {
    throw "audit should reject cleanup-result.md with Status: failed, got $($CleanupGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when cleanup-result.md has Status: failed"
}

Write-Host "Closeout audit rejects failed cleanup result evidence even when pass markers remain."
