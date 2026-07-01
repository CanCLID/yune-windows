param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FixtureScript = Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1"
$AuditScript = Join-Path $RepoRoot "tools\audit-m01-closeout.ps1"
$OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-state-snapshot-schema-test"
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

function Expect-GateStatus([object]$Audit, [string]$GateId, [string]$ExpectedStatus) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if ($null -eq $Gate) {
        throw "audit is missing gate: $GateId"
    }
    if ($Gate.status -ne $ExpectedStatus) {
        $Summary = ($Audit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
        throw "expected gate $GateId to be $ExpectedStatus, got $($Gate.status): $Summary"
    }
}

function Set-SnapshotProperty([string]$RelativePath, [string]$Name, [object]$Value) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Snapshot = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $Snapshot | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $Snapshot | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $Path -Encoding utf8
}

New-CompleteFixture
Set-SnapshotProperty `
    -RelativePath "m01\installer\post-install-state.json" `
    -Name "machine_registration_checked" `
    -Value "true"
$StringMachineRegistrationAudit = Invoke-CloseoutAudit
Expect-GateStatus `
    -Audit $StringMachineRegistrationAudit `
    -GateId "fresh-install-registration-activation" `
    -ExpectedStatus "invalid"

New-CompleteFixture
Set-SnapshotProperty `
    -RelativePath "m01\tsf-smoke\notepad-post-state.json" `
    -Name "profile_state_verified" `
    -Value "true"
Set-SnapshotProperty `
    -RelativePath "m01\tsf-smoke\chromium-post-state.json" `
    -Name "profile_state_verified" `
    -Value "true"
$StringProfileVerifiedAudit = Invoke-CloseoutAudit
Expect-GateStatus `
    -Audit $StringProfileVerifiedAudit `
    -GateId "fresh-install-registration-activation" `
    -ExpectedStatus "invalid"

New-CompleteFixture
Set-SnapshotProperty `
    -RelativePath "m01\tsf-smoke\notepad-post-state.json" `
    -Name "profile_state" `
    -Value '{"registered":"true","active":"true"}'
Set-SnapshotProperty `
    -RelativePath "m01\tsf-smoke\chromium-post-state.json" `
    -Name "profile_state" `
    -Value '{"registered":"true","active":"true"}'
$StringProfileStateAudit = Invoke-CloseoutAudit
Expect-GateStatus `
    -Audit $StringProfileStateAudit `
    -GateId "fresh-install-registration-activation" `
    -ExpectedStatus "invalid"

New-CompleteFixture
Set-SnapshotProperty `
    -RelativePath "m01\installer\post-cleanup-state.json" `
    -Name "machine_state_checked" `
    -Value "true"
$StringCleanupSnapshotAudit = Invoke-CloseoutAudit
Expect-GateStatus `
    -Audit $StringCleanupSnapshotAudit `
    -GateId "uninstall-cleanup" `
    -ExpectedStatus "invalid"

Write-Host "Closeout audit rejects state snapshots whose boolean fields are JSON strings."
