param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-failed-install-result-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
$InstallResultPath = Join-Path $EvidenceRoot "m01\installer\result.md"
if (-not (Test-Path -LiteralPath $InstallResultPath)) {
    throw "missing synthetic install result.md"
}

$Text = Get-Content -Raw -LiteralPath $InstallResultPath
if (($Text -notmatch "Status:\s*passed") -or ($Text -notmatch "Fresh install:\s*completed")) {
    throw "synthetic install result must start with pass markers so this test isolates Status: failed"
}
$Text = $Text -replace "(Date:\s*\d{4}-\d{2}-\d{2}T\S+\s*)", "`$1`r`nStatus: failed`r`n`r`nFailure stage: closeout-audit`r`n"
$Text | Out-File -LiteralPath $InstallResultPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-failed-install.json"
$MarkdownPath = Join-Path $OutputDir "audit-failed-install.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InstallGate = $Audit.gates |
    Where-Object { $_.id -eq "fresh-install-registration-activation" } |
    Select-Object -First 1
if (-not $InstallGate) {
    throw "audit did not emit fresh-install-registration-activation gate"
}
if ($InstallGate.status -ne "invalid") {
    throw "audit should reject result.md with Status: failed, got $($InstallGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when installer result.md has Status: failed"
}

Write-Host "Closeout audit rejects failed install/profile result evidence even when pass markers remain."
