param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$OutputPath = "",
    [string]$CurrentResiduePath = "",
    [switch]$RefreshCurrentResidue,
    [string]$ApprovalNote = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputPath -eq "") {
    $OutputPath = Join-Path $RepoRoot "docs\evidence\m01\installer\machine-cleanup-plan.json"
}

$InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath)) {
    $CurrentResiduePath = [System.IO.Path]::GetFullPath($CurrentResiduePath)
    if (-not (Test-Path -LiteralPath $CurrentResiduePath)) {
        throw "Missing machine-cleanup current-residue evidence: $CurrentResiduePath"
    }
    $Residue = Get-Content -Raw -LiteralPath $CurrentResiduePath | ConvertFrom-Json
    $MachineResidueSource = $CurrentResiduePath
}
elseif ($RefreshCurrentResidue.IsPresent) {
    Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
    $RefreshedResidue = Get-YuneWindowsMachineResidue -InstallDir $InstallRoot
    $Residue = [pscustomobject]([ordered]@{
            generated_at = (Get-Date).ToString("o")
            machine_state_checked = $true
            machine_state_issues = @($RefreshedResidue.machine_state_issues)
            filesystem_leftovers = @($RefreshedResidue.filesystem_leftovers)
        })
    $MachineResidueSource = "Get-YuneWindowsMachineResidue"
}
else {
    throw "Machine cleanup planning requires -CurrentResiduePath or -RefreshCurrentResidue."
}
$MachineStateChecked = Get-RequiredJsonBooleanProperty `
    -Object $Residue `
    -Name "machine_state_checked" `
    -Context "machine-cleanup current-residue evidence"
if ($MachineStateChecked -ne $true) {
    throw "machine-cleanup current-residue evidence must record machine_state_checked=true."
}
$MachineStateIssues = @($Residue.machine_state_issues)
$FilesystemLeftovers = @($Residue.filesystem_leftovers)
$RecommendedSteps = [System.Collections.Generic.List[object]]::new()
$ResidueGroupsByPath = @{}

function Get-ResidueAffectedPath {
    param([string]$ResidueText)

    $PathMatch = [regex]::Match($ResidueText, '[A-Za-z]:\\.+$')
    if ($PathMatch.Success) {
        return $PathMatch.Value
    }
    if ($ResidueText -like "*:*") {
        return (($ResidueText -split ":", 2)[1]).Trim()
    }
    return $ResidueText
}

function Get-ResidueGroup {
    param([string]$AffectedPath)

    if (-not $ResidueGroupsByPath.ContainsKey($AffectedPath)) {
        $ResidueGroupsByPath[$AffectedPath] = [ordered]@{
            affected_path = $AffectedPath
            approval_required = $true
            pending_rename_entries = [System.Collections.Generic.List[string]]::new()
            registry_entries = [System.Collections.Generic.List[string]]::new()
            registry_check_failures = [System.Collections.Generic.List[string]]::new()
            machine_state_entries = [System.Collections.Generic.List[string]]::new()
            filesystem_leftovers = [System.Collections.Generic.List[string]]::new()
        }
    }
    return $ResidueGroupsByPath[$AffectedPath]
}

foreach ($Issue in $MachineStateIssues) {
    $IssueText = [string]$Issue
    $StepType = "machine-state"
    $Instruction = "After explicit approval in the current session, clear this YuneWindows machine-state residue with an elevated cleanup flow, then rerun install/live preflight."
    if ($IssueText -like "Registry key remains:*") {
        $StepType = "registry"
        $Instruction = "After explicit approval in the current session, clear the named YuneWindows registry key with an elevated cleanup flow, then rerun install/live preflight."
    } elseif ($IssueText -like "PendingFileRenameOperations contains YuneWindows residue:*") {
        $StepType = "pending-rename"
        $Instruction = "After explicit approval in the current session, resolve the YuneWindows pending-rename residue or reboot if required, then rerun install/live preflight."
    } elseif ($IssueText -like "Registry key check failed:*") {
        $StepType = "registry-check"
        $Instruction = "Investigate the failed YuneWindows registry residue check before an approved live run, then rerun install/live preflight."
    }
    $Group = Get-ResidueGroup -AffectedPath (Get-ResidueAffectedPath -ResidueText $IssueText)
    if ($StepType -eq "pending-rename") {
        $Group.pending_rename_entries.Add($IssueText) | Out-Null
    } elseif ($StepType -eq "registry") {
        $Group.registry_entries.Add($IssueText) | Out-Null
    } elseif ($StepType -eq "registry-check") {
        $Group.registry_check_failures.Add($IssueText) | Out-Null
    } else {
        $Group.machine_state_entries.Add($IssueText) | Out-Null
    }
    $RecommendedSteps.Add([ordered]@{
            type = $StepType
            residue = $IssueText
            approval_required = $true
            instruction = $Instruction
        }) | Out-Null
}

foreach ($Leftover in $FilesystemLeftovers) {
    $LeftoverText = [string]$Leftover
    $Group = Get-ResidueGroup -AffectedPath (Get-ResidueAffectedPath -ResidueText $LeftoverText)
    $Group.filesystem_leftovers.Add($LeftoverText) | Out-Null
    $RecommendedSteps.Add([ordered]@{
            type = "filesystem"
            residue = $LeftoverText
            approval_required = $true
            instruction = "After explicit approval in the current session, clear this machine-level YuneWindows file leftover or reboot if it is tied to pending rename cleanup, then rerun install/live preflight."
        }) | Out-Null
}

if ($RecommendedSteps.Count -eq 0) {
    $RecommendedSteps.Add([ordered]@{
            type = "none"
            residue = ""
            approval_required = $false
            instruction = "No YuneWindows machine-state or machine-level filesystem residue was detected; rerun install/live preflight."
        }) | Out-Null
}

$Plan = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    machine_state_changed = $false
    machine_state_checked = $MachineStateChecked
    machine_residue_source = $MachineResidueSource
    install_dir = $InstallRoot
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = $true
    blocked_live_preflight = ($MachineStateIssues.Count + $FilesystemLeftovers.Count) -gt 0
    residue_summary = [ordered]@{
        machine_state_issue_count = $MachineStateIssues.Count
        pending_rename_count = @($MachineStateIssues | Where-Object {
                [string]$_ -like "PendingFileRenameOperations contains YuneWindows residue:*"
            }).Count
        registry_entry_count = @($MachineStateIssues | Where-Object {
                [string]$_ -like "Registry key remains:*"
            }).Count
        registry_check_failure_count = @($MachineStateIssues | Where-Object {
                [string]$_ -like "Registry key check failed:*"
            }).Count
        filesystem_leftover_count = $FilesystemLeftovers.Count
        affected_path_count = $ResidueGroupsByPath.Count
    }
    machine_state_issues = $MachineStateIssues
    filesystem_leftovers = $FilesystemLeftovers
    residue_groups = @($ResidueGroupsByPath.Values)
    recommended_steps = @($RecommendedSteps)
}

New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null
$Plan | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
