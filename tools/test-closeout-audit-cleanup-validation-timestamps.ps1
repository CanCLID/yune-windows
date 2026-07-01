param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-cleanup-validation-timestamps-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$JsonPath = Join-Path $OutputDir "audit-cleanup-validation-timestamps.json"
$MarkdownPath = Join-Path $OutputDir "audit-cleanup-validation-timestamps.md"

function Invoke-CompleteSynthetic {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
}

function Invoke-Audit {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
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
        throw "audit should reject $Context cleanup validation timestamp evidence, got $($CleanupGate.status)"
    }
    if ($Audit.status -eq "complete") {
        throw "audit must not report complete for $Context cleanup validation timestamp evidence"
    }
}

function Set-CleanupValidation([hashtable]$Properties) {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    $ValidationPath = Join-Path $EvidenceRoot "m01\installer\cleanup-validation.json"
    $Properties |
        ConvertTo-Json -Depth 4 |
        Out-File -LiteralPath $ValidationPath -Encoding utf8
}

function Set-PostCleanupStateCapturedAt([string]$CapturedAt) {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    $StatePath = Join-Path $EvidenceRoot "m01\installer\post-cleanup-state.json"
    $State = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    $State.captured_at = $CapturedAt
    $State |
        ConvertTo-Json -Depth 8 |
        Out-File -LiteralPath $StatePath -Encoding utf8
}

Invoke-CompleteSynthetic
Set-CleanupValidation @{
    pass = $true
    issues = @()
}
$MissingTimestampAudit = Invoke-Audit
Assert-CleanupGateInvalid $MissingTimestampAudit "missing generated_at"

Invoke-CompleteSynthetic
Set-CleanupValidation @{
    generated_at = "2026-06-25T08:59:59.0000000-07:00"
    pass = $true
    issues = @()
}
$StaleTimestampAudit = Invoke-Audit
Assert-CleanupGateInvalid $StaleTimestampAudit "stale generated_at"

Invoke-CompleteSynthetic
Set-PostCleanupStateCapturedAt "2026-06-25T09:00:10.0000000-07:00"
Set-CleanupValidation @{
    generated_at = "2026-06-25T09:00:09.0000000-07:00"
    pass = $true
    issues = @()
}
$PreSnapshotValidationAudit = Invoke-Audit
Assert-CleanupGateInvalid $PreSnapshotValidationAudit "pre-snapshot generated_at"

Write-Host "Closeout audit rejects missing, stale, or pre-snapshot cleanup-validation timestamps."
