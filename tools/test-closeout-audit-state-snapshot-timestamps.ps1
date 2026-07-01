param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FixtureScript = Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1"
$AuditScript = Join-Path $RepoRoot "tools\audit-m01-closeout.ps1"
$OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-state-snapshot-timestamps-test"
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

function Get-SnapshotPath([string]$RelativePath) {
    return Join-Path $EvidenceRoot $RelativePath
}

function Set-SnapshotCapturedAt([string]$RelativePath, [string]$CapturedAt) {
    $Path = Get-SnapshotPath $RelativePath
    $Snapshot = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $Snapshot | Add-Member -NotePropertyName "captured_at" -NotePropertyValue $CapturedAt -Force
    $Snapshot | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}

function Remove-SnapshotCapturedAt([string]$RelativePath) {
    $Path = Get-SnapshotPath $RelativePath
    $Snapshot = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $Snapshot.PSObject.Properties.Remove("captured_at")
    $Snapshot | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}

function Expect-GateStatus([object]$Audit, [string]$GateId, [string]$ExpectedStatus) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId }
    if ($null -eq $Gate) {
        throw "audit is missing gate: $GateId"
    }
    if ($Gate.status -ne $ExpectedStatus) {
        $Summary = ($Audit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
        throw "expected gate $GateId to be $ExpectedStatus, got $($Gate.status): $Summary"
    }
}

New-CompleteFixture
$StaleCapturedAt = "2026-06-25T08:59:59.0000000-07:00"
foreach ($SnapshotPath in @(
        "m01\installer\pre-install-state.json",
        "m01\installer\post-install-state.json",
        "m01\tsf-smoke\notepad-post-state.json",
        "m01\tsf-smoke\chromium-post-state.json",
        "m01\settings\diagnostics-pre-state.json",
        "m01\installer\post-cleanup-state.json"
    )) {
    Set-SnapshotCapturedAt -RelativePath $SnapshotPath -CapturedAt $StaleCapturedAt
}

$StaleAudit = Invoke-CloseoutAudit
Expect-GateStatus -Audit $StaleAudit -GateId "fresh-install-registration-activation" -ExpectedStatus "invalid"
Expect-GateStatus -Audit $StaleAudit -GateId "tsf-notepad-smoke" -ExpectedStatus "invalid"
Expect-GateStatus -Audit $StaleAudit -GateId "chromium-text-field-smoke" -ExpectedStatus "invalid"
Expect-GateStatus -Audit $StaleAudit -GateId "diagnostics-export" -ExpectedStatus "invalid"
Expect-GateStatus -Audit $StaleAudit -GateId "uninstall-cleanup" -ExpectedStatus "invalid"

New-CompleteFixture
Remove-SnapshotCapturedAt -RelativePath "m01\installer\post-install-state.json"
$MissingTimestampAudit = Invoke-CloseoutAudit
Expect-GateStatus `
    -Audit $MissingTimestampAudit `
    -GateId "fresh-install-registration-activation" `
    -ExpectedStatus "invalid"

Write-Host "Closeout audit rejects stale or untimestamped live state snapshots."
