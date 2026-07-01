param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-cleanup-validation-schema-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"
$ValidationPath = Join-Path $EvidenceRoot "m01\installer\cleanup-validation.json"
@{
    generated_at = "2026-06-25T09:00:09.0000000-07:00"
    pass = "true"
    issues = @()
} |
    ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $ValidationPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-cleanup-validation-schema.json"
$MarkdownPath = Join-Path $OutputDir "audit-cleanup-validation-schema.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$CleanupGate = $Audit.gates |
    Where-Object { $_.id -eq "uninstall-cleanup" } |
    Select-Object -First 1
if (-not $CleanupGate) {
    throw "audit did not emit uninstall-cleanup gate"
}
if ($CleanupGate.status -ne "invalid") {
    throw "audit should reject cleanup-validation.json whose pass field is not boolean true, got $($CleanupGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when cleanup-validation.json has a non-boolean pass field"
}

Write-Host "Closeout audit rejects cleanup validation whose pass field is not boolean true."
