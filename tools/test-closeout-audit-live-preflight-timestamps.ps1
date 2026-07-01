param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FixtureScript = Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1"
$AuditScript = Join-Path $RepoRoot "tools\audit-m01-closeout.ps1"
$OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-live-preflight-timestamps-test"
$EvidenceRoot = Join-Path $OutputDir "evidence"
$JsonPath = Join-Path $OutputDir "audit-under-test.json"
$MarkdownPath = Join-Path $OutputDir "audit-under-test.md"

function New-CompleteFixture {
    & $FixtureScript -OutputDir $OutputDir | Out-Null
}

function Invoke-CloseoutAudit {
    & $AuditScript `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Set-PreflightGeneratedAt([string]$RelativePath, [string]$GeneratedAt) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Report = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $Report.generated_at = $GeneratedAt
    $Report | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}

function Set-ApprovalDate([string]$DateLine) {
    $Path = Join-Path $EvidenceRoot "m01\installer\approval.md"
    $Text = Get-Content -Raw -LiteralPath $Path
    $Text = [regex]::Replace($Text, '(?m)^Date:.*$', $DateLine, 1)
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

function Get-Gate([object]$Audit, [string]$GateId) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if ($null -eq $Gate) {
        throw "audit is missing gate: $GateId"
    }
    return $Gate
}

New-CompleteFixture
Set-PreflightGeneratedAt `
    -RelativePath "m01\installer\live-preflight.json" `
    -GeneratedAt "2026-06-25T08:59:59.0000000-07:00"
$StaleLiveAudit = Invoke-CloseoutAudit
$StaleLiveGate = Get-Gate -Audit $StaleLiveAudit -GateId "live-preflight"
if ($StaleLiveGate.status -ne "invalid") {
    $Summary = ($StaleLiveAudit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
    throw "stale approved live-preflight JSON should be invalid, got $($StaleLiveGate.status): $Summary"
}

New-CompleteFixture
Set-ApprovalDate -DateLine "Date: 2026-06-25Tnot-a-valid-time"
$MalformedApprovalAudit = Invoke-CloseoutAudit
$MalformedApprovalGate = Get-Gate -Audit $MalformedApprovalAudit -GateId "live-preflight"
if ($MalformedApprovalGate.status -ne "invalid") {
    $Summary = ($MalformedApprovalAudit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
    throw "approved live-preflight evidence with a malformed approval timestamp should be invalid, got $($MalformedApprovalGate.status): $Summary"
}

New-CompleteFixture
Set-PreflightGeneratedAt `
    -RelativePath "m01\installer\install-preflight.json" `
    -GeneratedAt "2026-06-25T08:59:59.0000000-07:00"
$AdvisoryInstallAudit = Invoke-CloseoutAudit
$AdvisoryInstallGate = Get-Gate -Audit $AdvisoryInstallAudit -GateId "live-preflight"
if ($AdvisoryInstallGate.status -ne "complete") {
    $Summary = ($AdvisoryInstallAudit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
    throw "advisory install-preflight JSON may predate approval, got $($AdvisoryInstallGate.status): $Summary"
}

Write-Host "Closeout audit rejects stale approved live-preflight evidence."
