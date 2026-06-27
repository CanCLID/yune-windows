param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-product-engine-claim-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null

function Write-EvidenceFile([string]$RelativePath, [string]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Content | Out-File -LiteralPath $Path -Encoding utf8
}

function Invoke-TestAudit([string]$Name) {
    $JsonPath = Join-Path $OutputDir "$Name.json"
    $MarkdownPath = Join-Path $OutputDir "$Name.md"
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

Write-EvidenceFile "p2-win01-installer\result.md" @'
# Synthetic Bad Claim

Status: passed

Windows product evidence closes Yune M38.
'@

$BadAudit = Invoke-TestAudit "bad-claim"
$BadGate = $BadAudit.gates | Where-Object { $_.id -eq "product-engine-claim-split" } | Select-Object -First 1
if (-not $BadGate) {
    throw "audit did not emit product-engine-claim-split gate"
}
if ($BadGate.status -ne "invalid") {
    throw "audit should reject evidence claiming Windows product proof closes Yune M38, got $($BadGate.status)"
}

Write-EvidenceFile "p2-win01-installer\result.md" @'
# Synthetic Allowed Claim

Status: passed

Windows product evidence does not close Yune M38.
'@

$AllowedAudit = Invoke-TestAudit "allowed-claim"
$AllowedGate = $AllowedAudit.gates | Where-Object { $_.id -eq "product-engine-claim-split" } | Select-Object -First 1
if (-not $AllowedGate) {
    throw "audit did not emit product-engine-claim-split gate for allowed claim"
}
if ($AllowedGate.status -ne "complete") {
    throw "audit should accept explicit product/engine claim separation, got $($AllowedGate.status)"
}

Write-Host "Closeout audit enforces the Windows product/Yune M38 claim split."
