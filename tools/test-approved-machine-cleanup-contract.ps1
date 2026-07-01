param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CleanupScript = Join-Path $RepoRoot "tools\clear-yune-windows-machine-residue.ps1"
if (-not (Test-Path -LiteralPath $CleanupScript)) {
    throw "missing approved machine cleanup script: tools\clear-yune-windows-machine-residue.ps1"
}
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
if (-not (Test-Path -LiteralPath $SupportScript)) {
    throw "missing live smoke support script: tools\live-smoke-support.ps1"
}
. $SupportScript

$Source = Get-Content -Raw -LiteralPath $CleanupScript
$SupportSource = Get-Content -Raw -LiteralPath $SupportScript

$RegistryOnlyResidue = "Registry key remains: Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}"
$RegistryOnlyPlan = [pscustomobject]@{
    machine_state_issues = @($RegistryOnlyResidue)
    filesystem_leftovers = @()
    residue_groups = @(
        [pscustomobject]@{
            affected_path = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}"
            approval_required = $true
            pending_rename_entries = @()
            registry_entries = @($RegistryOnlyResidue)
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @()
        }
    )
}
$RegistryOnlyCurrentResidue = [pscustomobject]@{
    machine_state_issues = @($RegistryOnlyResidue)
    filesystem_leftovers = @()
}
Assert-CleanupPlanCoversCurrentResidue `
    -Plan $RegistryOnlyPlan `
    -CurrentResidue $RegistryOnlyCurrentResidue `
    -Context "registry-only cleanup plan"

function Get-CleanupScriptFunctionDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptSource,
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $ScriptSource,
        [ref]$Tokens,
        [ref]$ParseErrors)
    if (@($ParseErrors).Count -gt 0) {
        throw "cleanup script parse errors prevented function import: $($ParseErrors -join '; ')"
    }

    $FunctionAst = $Ast.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $Node.Name -eq $FunctionName
        }, $true)
    if ($null -eq $FunctionAst) {
        throw "cleanup script is missing function: $FunctionName"
    }

    return $FunctionAst.Extent.Text
}

foreach ($Required in @(
        '\[switch\]\$ApprovedMachineStateChange',
        '\[string\]\$ApprovalNote\s*=\s*""',
        '\[string\]\$BrowserPath\s*=\s*""',
        'Require-ApprovedMachineStateChange',
        'Require-LiveSmokeApprovalNote\s+-ApprovalNote\s+\$ApprovalNote',
        'Require-ApprovedMachineCleanupContext',
        'Write-LiveSmokeApprovalEvidence',
        '-BrowserPath\s+\$BrowserPath',
        'clear YuneWindows machine residue',
        'machine_state_changed_before_approval\s*=\s*\$false',
        'machine-cleanup-approval\.md',
        'machine-cleanup-before\.json',
        'machine-cleanup-after\.json',
        'machine-cleanup-result\.json',
        'machine-cleanup-result\.md',
        'Write-YuneWindowsStateSnapshot',
        'Get-YuneWindowsMachineResidue',
        'residue_groups',
        'approval_required',
        'PendingFileRenameOperations',
        'ApprovedPendingRenameEntries',
        '(?s)function Clear-YuneWindowsPendingRenameOperations\s*\{\s*param\(\s*\[string\[\]\]\$ApprovedEntries',
        'Get-PendingRenameOperationTokenFromResidue',
        'Clear-YuneWindowsPendingRenameOperations\s+-ApprovedEntries\s+\$ApprovedPendingRenameEntries',
        'HashSet\[string\]',
        'Assert-CleanupPlanInstallDir',
        'Assert-CleanupPlanProvenance',
        'Assert-CleanupPlanResidueGroups',
        'Assert-CleanupPlanCoversCurrentResidue',
        'Set-ItemProperty',
        'Remove-Item',
        '-LiteralPath',
        'cleanup_plan_generated_at',
        'cleanup_plan_residue_detector',
        'cleanup_plan_current_residue_covered',
        'Cleanup plan generated_at',
        'Cleanup plan residue detector',
        'Cleanup plan current residue covered',
        'Failure stage'
    )) {
    if ($Source -notmatch $Required) {
        throw "approved machine cleanup script is missing required pattern: $Required"
    }
}

foreach ($RequiredSupport in @(
        '(?s)function Require-ApprovedMachineCleanupContext\s*\{',
        'Test-IsAdministrator',
        '\[Threading\.Thread\]::CurrentThread\.ApartmentState\s+-ne\s+"STA"',
        'elevated STA PowerShell session after approval'
    )) {
    if ($SupportSource -notmatch $RequiredSupport) {
        throw "live smoke support is missing approved cleanup context pattern: $RequiredSupport"
    }
}

$MatchingPlan = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
}
Assert-CleanupPlanInstallDir `
    -Plan $MatchingPlan `
    -InstallDir "C:\Users\example\AppData\Local\Yune\WindowsIme" `
    -Context "matching cleanup plan"

$MismatchedPlan = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\OtherIme"
}
$MismatchThrew = $false
try {
    Assert-CleanupPlanInstallDir `
        -Plan $MismatchedPlan `
        -InstallDir "C:\Users\example\AppData\Local\Yune\WindowsIme" `
        -Context "mismatched cleanup plan"
}
catch {
    $MismatchThrew = $true
    if ($_.Exception.Message -notmatch "install_dir mismatch") {
        throw "cleanup plan install-dir mismatch error was not specific: $($_.Exception.Message)"
    }
}
if (-not $MismatchThrew) {
    throw "cleanup plan install-dir validation accepted a mismatched install directory"
}

$ValidProvenancePlan = [pscustomobject]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = $true
}
Assert-CleanupPlanProvenance `
    -Plan $ValidProvenancePlan `
    -Context "valid cleanup plan"

$StringTypedProvenancePlan = [pscustomobject]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = "false"
    machine_state_checked = "true"
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = "true"
}
$StringTypedProvenanceThrew = $false
try {
    Assert-CleanupPlanProvenance `
        -Plan $StringTypedProvenancePlan `
        -Context "string-typed cleanup plan"
}
catch {
    $StringTypedProvenanceThrew = $true
    if ($_.Exception.Message -notmatch "machine_state_changed must be a JSON boolean") {
        throw "cleanup plan provenance string-boolean error was not specific: $($_.Exception.Message)"
    }
}
if (-not $StringTypedProvenanceThrew) {
    throw "cleanup plan provenance validation accepted string-typed JSON booleans"
}

$ValidResidueGroupsPlan = [pscustomobject]@{
    residue_groups = @(
        [pscustomobject]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
            approval_required = $true
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
        }
    )
}
Assert-CleanupPlanResidueGroups `
    -Plan $ValidResidueGroupsPlan `
    -Context "valid residue cleanup plan"

$StringTypedResidueGroupsPlan = [pscustomobject]@{
    residue_groups = @(
        [pscustomobject]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
            approval_required = "true"
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
        }
    )
}
$StringTypedResidueGroupsThrew = $false
try {
    Assert-CleanupPlanResidueGroups `
        -Plan $StringTypedResidueGroupsPlan `
        -Context "string-typed residue cleanup plan"
}
catch {
    $StringTypedResidueGroupsThrew = $true
    if ($_.Exception.Message -notmatch "approval_required must be a JSON boolean") {
        throw "cleanup plan residue string-boolean error was not specific: $($_.Exception.Message)"
    }
}
if (-not $StringTypedResidueGroupsThrew) {
    throw "cleanup plan residue validation accepted string-typed approval_required"
}

$MatchingCurrentResidue = [pscustomobject]@{
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
}
Assert-CleanupPlanCoversCurrentResidue `
    -Plan $ValidResidueGroupsPlan `
    -CurrentResidue $MatchingCurrentResidue `
    -Context "current-residue cleanup plan"

Invoke-Expression (Get-CleanupScriptFunctionDefinition `
        -ScriptSource $Source `
        -FunctionName "Resolve-YuneWindowsSystemFileResiduePath")
$System32Root = [System.IO.Path]::GetFullPath((Join-Path $env:SystemRoot "System32"))
$DirectSystem32Leftover = Join-Path $System32Root "YuneWindows.dll.old.0"
$ResolvedDirectSystem32Leftover = Resolve-YuneWindowsSystemFileResiduePath -Path $DirectSystem32Leftover
if (-not [string]::Equals(
        $ResolvedDirectSystem32Leftover,
        [System.IO.Path]::GetFullPath($DirectSystem32Leftover),
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "filesystem residue resolver rejected a direct YuneWindows System32 leftover"
}

$NestedSystem32Leftover = Join-Path (Join-Path $System32Root "drivers") "YuneWindows.dll.old.0"
$NestedSystem32Threw = $false
try {
    Resolve-YuneWindowsSystemFileResiduePath -Path $NestedSystem32Leftover | Out-Null
}
catch {
    $NestedSystem32Threw = $true
    if ($_.Exception.Message -notmatch "direct Windows system YuneWindows file") {
        throw "nested System32 residue rejection did not name the direct-file boundary: $($_.Exception.Message)"
    }
}
if (-not $NestedSystem32Threw) {
    throw "filesystem residue resolver accepted a nested System32 YuneWindows path"
}

$MissingCurrentMachineResidue = [pscustomobject]@{
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.1")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
}
$MissingCurrentMachineResidueThrew = $false
try {
    Assert-CleanupPlanCoversCurrentResidue `
        -Plan $ValidResidueGroupsPlan `
        -CurrentResidue $MissingCurrentMachineResidue `
        -Context "partial machine-residue cleanup plan"
}
catch {
    $MissingCurrentMachineResidueThrew = $true
    if ($_.Exception.Message -notmatch "current machine-state residue") {
        throw "cleanup plan current-residue error did not name machine-state residue: $($_.Exception.Message)"
    }
}
if (-not $MissingCurrentMachineResidueThrew) {
    throw "cleanup plan coverage validation accepted an unlisted current machine-state residue"
}

$MissingCurrentFilesystemResidue = [pscustomobject]@{
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.1")
}
$MissingCurrentFilesystemResidueThrew = $false
try {
    Assert-CleanupPlanCoversCurrentResidue `
        -Plan $ValidResidueGroupsPlan `
        -CurrentResidue $MissingCurrentFilesystemResidue `
        -Context "partial filesystem-residue cleanup plan"
}
catch {
    $MissingCurrentFilesystemResidueThrew = $true
    if ($_.Exception.Message -notmatch "current filesystem leftover") {
        throw "cleanup plan current-residue error did not name filesystem leftover: $($_.Exception.Message)"
    }
}
if (-not $MissingCurrentFilesystemResidueThrew) {
    throw "cleanup plan coverage validation accepted an unlisted current filesystem leftover"
}

$ExtraCleanupTargetPlan = [pscustomobject]@{
    residue_groups = @(
        [pscustomobject]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
            approval_required = $true
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @(
                "C:\Windows\System32\YuneWindows.dll.old.0",
                "C:\Windows\System32\YuneWindows-extra.dll.old.0"
            )
        }
    )
}
$ExtraCleanupTargetThrew = $false
try {
    Assert-CleanupPlanCoversCurrentResidue `
        -Plan $ExtraCleanupTargetPlan `
        -CurrentResidue $MatchingCurrentResidue `
        -Context "extra-target cleanup plan"
}
catch {
    $ExtraCleanupTargetThrew = $true
    if ($_.Exception.Message -notmatch "extra cleanup target") {
        throw "cleanup plan extra-target error did not name extra cleanup targets: $($_.Exception.Message)"
    }
}
if (-not $ExtraCleanupTargetThrew) {
    throw "cleanup plan coverage validation accepted cleanup targets that are absent from current residue"
}

$EmptyResidueGroupsPlan = [pscustomobject]@{
    residue_groups = @()
}
$EmptyResidueGroupsThrew = $false
try {
    Assert-CleanupPlanResidueGroups `
        -Plan $EmptyResidueGroupsPlan `
        -Context "empty residue cleanup plan"
}
catch {
    $EmptyResidueGroupsThrew = $true
    if ($_.Exception.Message -notmatch "residue_groups") {
        throw "cleanup plan empty-group error did not name residue_groups: $($_.Exception.Message)"
    }
}
if (-not $EmptyResidueGroupsThrew) {
    throw "cleanup plan residue validation accepted an empty residue group list"
}

$MissingAffectedPathPlan = [pscustomobject]@{
    residue_groups = @(
        [pscustomobject]@{
            affected_path = ""
            approval_required = $true
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @()
        }
    )
}
$MissingAffectedPathThrew = $false
try {
    Assert-CleanupPlanResidueGroups `
        -Plan $MissingAffectedPathPlan `
        -Context "missing-path cleanup plan"
}
catch {
    $MissingAffectedPathThrew = $true
    if ($_.Exception.Message -notmatch "affected_path") {
        throw "cleanup plan residue validation error did not name affected_path: $($_.Exception.Message)"
    }
}
if (-not $MissingAffectedPathThrew) {
    throw "cleanup plan residue validation accepted a group without affected_path"
}

$NoResidueEntriesPlan = [pscustomobject]@{
    residue_groups = @(
        [pscustomobject]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
            approval_required = $true
            pending_rename_entries = @()
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @()
        }
    )
}
$NoResidueEntriesThrew = $false
try {
    Assert-CleanupPlanResidueGroups `
        -Plan $NoResidueEntriesPlan `
        -Context "entryless cleanup plan"
}
catch {
    $NoResidueEntriesThrew = $true
    if ($_.Exception.Message -notmatch "residue entry") {
        throw "cleanup plan residue validation error did not name missing residue entries: $($_.Exception.Message)"
    }
}
if (-not $NoResidueEntriesThrew) {
    throw "cleanup plan residue validation accepted a group without residue entries"
}

$MutatingPlan = [pscustomobject]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = $true
    machine_state_checked = $true
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = $true
}
$MutatingPlanThrew = $false
try {
    Assert-CleanupPlanProvenance `
        -Plan $MutatingPlan `
        -Context "mutating cleanup plan"
}
catch {
    $MutatingPlanThrew = $true
    if ($_.Exception.Message -notmatch "machine_state_changed=false") {
        throw "cleanup plan provenance error did not name machine_state_changed=false: $($_.Exception.Message)"
    }
}
if (-not $MutatingPlanThrew) {
    throw "cleanup plan provenance validation accepted machine_state_changed=true"
}

$WrongDetectorPlan = [pscustomobject]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    residue_detector = "OtherDetector"
    requires_current_session_approval = $true
}
$WrongDetectorThrew = $false
try {
    Assert-CleanupPlanProvenance `
        -Plan $WrongDetectorPlan `
        -Context "wrong-detector cleanup plan"
}
catch {
    $WrongDetectorThrew = $true
    if ($_.Exception.Message -notmatch "residue_detector=Get-YuneWindowsMachineResidue") {
        throw "cleanup plan provenance error did not name residue detector: $($_.Exception.Message)"
    }
}
if (-not $WrongDetectorThrew) {
    throw "cleanup plan provenance validation accepted an unexpected residue detector"
}

$MalformedGeneratedAtPlan = [pscustomobject]@{
    generated_at = "not-an-iso-date"
    machine_state_changed = $false
    machine_state_checked = $true
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = $true
}
$MalformedGeneratedAtThrew = $false
try {
    Assert-CleanupPlanProvenance `
        -Plan $MalformedGeneratedAtPlan `
        -Context "malformed-timestamp cleanup plan"
}
catch {
    $MalformedGeneratedAtThrew = $true
    if ($_.Exception.Message -notmatch "generated_at") {
        throw "cleanup plan provenance error did not name generated_at: $($_.Exception.Message)"
    }
}
if (-not $MalformedGeneratedAtThrew) {
    throw "cleanup plan provenance validation accepted malformed generated_at"
}

$GateIndex = $Source.IndexOf("Require-ApprovedMachineStateChange")
if ($GateIndex -lt 0) {
    throw "approved machine cleanup script is missing approval gate"
}
$ApprovalNoteIndex = $Source.IndexOf("Require-LiveSmokeApprovalNote")
$ApprovedContextIndex = $Source.IndexOf("Require-ApprovedMachineCleanupContext")
$ApprovalEvidenceIndex = $Source.IndexOf("Write-LiveSmokeApprovalEvidence")
$BeforeSnapshotIndex = $Source.IndexOf("machine-cleanup-before.json")
if ($ApprovalNoteIndex -lt $GateIndex) {
    throw "approved machine cleanup script must validate approval note after the approval gate"
}
if ($ApprovedContextIndex -lt $ApprovalNoteIndex) {
    throw "approved machine cleanup script must validate elevated STA context after the approval note"
}
if ($ApprovalEvidenceIndex -lt $ApprovedContextIndex) {
    throw "approved machine cleanup script must write approval evidence after validating elevated STA context"
}
if ($BeforeSnapshotIndex -ge 0 -and $ApprovalEvidenceIndex -gt $BeforeSnapshotIndex) {
    throw "approved machine cleanup script must write approval evidence before cleanup snapshots"
}
foreach ($Mutation in @("Set-ItemProperty", "Remove-Item", "Remove-ItemProperty")) {
    $MutationIndex = $Source.IndexOf($Mutation)
    if ($MutationIndex -ge 0 -and $MutationIndex -lt $ApprovedContextIndex) {
        throw "approved machine cleanup script has mutation before elevated STA context check: $Mutation"
    }
}
$CurrentResidueGuardIndex = $Source.IndexOf("Assert-CleanupPlanCoversCurrentResidue")
$PendingRenameMutationIndex = $Source.IndexOf("Clear-YuneWindowsPendingRenameOperations -ApprovedEntries")
$RegistryMutationIndex = $Source.IndexOf("Remove-Item -LiteralPath `$RegistryPath")
$FilesystemMutationIndex = $Source.IndexOf("Remove-Item -LiteralPath `$LeftoverPath")
$CoverageFailureIndex = $Source.IndexOf('failure_stage = "cleanup-plan-current-residue"')
if ($CurrentResidueGuardIndex -lt 0) {
    throw "approved machine cleanup script must compare the cleanup plan to current residue before cleanup"
}
if ($BeforeSnapshotIndex -ge 0 -and $CurrentResidueGuardIndex -lt $BeforeSnapshotIndex) {
    throw "approved machine cleanup script must capture a before snapshot before current-residue coverage validation"
}
if ($CoverageFailureIndex -lt 0) {
    throw "approved machine cleanup script must write failed result evidence when the plan does not cover current residue"
}
if ($CoverageFailureIndex -lt $CurrentResidueGuardIndex) {
    throw "approved machine cleanup script must only write current-residue coverage failure after checking coverage"
}
if ($Source -notmatch '(?s)catch\s*\{(?s:.*?)failure_stage\s*=\s*"cleanup-plan-current-residue"(?s:.*?)cleanup_plan_current_residue_covered\s*=\s*\$false(?s:.*?)Write-CleanupEvidence') {
    throw "approved machine cleanup script must catch current-residue coverage failure and write durable failed cleanup evidence"
}
if ($Source -notmatch '(?s)catch\s*\{(?s:.*?)failure_stage\s*=\s*"machine-cleanup-before-snapshot"(?s:.*?)Write-CleanupEvidence') {
    throw "approved machine cleanup script must catch before-snapshot failures and write durable failed cleanup evidence"
}
if ($Source -notmatch '(?s)catch\s*\{(?s:.*?)failure_stage\s*=\s*"machine-cleanup-after-snapshot"(?s:.*?)Write-CleanupEvidence') {
    throw "approved machine cleanup script must catch after-snapshot failures and write durable failed cleanup evidence"
}
foreach ($MutationIndex in @($PendingRenameMutationIndex, $RegistryMutationIndex, $FilesystemMutationIndex)) {
    if ($MutationIndex -ge 0 -and $CurrentResidueGuardIndex -gt $MutationIndex) {
        throw "approved machine cleanup script must validate current residue before cleanup mutations"
    }
    if ($MutationIndex -ge 0 -and $CoverageFailureIndex -gt $MutationIndex) {
        throw "approved machine cleanup script must write current-residue coverage failure evidence before cleanup mutations"
    }
}
foreach ($Mutation in @("Set-ItemProperty", "Remove-Item", "Remove-ItemProperty")) {
    $MutationIndex = $Source.IndexOf($Mutation)
    if ($MutationIndex -ge 0 -and $MutationIndex -lt $GateIndex) {
        throw "approved machine cleanup script has mutation before approval gate: $Mutation"
    }
}

$TempDir = Join-Path $env:TEMP "yune-windows\m01-approved-machine-cleanup-test"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$PlanPath = Join-Path $TempDir "machine-cleanup-plan.json"
$EvidenceDir = Join-Path $TempDir "evidence"
$Plan = [ordered]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    requires_current_session_approval = $true
    blocked_live_preflight = $true
    residue_summary = [ordered]@{
        machine_state_issue_count = 1
        pending_rename_count = 1
        registry_entry_count = 0
        registry_check_failure_count = 0
        filesystem_leftover_count = 1
        affected_path_count = 1
    }
    residue_groups = @(
        [ordered]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
            approval_required = $true
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
        }
    )
} | ConvertTo-Json -Depth 8
$Plan | Out-File -LiteralPath $PlanPath -Encoding utf8

$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CleanupScript `
        -CleanupPlanPath $PlanPath `
        -EvidenceDir $EvidenceDir 2>&1
    $CleanupExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
}
$Text = ($Output | Out-String)
if ($CleanupExitCode -eq 0) {
    throw "approved machine cleanup script unexpectedly succeeded without approval"
}
if ($Text -notmatch "without explicit approval") {
    throw "approved machine cleanup script did not report approval gate. Output: $Text"
}
if (Test-Path -LiteralPath (Join-Path $EvidenceDir "machine-cleanup-before.json")) {
    throw "approved machine cleanup script wrote before snapshot without approval"
}
if (Test-Path -LiteralPath (Join-Path $EvidenceDir "machine-cleanup-after.json")) {
    throw "approved machine cleanup script wrote after snapshot without approval"
}

$PlanText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\plans\history\m01-plan-windows-product.md")
foreach ($RequiredPlanText in @(
        'tools\clear-yune-windows-machine-residue.ps1',
        'tools\test-approved-machine-cleanup-contract.ps1',
        'docs\evidence\m01\installer\machine-cleanup-approval.md',
        'docs\evidence\m01\installer\machine-cleanup-before.json',
        'docs\evidence\m01\installer\machine-cleanup-after.json',
        'docs\evidence\m01\installer\machine-cleanup-result.md'
    )) {
    if ($PlanText -notmatch [regex]::Escape($RequiredPlanText)) {
        throw "active plan is missing approved machine cleanup reference: $RequiredPlanText"
    }
}

Write-Host "Approved machine cleanup script is gated and evidence-backed."
