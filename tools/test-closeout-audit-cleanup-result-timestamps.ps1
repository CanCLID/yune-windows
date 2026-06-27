param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-cleanup-result-timestamps-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$JsonPath = Join-Path $OutputDir "audit-cleanup-result-timestamps.json"
$MarkdownPath = Join-Path $OutputDir "audit-cleanup-result-timestamps.md"

function Invoke-CompleteSynthetic {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
}

function Invoke-Audit {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Assert-CleanupGateInvalid([object]$Audit, [string]$Context) {
    $CleanupGate = $Audit.gates |
        Where-Object { $_.id -eq "uninstall-cleanup" } |
        Select-Object -First 1
    if (-not $CleanupGate) {
        throw "audit did not emit uninstall-cleanup gate for $Context"
    }
    if ($CleanupGate.status -ne "invalid") {
        throw "audit should reject $Context cleanup result timestamp evidence, got $($CleanupGate.status)"
    }
    if ($Audit.status -eq "complete") {
        throw "audit must not report complete for $Context cleanup result timestamp evidence"
    }
}

function Set-CleanupResultDate([string]$Date) {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    $CleanupResultPath = Join-Path $EvidenceRoot "p2-win01-installer\cleanup-result.md"
    $Text = Get-Content -Raw -LiteralPath $CleanupResultPath
    if ($Text -notmatch "(?m)^Date:\s*\S+\s*$") {
        throw "synthetic cleanup-result.md should contain a Date line"
    }
    $Text = $Text -replace "(?m)^Date:\s*\S+\s*$", "Date: $Date"
    $Text | Out-File -LiteralPath $CleanupResultPath -Encoding utf8
}

Invoke-CompleteSynthetic
Set-CleanupResultDate "2026-06-25T09:00:08.9999999-07:00"
$PreValidationResultAudit = Invoke-Audit
Assert-CleanupGateInvalid $PreValidationResultAudit "pre-validation Date"

Write-Host "Closeout audit rejects cleanup result timestamps before cleanup validation."
