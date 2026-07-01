param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PlanScript = Join-Path $RepoRoot "tools\plan-yune-windows-machine-cleanup.ps1"
if (-not (Test-Path -LiteralPath $PlanScript)) {
    throw "missing non-mutating machine-cleanup plan script: $PlanScript"
}

$Source = Get-Content -Raw -LiteralPath $PlanScript
foreach ($Required in @(
        'machine_state_checked\s*=\s*\$MachineStateChecked',
        'residue_summary',
        'pending_rename_count',
        'filesystem_leftover_count',
        'residue_groups',
        'affected_path',
        'pending_rename_entries',
        'filesystem_leftovers'
    )) {
    if ($Source -notmatch $Required) {
        throw "machine-cleanup plan is missing actionable residue pattern: $Required"
    }
}

$OutputPath = Join-Path $env:TEMP "yune-windows\m01-machine-cleanup-plan-actionability-test.json"
$CurrentResiduePath = Join-Path $env:TEMP "yune-windows\m01-machine-cleanup-plan-actionability-test-current-residue.json"
[ordered]@{
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $CurrentResiduePath -Encoding utf8
& powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
    -OutputPath $OutputPath `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "machine-cleanup plan script failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "machine-cleanup plan did not write output: $OutputPath"
}

$Plan = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
if ($Plan.machine_state_changed -ne $false) {
    throw "machine-cleanup plan must remain non-mutating"
}
if ($Plan.machine_state_checked -ne $true) {
    throw "machine-cleanup plan must record machine_state_checked=true"
}
if ($null -eq $Plan.residue_summary) {
    throw "machine-cleanup plan must include residue_summary"
}
if ([int]$Plan.residue_summary.machine_state_issue_count -ne @($Plan.machine_state_issues).Count) {
    throw "machine_state_issue_count does not match machine_state_issues"
}
if ([int]$Plan.residue_summary.filesystem_leftover_count -ne @($Plan.filesystem_leftovers).Count) {
    throw "filesystem_leftover_count does not match filesystem_leftovers"
}
if ([int]$Plan.residue_summary.pending_rename_count -lt 0) {
    throw "pending_rename_count must be non-negative"
}
if ($null -eq $Plan.residue_groups) {
    throw "machine-cleanup plan must include residue_groups"
}

foreach ($Group in @($Plan.residue_groups)) {
    if ([string]::IsNullOrWhiteSpace([string]$Group.affected_path)) {
        throw "each residue group must include affected_path"
    }
    if ($null -eq $Group.pending_rename_entries) {
        throw "each residue group must include pending_rename_entries"
    }
    if ($null -eq $Group.filesystem_leftovers) {
        throw "each residue group must include filesystem_leftovers"
    }
    if ($Group.approval_required -ne $true) {
        throw "each residue group must keep approval_required=true"
    }
}

Write-Host "Machine cleanup plan records checked, grouped, approval-gated residue evidence."
