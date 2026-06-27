param(
    [string]$CleanupPlanPath = "",
    [string]$EvidenceDir = "",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$ApprovalNote = "",
    [string]$BrowserPath = "",
    [switch]$ApprovedMachineStateChange
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($CleanupPlanPath -eq "") {
    $CleanupPlanPath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\machine-cleanup-plan.json"
}
if ($EvidenceDir -eq "") {
    $EvidenceDir = Join-Path $RepoRoot "docs\evidence\p2-win01-installer"
}

$machine_state_changed_before_approval = $false
Require-ApprovedMachineStateChange `
    -Approved $ApprovedMachineStateChange.IsPresent `
    -Action "clear YuneWindows machine residue before the P2-WIN01 live smoke"
Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
Require-ApprovedMachineCleanupContext

function Read-CleanupPlan {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "cleanup plan does not exist: $Path"
    }
    $Plan = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if ($Plan.machine_state_checked -ne $true) {
        throw "cleanup plan must record machine_state_checked=true"
    }
    if ($Plan.requires_current_session_approval -ne $true) {
        throw "cleanup plan must record requires_current_session_approval=true"
    }
    foreach ($Group in @($Plan.residue_groups)) {
        if ($Group.approval_required -ne $true) {
            throw "cleanup plan residue group is not approval-required: $($Group.affected_path)"
        }
    }
    return $Plan
}

function Get-PendingRenameOperations {
    $SessionManagerKey = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager"
    try {
        return @((Get-ItemProperty `
                    -LiteralPath $SessionManagerKey `
                    -Name PendingFileRenameOperations `
                    -ErrorAction Stop).PendingFileRenameOperations)
    }
    catch {
        return @()
    }
}

function Get-PendingRenameOperationTokenFromResidue {
    param([string]$ResidueText)

    if ($ResidueText -notlike "PendingFileRenameOperations contains YuneWindows residue:*") {
        return ""
    }
    return (($ResidueText -split ":", 2)[1]).Trim()
}

function Clear-YuneWindowsPendingRenameOperations {
    param([string[]]$ApprovedEntries)

    $SessionManagerKey = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager"
    $ApprovedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Entry in @($ApprovedEntries)) {
        $EntryText = [string]$Entry
        if (-not [string]::IsNullOrWhiteSpace($EntryText)) {
            [void]$ApprovedSet.Add($EntryText)
        }
    }
    if ($ApprovedSet.Count -eq 0) {
        return @()
    }

    $CurrentEntries = @(Get-PendingRenameOperations)
    $KeptEntries = @($CurrentEntries | Where-Object {
            -not $ApprovedSet.Contains([string]$_)
        })
    $RemovedEntries = @($CurrentEntries | Where-Object {
            $ApprovedSet.Contains([string]$_)
        })

    if ($RemovedEntries.Count -eq 0) {
        return @()
    }

    if ($KeptEntries.Count -eq 0) {
        Remove-ItemProperty `
            -LiteralPath $SessionManagerKey `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue
    }
    else {
        Set-ItemProperty `
            -LiteralPath $SessionManagerKey `
            -Name PendingFileRenameOperations `
            -Value ([string[]]$KeptEntries)
    }

    return @($RemovedEntries)
}

function Resolve-YuneWindowsRegistryResiduePath {
    param([string]$ResidueText)

    if ($ResidueText -notlike "Registry key remains:*") {
        return ""
    }
    $RegistryPath = (($ResidueText -split ":", 2)[1]).Trim()
    if ($RegistryPath -notmatch '^Registry::HKEY_(CLASSES_ROOT|CURRENT_USER|LOCAL_MACHINE)\\') {
        throw "refusing unsafe YuneWindows registry residue path: $RegistryPath"
    }
    if ($RegistryPath.IndexOf("YuneWindows", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
        $RegistryPath.IndexOf("1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
        $RegistryPath.IndexOf("3AE69B8D-19B4-4267-8F21-E239666D6632", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "refusing registry residue path that is not YuneWindows-specific: $RegistryPath"
    }
    return $RegistryPath
}

function Resolve-YuneWindowsSystemFileResiduePath {
    param([string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $ParentPath = [System.IO.Path]::GetDirectoryName($FullPath)
    $AllowedRoots = @(
        (Join-Path $env:SystemRoot "System32"),
        (Join-Path $env:SystemRoot "SysWOW64")
    )
    $Allowed = $false
    foreach ($Root in $AllowedRoots) {
        $FullRoot = [System.IO.Path]::GetFullPath($Root)
        if ([string]::Equals($ParentPath, $FullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $Allowed = $true
            break
        }
    }
    if (-not $Allowed) {
        throw "refusing filesystem residue outside direct Windows system YuneWindows file locations: $FullPath"
    }
    if ([System.IO.Path]::GetFileName($FullPath).IndexOf("YuneWindows", [System.StringComparison]::OrdinalIgnoreCase) -ne 0) {
        throw "refusing filesystem residue whose file name is not YuneWindows-specific: $FullPath"
    }
    return $FullPath
}

function Write-CleanupEvidence {
    param(
        [string]$ResultJsonPath,
        [string]$ResultMarkdownPath,
        [object]$Result
    )

    $Result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $ResultJsonPath -Encoding utf8
    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("# Approved Machine Cleanup Result") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Date: $($Result.generated_at)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Status: $($Result.status)") | Out-Null
    $Lines.Add("") | Out-Null
    $FailureStage = [string]$Result.failure_stage
    if (-not [string]::IsNullOrWhiteSpace($FailureStage)) {
        $Lines.Add("Failure stage: $FailureStage") | Out-Null
        $Lines.Add("") | Out-Null
    }
    $Lines.Add("Machine state changed before approval evidence: $($Result.machine_state_changed_before_approval)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Cleanup plan: $($Result.cleanup_plan)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Cleanup plan generated_at: $($Result.cleanup_plan_generated_at)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Cleanup plan residue detector: $($Result.cleanup_plan_residue_detector)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Cleanup plan residue groups: $($Result.cleanup_plan_residue_group_count)") | Out-Null
    $Lines.Add("") | Out-Null
    $CoverageProperty = $Result.PSObject.Properties["cleanup_plan_current_residue_covered"]
    if ($null -ne $CoverageProperty) {
        $Lines.Add("Cleanup plan current residue covered: $($CoverageProperty.Value)") | Out-Null
        $Lines.Add("") | Out-Null
    }
    $Lines.Add("Before snapshot: $($Result.before_snapshot)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("After snapshot: $($Result.after_snapshot)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Pending rename entries removed: $(@($Result.pending_rename_entries_removed).Count)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Registry keys removed: $(@($Result.registry_keys_removed).Count)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("Filesystem leftovers removed: $(@($Result.filesystem_leftovers_removed).Count)") | Out-Null
    $Lines.Add("") | Out-Null
    if (@($Result.errors).Count -gt 0) {
        $Lines.Add("Errors:") | Out-Null
        foreach ($ErrorText in @($Result.errors)) {
            $Lines.Add("- $ErrorText") | Out-Null
        }
        $Lines.Add("") | Out-Null
    }
    $Lines.Add("Rerun install/live preflight after this cleanup result.") | Out-Null
    $Lines | Out-File -LiteralPath $ResultMarkdownPath -Encoding utf8
}

$InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
$CleanupPlan = Read-CleanupPlan -Path $CleanupPlanPath
Assert-CleanupPlanProvenance `
    -Plan $CleanupPlan `
    -Context "approved machine cleanup plan"
Assert-CleanupPlanInstallDir `
    -Plan $CleanupPlan `
    -InstallDir $InstallRoot `
    -Context "approved machine cleanup plan"
Assert-CleanupPlanResidueGroups `
    -Plan $CleanupPlan `
    -Context "approved machine cleanup plan"
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceDir)
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null

$ApprovalPath = Join-Path $EvidenceRoot "machine-cleanup-approval.md"
Write-LiveSmokeApprovalEvidence `
    -Path $ApprovalPath `
    -ApprovalNote $ApprovalNote `
    -InstallDir $InstallRoot `
    -YuneRoot $YuneRoot `
    -BrowserPath $BrowserPath

$BeforeSnapshotPath = Join-Path $EvidenceRoot "machine-cleanup-before.json"
$AfterSnapshotPath = Join-Path $EvidenceRoot "machine-cleanup-after.json"
$ResultJsonPath = Join-Path $EvidenceRoot "machine-cleanup-result.json"
$ResultMarkdownPath = Join-Path $EvidenceRoot "machine-cleanup-result.md"

$BeforeResidue = $null
try {
    Write-YuneWindowsStateSnapshot `
        -Path $BeforeSnapshotPath `
        -InstallDir $InstallRoot `
        -ApprovalNote $ApprovalNote `
        -IncludeMachineResidue
}
catch {
    $SnapshotError = "before cleanup snapshot failed: $($_.Exception.Message)"
    $Result = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        status = "failed"
        failure_stage = "machine-cleanup-before-snapshot"
        cleanup_plan = $CleanupPlanPath
        cleanup_plan_generated_at = [string]$CleanupPlan.generated_at
        cleanup_plan_residue_detector = [string]$CleanupPlan.residue_detector
        cleanup_plan_residue_group_count = @($CleanupPlan.residue_groups).Count
        cleanup_plan_current_residue_covered = $false
        machine_state_changed_before_approval = $machine_state_changed_before_approval
        approval_required = $true
        before_snapshot = $BeforeSnapshotPath
        after_snapshot = ""
        pending_rename_entries_removed = @()
        registry_keys_removed = @()
        filesystem_leftovers_removed = @()
        remaining_machine_state_issues = @()
        remaining_filesystem_leftovers = @()
        errors = @($SnapshotError)
    }

    Write-CleanupEvidence `
        -ResultJsonPath $ResultJsonPath `
        -ResultMarkdownPath $ResultMarkdownPath `
        -Result $Result

    throw "approved YuneWindows machine cleanup before snapshot failed; see $ResultMarkdownPath"
}

try {
    $BeforeResidue = Get-YuneWindowsMachineResidue -InstallDir $InstallRoot
    Assert-CleanupPlanCoversCurrentResidue `
        -Plan $CleanupPlan `
        -CurrentResidue $BeforeResidue `
        -Context "approved machine cleanup plan"
    $CleanupPlanCurrentResidueCovered = $true
}
catch {
    $CoverageError = "cleanup plan current-residue coverage failed: $($_.Exception.Message)"
    $Result = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        status = "failed"
        failure_stage = "cleanup-plan-current-residue"
        cleanup_plan = $CleanupPlanPath
        cleanup_plan_generated_at = [string]$CleanupPlan.generated_at
        cleanup_plan_residue_detector = [string]$CleanupPlan.residue_detector
        cleanup_plan_residue_group_count = @($CleanupPlan.residue_groups).Count
        cleanup_plan_current_residue_covered = $false
        machine_state_changed_before_approval = $machine_state_changed_before_approval
        approval_required = $true
        before_snapshot = $BeforeSnapshotPath
        after_snapshot = ""
        pending_rename_entries_removed = @()
        registry_keys_removed = @()
        filesystem_leftovers_removed = @()
        remaining_machine_state_issues = @($BeforeResidue.machine_state_issues)
        remaining_filesystem_leftovers = @($BeforeResidue.filesystem_leftovers)
        errors = @($CoverageError)
    }

    Write-CleanupEvidence `
        -ResultJsonPath $ResultJsonPath `
        -ResultMarkdownPath $ResultMarkdownPath `
        -Result $Result

    throw "approved YuneWindows machine cleanup plan does not cover current residue; see $ResultMarkdownPath"
}

$Errors = [System.Collections.Generic.List[string]]::new()
$RemovedPendingEntries = @()
$RemovedRegistryKeys = [System.Collections.Generic.List[string]]::new()
$RemovedFilesystemLeftovers = [System.Collections.Generic.List[string]]::new()

$ApprovedPendingRenameEntries = @($CleanupPlan.residue_groups |
    ForEach-Object { $_.pending_rename_entries } |
    ForEach-Object { Get-PendingRenameOperationTokenFromResidue -ResidueText ([string]$_) } |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

try {
    if ($ApprovedPendingRenameEntries.Count -gt 0) {
        $RemovedPendingEntries = @(Clear-YuneWindowsPendingRenameOperations -ApprovedEntries $ApprovedPendingRenameEntries)
    }
}
catch {
    $Errors.Add("pending rename cleanup failed: $($_.Exception.Message)") | Out-Null
}

foreach ($Group in @($CleanupPlan.residue_groups)) {
    foreach ($RegistryResidue in @($Group.registry_entries)) {
        try {
            $RegistryPath = Resolve-YuneWindowsRegistryResiduePath -ResidueText ([string]$RegistryResidue)
            if ($RegistryPath -and (Test-Path -LiteralPath $RegistryPath)) {
                Remove-Item -LiteralPath $RegistryPath -Recurse -Force
                $RemovedRegistryKeys.Add($RegistryPath) | Out-Null
            }
        }
        catch {
            $Errors.Add("registry cleanup failed for $RegistryResidue`: $($_.Exception.Message)") | Out-Null
        }
    }

    foreach ($Leftover in @($Group.filesystem_leftovers)) {
        try {
            $LeftoverPath = Resolve-YuneWindowsSystemFileResiduePath -Path ([string]$Leftover)
            if (Test-Path -LiteralPath $LeftoverPath) {
                Remove-Item -LiteralPath $LeftoverPath -Force
                $RemovedFilesystemLeftovers.Add($LeftoverPath) | Out-Null
            }
        }
        catch {
            $Errors.Add("filesystem cleanup failed for $Leftover`: $($_.Exception.Message)") | Out-Null
        }
    }
}

try {
    Write-YuneWindowsStateSnapshot `
        -Path $AfterSnapshotPath `
        -InstallDir $InstallRoot `
        -ApprovalNote $ApprovalNote `
        -IncludeMachineResidue
    $AfterResidue = Get-YuneWindowsMachineResidue -InstallDir $InstallRoot
}
catch {
    $SnapshotError = "after cleanup snapshot failed: $($_.Exception.Message)"
    $Result = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        status = "failed"
        failure_stage = "machine-cleanup-after-snapshot"
        cleanup_plan = $CleanupPlanPath
        cleanup_plan_generated_at = [string]$CleanupPlan.generated_at
        cleanup_plan_residue_detector = [string]$CleanupPlan.residue_detector
        cleanup_plan_residue_group_count = @($CleanupPlan.residue_groups).Count
        cleanup_plan_current_residue_covered = $CleanupPlanCurrentResidueCovered
        machine_state_changed_before_approval = $machine_state_changed_before_approval
        approval_required = $true
        before_snapshot = $BeforeSnapshotPath
        after_snapshot = $AfterSnapshotPath
        pending_rename_entries_removed = @($RemovedPendingEntries)
        registry_keys_removed = @($RemovedRegistryKeys)
        filesystem_leftovers_removed = @($RemovedFilesystemLeftovers)
        remaining_machine_state_issues = @()
        remaining_filesystem_leftovers = @()
        errors = @($SnapshotError)
    }

    Write-CleanupEvidence `
        -ResultJsonPath $ResultJsonPath `
        -ResultMarkdownPath $ResultMarkdownPath `
        -Result $Result

    throw "approved YuneWindows machine cleanup after snapshot failed; see $ResultMarkdownPath"
}
$RemainingIssues = @($AfterResidue.machine_state_issues)
$RemainingLeftovers = @($AfterResidue.filesystem_leftovers)
$Status = "passed"
if ($Errors.Count -gt 0 -or $RemainingIssues.Count -gt 0 -or $RemainingLeftovers.Count -gt 0) {
    $Status = "failed"
}

$Result = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    status = $Status
    failure_stage = ""
    cleanup_plan = $CleanupPlanPath
    cleanup_plan_generated_at = [string]$CleanupPlan.generated_at
    cleanup_plan_residue_detector = [string]$CleanupPlan.residue_detector
    cleanup_plan_residue_group_count = @($CleanupPlan.residue_groups).Count
    cleanup_plan_current_residue_covered = $CleanupPlanCurrentResidueCovered
    machine_state_changed_before_approval = $machine_state_changed_before_approval
    approval_required = $true
    before_snapshot = $BeforeSnapshotPath
    after_snapshot = $AfterSnapshotPath
    pending_rename_entries_removed = @($RemovedPendingEntries)
    registry_keys_removed = @($RemovedRegistryKeys)
    filesystem_leftovers_removed = @($RemovedFilesystemLeftovers)
    remaining_machine_state_issues = $RemainingIssues
    remaining_filesystem_leftovers = $RemainingLeftovers
    errors = @($Errors)
}

Write-CleanupEvidence `
    -ResultJsonPath $ResultJsonPath `
    -ResultMarkdownPath $ResultMarkdownPath `
    -Result $Result

if ($Status -ne "passed") {
    throw "approved YuneWindows machine cleanup left residue or errors; see $ResultMarkdownPath"
}

Write-Output $ResultMarkdownPath
