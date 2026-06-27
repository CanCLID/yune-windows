param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-approval-evidence-test"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP "yune-windows"))
if (-not $OutputDir.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to clean output directory outside $AllowedRoot"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null
$ExistingBrowserPath = Join-Path $OutputDir "browser\msedge.exe"
New-Item -ItemType Directory -Force (Split-Path -Parent $ExistingBrowserPath) | Out-Null
"" | Out-File -LiteralPath $ExistingBrowserPath -Encoding ascii
$MissingBrowserPath = Join-Path $OutputDir "missing-browser\msedge.exe"

function Write-EvidenceFile([string]$RelativePath, [string]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Content | Out-File -LiteralPath $Path -Encoding utf8
}

function Write-MachineCleanupPlanEvidence {
    param(
        [string]$GeneratedAt = "2026-06-25T08:20:00.0000000-07:00",
        [string]$ResidueDetector = "Get-YuneWindowsMachineResidue",
        [int]$ResidueGroupCount = 2,
        [string]$InstallDir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    )

    $ResidueGroups = @()
    for ($Index = 0; $Index -lt $ResidueGroupCount; $Index++) {
        $ResidueGroups += [ordered]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.$Index"
            approval_required = $true
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: *1\??\C:\Windows\System32\YuneWindows.dll.old.$Index")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.$Index")
        }
    }

    $Plan = [ordered]@{
        generated_at = $GeneratedAt
        machine_state_changed = $false
        machine_state_checked = $true
        install_dir = $InstallDir
        residue_detector = $ResidueDetector
        requires_current_session_approval = $true
        residue_groups = $ResidueGroups
    }
    Write-EvidenceFile `
        "p2-win01-installer\machine-cleanup-plan.json" `
        ($Plan | ConvertTo-Json -Depth 8)
}

function Write-OverbroadMachineCleanupPlanEvidence {
    $Plan = [ordered]@{
        generated_at = "2026-06-25T08:20:00.0000000-07:00"
        machine_state_changed = $false
        machine_state_checked = $true
        install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
        residue_detector = "Get-YuneWindowsMachineResidue"
        requires_current_session_approval = $true
        residue_groups = @(
            [ordered]@{
                affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
                approval_required = $true
                pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: *1\??\C:\Windows\System32\YuneWindows.dll.old.0")
                registry_entries = @()
                registry_check_failures = @()
                machine_state_entries = @()
                filesystem_leftovers = @(
                    "C:\Windows\System32\YuneWindows.dll.old.0",
                    "C:\Windows\System32\YuneWindows-extra.dll.old.0"
                )
            },
            [ordered]@{
                affected_path = "C:\Windows\System32\YuneWindows.dll.old.1"
                approval_required = $true
                pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: *1\??\C:\Windows\System32\YuneWindows.dll.old.1")
                registry_entries = @()
                registry_check_failures = @()
                machine_state_entries = @()
                filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.1")
            }
        )
    }
    Write-EvidenceFile `
        "p2-win01-installer\machine-cleanup-plan.json" `
        ($Plan | ConvertTo-Json -Depth 8)
}

function Write-UnactionableMachineCleanupPlanEvidence {
    $Plan = [ordered]@{
        generated_at = "2026-06-25T08:20:00.0000000-07:00"
        machine_state_changed = $false
        machine_state_checked = $true
        install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
        residue_detector = "Get-YuneWindowsMachineResidue"
        requires_current_session_approval = $true
        residue_groups = @(
            [ordered]@{
                affected_path = ""
                approval_required = $false
                pending_rename_entries = @()
                registry_entries = @()
                registry_check_failures = @()
                machine_state_entries = @()
                filesystem_leftovers = @()
            },
            [ordered]@{
                affected_path = "C:\Windows\System32\YuneWindows.dll.old.1"
                approval_required = $true
                pending_rename_entries = @()
                registry_entries = @()
                registry_check_failures = @()
                machine_state_entries = @()
                filesystem_leftovers = @()
            }
        )
    }
    Write-EvidenceFile `
        "p2-win01-installer\machine-cleanup-plan.json" `
        ($Plan | ConvertTo-Json -Depth 8)
}

function Write-MachineCleanupSnapshotEvidence {
    Write-EvidenceFile "p2-win01-installer\machine-cleanup-before.json" @'
{
  "captured_at": "2026-06-25T08:50:00.0000000-07:00",
  "machine_state_checked": true,
  "machine_state_issues": [
    "PendingFileRenameOperations contains YuneWindows residue: *1\\??\\C:\\Windows\\System32\\YuneWindows.dll.old.0",
    "PendingFileRenameOperations contains YuneWindows residue: *1\\??\\C:\\Windows\\System32\\YuneWindows.dll.old.1"
  ],
  "filesystem_leftovers": [
    "C:\\Windows\\System32\\YuneWindows.dll.old.0",
    "C:\\Windows\\System32\\YuneWindows.dll.old.1"
  ]
}
'@

    Write-EvidenceFile "p2-win01-installer\machine-cleanup-after.json" @'
{
  "captured_at": "2026-06-25T08:55:00.0000000-07:00",
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
'@
}

function Write-CleanBeforeMachineCleanupSnapshotEvidence {
    Write-EvidenceFile "p2-win01-installer\machine-cleanup-before.json" @'
{
  "captured_at": "2026-06-25T08:50:00.0000000-07:00",
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
'@

    Write-EvidenceFile "p2-win01-installer\machine-cleanup-after.json" @'
{
  "captured_at": "2026-06-25T08:55:00.0000000-07:00",
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
'@
}

function Write-MismatchedBeforeMachineCleanupSnapshotEvidence {
    Write-EvidenceFile "p2-win01-installer\machine-cleanup-before.json" @'
{
  "captured_at": "2026-06-25T08:50:00.0000000-07:00",
  "machine_state_checked": true,
  "machine_state_issues": ["PendingFileRenameOperations contains YuneWindows residue: *1\\??\\C:\\Windows\\System32\\OtherYuneWindows.dll.old.9"],
  "filesystem_leftovers": ["C:\\Windows\\System32\\OtherYuneWindows.dll.old.9"]
}
'@

    Write-EvidenceFile "p2-win01-installer\machine-cleanup-after.json" @'
{
  "captured_at": "2026-06-25T08:55:00.0000000-07:00",
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
'@
}

function Invoke-TestAudit([string]$Name) {
    $JsonPath = Join-Path $OutputDir "$Name.json"
    $MarkdownPath = Join-Path $OutputDir "$Name.md"
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    if (-not (Test-Path -LiteralPath $JsonPath)) {
        throw "audit did not write $JsonPath"
    }
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

Write-EvidenceFile "p2-win01-bootstrap\repo-state.md" "repo state"
Write-EvidenceFile "p2-win01-bootstrap\reference-audit.md" "reference audit"
Write-EvidenceFile "p2-win01-bootstrap\process-model.md" "process model"
Write-EvidenceFile "p2-win01-bootstrap\first-smoke-target.md" "first smoke"
Write-EvidenceFile "p2-win01-yune-host\result.json" '{"status":{"schema_id":"jyut6ping3"}}'
Write-EvidenceFile "p2-win01-tsf-smoke\server-ipc-smoke.md" "server ipc smoke"
Write-EvidenceFile "p2-win01-candidate-window\build-preflight.md" "candidate preflight"
Write-EvidenceFile "p2-win01-settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "p2-win01-settings\webview2-spike.md" 'Decision: `defer-settings`'
Write-EvidenceFile "p2-win01-installer\live-preflight.json" '{"machine_state_changed":false}'
Write-EvidenceFile "p2-win01-installer\install-preflight.json" '{"machine_state_changed":false}'

Write-EvidenceFile "p2-win01-tsf-smoke\machine-state-gates.md" @'
# Machine-State Approval Gates

Pass.

Observed output:

```text
Machine-state approval gates refused unapproved install and uninstall runs.
```

## Covered Scripts

- `tools\install-yune-windows-ime.ps1`
- `tools\uninstall-yune-windows-ime.ps1`
'@

$WeakAudit = Invoke-TestAudit "weak-approval"
$WeakGate = $WeakAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $WeakGate) {
    throw "audit did not emit approval-discipline gate"
}
if ($WeakGate.status -ne "invalid") {
    throw "audit should mark approval evidence invalid when it omits Notepad, Chromium, and live sequence refusals; got $($WeakGate.status)"
}

Write-EvidenceFile "p2-win01-tsf-smoke\machine-state-gates.md" @'
# Machine-State Approval Gates

Pass.

Observed output:

```text
Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs. Cleanup helper also refused before machine residue cleanup.
```

## Covered Scripts

- `tools\install-yune-windows-ime.ps1`
- `tools\uninstall-yune-windows-ime.ps1`
- `tools\clear-yune-windows-machine-residue.ps1`
- `tools\run-notepad-smoke.ps1`
- `tools\run-chromium-smoke.ps1`
- `tools\run-p2-win01-live-smoke.ps1`

The scripts were invoked without `-ApprovedMachineStateChange`; each refused
before registration, uninstall, machine residue cleanup, profile activation,
Notepad automation, Chromium automation, full live-sequence orchestration, or
cleanup could run.
'@

$MissingBlankNoteRefusalAudit = Invoke-TestAudit "missing-blank-note-refusal"
$MissingBlankNoteRefusalGate = $MissingBlankNoteRefusalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingBlankNoteRefusalGate) {
    throw "audit did not emit approval-discipline gate for missing blank-note refusal evidence"
}
if ($MissingBlankNoteRefusalGate.status -ne "invalid") {
    throw "audit should reject approval evidence that omits blank approval-note refusals, got $($MissingBlankNoteRefusalGate.status)"
}

Write-EvidenceFile "p2-win01-tsf-smoke\machine-state-gates.md" @'
# Machine-State Approval Gates

Pass.

Observed output:

```text
Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs. Cleanup helper also refused before machine residue cleanup. Standalone approved machine-state scripts also refused blank or approval-brief placeholder approval notes before machine-state work.
```

## Covered Scripts

- `tools\install-yune-windows-ime.ps1`
- `tools\uninstall-yune-windows-ime.ps1`
- `tools\clear-yune-windows-machine-residue.ps1`
- `tools\run-notepad-smoke.ps1`
- `tools\run-chromium-smoke.ps1`
- `tools\run-p2-win01-live-smoke.ps1`

The scripts were invoked without `-ApprovedMachineStateChange`; each refused
before registration, uninstall, machine residue cleanup, profile activation,
Notepad automation, Chromium automation, full live-sequence orchestration, or
cleanup could run.

The standalone install, uninstall, machine-residue cleanup, Notepad smoke, and
Chromium smoke scripts were also invoked with `-ApprovedMachineStateChange` but
without `-ApprovalNote`; each refused before elevation checks, TSF
registration, cleanup, profile activation, or app automation could run.
'@

$MissingLiveBlankNoteRefusalAudit = Invoke-TestAudit "missing-live-blank-note-refusal"
$MissingLiveBlankNoteRefusalGate = $MissingLiveBlankNoteRefusalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingLiveBlankNoteRefusalGate) {
    throw "audit did not emit approval-discipline gate for missing full live blank-note refusal evidence"
}
if ($MissingLiveBlankNoteRefusalGate.status -ne "invalid") {
    throw "audit should reject approval evidence that omits the full live blank approval-note refusal, got $($MissingLiveBlankNoteRefusalGate.status)"
}

Write-EvidenceFile "p2-win01-tsf-smoke\machine-state-gates.md" @'
# Machine-State Approval Gates

Pass.

Observed output:

```text
Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs. Cleanup helper also refused before machine residue cleanup. Standalone approved machine-state scripts and the full live sequence also refused blank or approval-brief placeholder approval notes before post-approval context checks or machine-state work.
```

## Covered Scripts

- `tools\install-yune-windows-ime.ps1`
- `tools\uninstall-yune-windows-ime.ps1`
- `tools\clear-yune-windows-machine-residue.ps1`
- `tools\run-notepad-smoke.ps1`
- `tools\run-chromium-smoke.ps1`
- `tools\run-p2-win01-live-smoke.ps1`

The scripts were invoked without `-ApprovedMachineStateChange`; each refused
before registration, uninstall, machine residue cleanup, profile activation,
Notepad automation, Chromium automation, full live-sequence orchestration, or
cleanup could run.

The standalone install, uninstall, machine-residue cleanup, Notepad smoke, and
Chromium smoke scripts were also invoked with `-ApprovedMachineStateChange` but
without `-ApprovalNote`; each refused before elevation checks, TSF
registration, cleanup, profile activation, or app automation could run.

The full live sequence was also invoked with `-ApprovedMachineStateChange` but
without `-ApprovalNote`; it refused before elevated/STA context checks,
command transcript writes, profile-probe build, install, registration, app
automation, or cleanup could run.
'@

$MissingApprovalNoteAudit = Invoke-TestAudit "missing-live-approval-note"
$MissingApprovalNoteGate = $MissingApprovalNoteAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingApprovalNoteGate) {
    throw "audit did not emit approval-discipline gate for missing approval-note evidence"
}
if ($MissingApprovalNoteGate.status -ne "preflight") {
    throw "audit should treat complete refusal evidence without live approval-note evidence as preflight, got $($MissingApprovalNoteGate.status)"
}
if ($MissingApprovalNoteGate.notes -match "approved live sequence and cleanup evidence record") {
    throw "preflight approval-discipline notes must not claim approved live/cleanup evidence has already been recorded"
}
if ($MissingApprovalNoteGate.notes -notmatch "Complete approval-discipline closeout requires approved live evidence") {
    throw "preflight approval-discipline notes must say approved live evidence is still required"
}

Write-EvidenceFile "p2-win01-installer\approval-brief.md" @'
# P2-WIN01 Approval Brief

Date: 2026-06-25T09:00:00.0000000-07:00

Current residue source: C:\tmp\current-residue.json

Prep validation status: prep-preflight-ready
'@
Write-EvidenceFile "p2-win01-installer\elevated-live-smoke-prep-validation-result.json" @'
{
  "generated_at": "2026-06-25T09:05:00.0000000-07:00",
  "status": "prep-preflight-invalid",
  "elevated_process_started": false,
  "machine_state_changed_before_elevated_process": false,
  "error_message": "prep preflight machine_residue_source must not point to itself."
}
'@
$StaleApprovalBriefAudit = Invoke-TestAudit "stale-approval-brief"
$StaleApprovalBriefGate = $StaleApprovalBriefAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StaleApprovalBriefGate) {
    throw "audit did not emit approval-discipline gate for stale approval brief evidence"
}
if ($StaleApprovalBriefGate.notes -notmatch "approval brief is stale relative to latest prep validation") {
    throw "approval-discipline notes must call out stale approval-brief prep evidence, got: $($StaleApprovalBriefGate.notes)"
}

Write-EvidenceFile "p2-win01-installer\approval-brief.md" @'
# P2-WIN01 Approval Brief

Date: 2026-06-25T09:10:00.0000000-07:00

Current residue source: Get-YuneWindowsMachineResidue

Prep validation status: prep-preflight-ready
'@
Write-EvidenceFile "p2-win01-installer\elevated-live-smoke-prep-validation-result.json" @'
{
  "generated_at": "2026-06-25T09:09:00.0000000-07:00",
  "status": "prep-preflight-ready",
  "approved_machine_state_change": "false",
  "elevated_process_started": "false",
  "exit_code": null,
  "error_message": "",
  "transcript_exists": "false",
  "machine_state_changed_before_elevated_process": "false"
}
'@
$StringTypedPrepValidationAudit = Invoke-TestAudit "string-typed-prep-validation-booleans"
$StringTypedPrepValidationGate = $StringTypedPrepValidationAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StringTypedPrepValidationGate) {
    throw "audit did not emit approval-discipline gate for string-typed prep-validation booleans"
}
if ($StringTypedPrepValidationGate.notes -notmatch "latest prep-validation boolean fields are not JSON booleans: approved_machine_state_change, elevated_process_started, transcript_exists, machine_state_changed_before_elevated_process") {
    throw "approval-discipline notes must call out malformed prep-validation boolean schema, got: $($StringTypedPrepValidationGate.notes)"
}

Write-EvidenceFile "p2-win01-installer\approval-brief.md" @'
# P2-WIN01 Approval Brief

Date: 2026-06-25T09:10:00.0000000-07:00

Current residue source: Get-YuneWindowsMachineResidue

Prep validation status: prep-preflight-ready

Launcher status: elevation-canceled
Elevated process started: False
Fresh approval required before retry: True
'@
Write-EvidenceFile "p2-win01-installer\elevated-live-smoke-launch-result.json" @'
{
  "generated_at": "2026-06-25T09:09:00.0000000-07:00",
  "status": "elevation-canceled",
  "approved_machine_state_change": true,
  "approval_note": "User approved elevated live smoke in this session.",
  "elevated_process_started": false,
  "exit_code": null,
  "error_message": "The operation was canceled by the user.",
  "transcript_exists": false,
  "machine_state_changed_before_elevated_process": false
}
'@
$CanceledLauncherAudit = Invoke-TestAudit "canceled-live-launcher"
$CanceledLauncherGate = $CanceledLauncherAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $CanceledLauncherGate) {
    throw "audit did not emit approval-discipline gate for canceled launcher evidence"
}
if ($CanceledLauncherGate.notes -notmatch "latest single-UAC launcher did not start; fresh approval is required before retry") {
    throw "approval-discipline notes must call out no-start launcher approval expiry, got: $($CanceledLauncherGate.notes)"
}

Write-EvidenceFile "p2-win01-installer\approval-brief.md" @'
# P2-WIN01 Approval Brief

Date: 2026-06-25T09:12:00.0000000-07:00

Current residue source: Get-YuneWindowsMachineResidue

Prep validation status: prep-preflight-ready

Launcher status: elevation-canceled
Elevated process started: False
Fresh approval required before retry: True
'@
Write-EvidenceFile "p2-win01-installer\elevated-live-smoke-launch-result.json" @'
{
  "generated_at": "2026-06-25T09:13:00.0000000-07:00",
  "status": "elevation-canceled",
  "approved_machine_state_change": true,
  "approval_note": "User approved elevated live smoke in this session.",
  "elevated_process_started": false,
  "exit_code": null,
  "error_message": "The operation was canceled by the user.",
  "transcript_exists": false,
  "machine_state_changed_before_elevated_process": false
}
'@
$StaleLauncherBriefAudit = Invoke-TestAudit "stale-launcher-approval-brief"
$StaleLauncherBriefGate = $StaleLauncherBriefAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StaleLauncherBriefGate) {
    throw "audit did not emit approval-discipline gate for stale launcher approval brief evidence"
}
if ($StaleLauncherBriefGate.notes -notmatch "approval brief is stale relative to latest single-UAC launcher") {
    throw "approval-discipline notes must call out stale approval-brief launcher evidence, got: $($StaleLauncherBriefGate.notes)"
}

Write-EvidenceFile "p2-win01-installer\elevated-live-smoke-launch-result.json" @'
{
  "generated_at": "2026-06-25T09:14:00.0000000-07:00",
  "status": "failed",
  "approved_machine_state_change": true,
  "approval_note": "User approved elevated live smoke in this session.",
  "elevated_process_started": true,
  "exit_code": 1,
  "error_message": "Elevated live smoke exited with code 1.",
  "transcript_exists": false,
  "machine_state_changed_before_elevated_process": false,
  "transcript_path": "C:\\evidence\\missing-elevated-live-smoke-transcript.txt"
}
'@
$StartedMissingTranscriptAudit = Invoke-TestAudit "started-launcher-missing-transcript"
$StartedMissingTranscriptGate = $StartedMissingTranscriptAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StartedMissingTranscriptGate) {
    throw "audit did not emit approval-discipline gate for started launcher without transcript evidence"
}
if ($StartedMissingTranscriptGate.notes -notmatch "latest single-UAC launcher started without transcript evidence") {
    throw "approval-discipline notes must call out started launcher missing transcript evidence, got: $($StartedMissingTranscriptGate.notes)"
}

Write-EvidenceFile "p2-win01-installer\elevated-live-smoke-launch-result.json" @'
{
  "generated_at": "2026-06-25T09:15:00.0000000-07:00",
  "status": "elevation-canceled",
  "approved_machine_state_change": "true",
  "approval_note": "User approved elevated live smoke in this session.",
  "elevated_process_started": "false",
  "exit_code": null,
  "error_message": "The operation was canceled by the user.",
  "transcript_exists": "false",
  "machine_state_changed_before_elevated_process": "false",
  "transcript_path": "C:\\evidence\\string-typed-elevated-live-smoke-transcript.txt"
}
'@
$StringTypedLauncherAudit = Invoke-TestAudit "string-typed-launcher-booleans"
$StringTypedLauncherGate = $StringTypedLauncherAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StringTypedLauncherGate) {
    throw "audit did not emit approval-discipline gate for string-typed launcher booleans"
}
if ($StringTypedLauncherGate.notes -notmatch "latest single-UAC launcher boolean fields are not JSON booleans: approved_machine_state_change, elevated_process_started, transcript_exists, machine_state_changed_before_elevated_process") {
    throw "approval-discipline notes must call out malformed launcher boolean schema, got: $($StringTypedLauncherGate.notes)"
}
if ($StringTypedLauncherGate.notes -notmatch "latest single-UAC launcher did not start; fresh approval is required before retry") {
    throw "approval-discipline notes must still require fresh approval after malformed no-start launcher evidence, got: $($StringTypedLauncherGate.notes)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.md" @'
# Approved Machine Cleanup Result

Date: 2026-06-25T08:30:00.0000000-07:00

Status: passed
'@

$MissingCleanupApprovalAudit = Invoke-TestAudit "missing-cleanup-approval-note"
$MissingCleanupApprovalGate = $MissingCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for missing machine-cleanup approval evidence"
}
if ($MissingCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result evidence without cleanup approval evidence, got $($MissingCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune
'@

$IncompleteCleanupApprovalAudit = Invoke-TestAudit "incomplete-cleanup-approval-note"
$IncompleteCleanupApprovalGate = $IncompleteCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $IncompleteCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for incomplete machine-cleanup approval evidence"
}
if ($IncompleteCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject incomplete machine-cleanup approval evidence, got $($IncompleteCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: False

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: (auto-detect)
'@

$NonStaCleanupApprovalAudit = Invoke-TestAudit "non-sta-cleanup-approval-note"
$NonStaCleanupApprovalGate = $NonStaCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $NonStaCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for non-STA machine-cleanup approval evidence"
}
if ($NonStaCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup approval evidence without STA=True, got $($NonStaCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: (auto-detect)
'@

$AutoDetectCleanupApprovalAudit = Invoke-TestAudit "auto-detect-cleanup-browser-approval"
$AutoDetectCleanupApprovalGate = $AutoDetectCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $AutoDetectCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for auto-detect machine-cleanup browser evidence"
}
if ($AutoDetectCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup approval evidence that records Browser path as auto-detect instead of an actual path, got $($AutoDetectCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: C:\Program Files\Microsoft\Edge\Application\msedge.txt
'@

$NonExeCleanupApprovalAudit = Invoke-TestAudit "non-exe-cleanup-browser-approval"
$NonExeCleanupApprovalGate = $NonExeCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $NonExeCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for non-exe machine-cleanup browser evidence"
}
if ($NonExeCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup approval evidence whose Browser path is not an .exe, got $($NonExeCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: relative\install

Yune root: relative\yune

Browser path: $ExistingBrowserPath
"@

$RelativePathCleanupApprovalAudit = Invoke-TestAudit "relative-path-cleanup-approval"
$RelativePathCleanupApprovalGate = $RelativePathCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $RelativePathCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for relative-path machine-cleanup approval evidence"
}
if ($RelativePathCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup approval evidence that records relative install or Yune paths, got $($RelativePathCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $MissingBrowserPath
"@

$MissingBrowserCleanupApprovalAudit = Invoke-TestAudit "missing-browser-cleanup-approval"
$MissingBrowserCleanupApprovalGate = $MissingBrowserCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingBrowserCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for missing-browser machine-cleanup approval evidence"
}
if ($MissingBrowserCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup approval evidence whose Browser path does not exist, got $($MissingBrowserCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$StaleCleanupApprovalAudit = Invoke-TestAudit "stale-cleanup-approval-note"
$StaleCleanupApprovalGate = $StaleCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StaleCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for stale machine-cleanup approval evidence"
}
if ($StaleCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result evidence dated before cleanup approval evidence, got $($StaleCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.md" @'
# Approved Machine Cleanup Result

Date: 2026-06-25T09:00:00.0000000-07:00

Status: passed
'@
Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan_current_residue_covered": false
}
'@

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: <current-session cleanup approval note>

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$PlaceholderCleanupApprovalAudit = Invoke-TestAudit "placeholder-cleanup-approval-note"
$PlaceholderCleanupApprovalGate = $PlaceholderCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $PlaceholderCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for placeholder machine-cleanup approval evidence"
}
if ($PlaceholderCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject placeholder machine-cleanup approval-note evidence, got $($PlaceholderCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$StaleCleanupCoverageAudit = Invoke-TestAudit "stale-cleanup-current-residue-coverage"
$StaleCleanupCoverageGate = $StaleCleanupCoverageAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StaleCleanupCoverageGate) {
    throw "audit did not emit approval-discipline gate for stale machine-cleanup current-residue coverage"
}
if ($StaleCleanupCoverageGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result evidence that did not cover current residue, got $($StaleCleanupCoverageGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T08:30:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan_current_residue_covered": true
}
'@

$StaleCleanupResultJsonAudit = Invoke-TestAudit "stale-cleanup-result-json"
$StaleCleanupResultJsonGate = $StaleCleanupResultJsonAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StaleCleanupResultJsonGate) {
    throw "audit did not emit approval-discipline gate for stale machine-cleanup result JSON"
}
if ($StaleCleanupResultJsonGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON generated before cleanup approval, got $($StaleCleanupResultJsonGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan_current_residue_covered": true
}
'@

$MissingCleanupPlanProvenanceAudit = Invoke-TestAudit "missing-cleanup-plan-provenance"
$MissingCleanupPlanProvenanceGate = $MissingCleanupPlanProvenanceAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingCleanupPlanProvenanceGate) {
    throw "audit did not emit approval-discipline gate for missing cleanup-plan provenance"
}
if ($MissingCleanupPlanProvenanceGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON without cleanup-plan provenance, got $($MissingCleanupPlanProvenanceGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "C:\\Temp\\other-machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true
}
'@

$MismatchedCleanupPlanPathAudit = Invoke-TestAudit "mismatched-cleanup-plan-path"
$MismatchedCleanupPlanPathGate = $MismatchedCleanupPlanPathAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MismatchedCleanupPlanPathGate) {
    throw "audit did not emit approval-discipline gate for mismatched cleanup-plan path"
}
if ($MismatchedCleanupPlanPathGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON tied to a different cleanup-plan path, got $($MismatchedCleanupPlanPathGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true
}
'@

$MissingCleanupPlanFileAudit = Invoke-TestAudit "missing-cleanup-plan-file"
$MissingCleanupPlanFileGate = $MissingCleanupPlanFileAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingCleanupPlanFileGate) {
    throw "audit did not emit approval-discipline gate for missing cleanup-plan file"
}
if ($MissingCleanupPlanFileGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan file is missing, got $($MissingCleanupPlanFileGate.status)"
}

Write-MachineCleanupPlanEvidence -GeneratedAt "2026-06-25T08:19:00.0000000-07:00"
$MismatchedCleanupPlanTimestampAudit = Invoke-TestAudit "mismatched-cleanup-plan-timestamp"
$MismatchedCleanupPlanTimestampGate = $MismatchedCleanupPlanTimestampAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MismatchedCleanupPlanTimestampGate) {
    throw "audit did not emit approval-discipline gate for mismatched cleanup-plan timestamp"
}
if ($MismatchedCleanupPlanTimestampGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan timestamp differs from the plan file, got $($MismatchedCleanupPlanTimestampGate.status)"
}

Write-MachineCleanupPlanEvidence -ResidueDetector "OtherResidueDetector"
$MismatchedCleanupPlanDetectorAudit = Invoke-TestAudit "mismatched-cleanup-plan-detector"
$MismatchedCleanupPlanDetectorGate = $MismatchedCleanupPlanDetectorAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MismatchedCleanupPlanDetectorGate) {
    throw "audit did not emit approval-discipline gate for mismatched cleanup-plan detector"
}
if ($MismatchedCleanupPlanDetectorGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan detector differs from the plan file, got $($MismatchedCleanupPlanDetectorGate.status)"
}

Write-MachineCleanupPlanEvidence -ResidueGroupCount 1
$MismatchedCleanupPlanCountAudit = Invoke-TestAudit "mismatched-cleanup-plan-count"
$MismatchedCleanupPlanCountGate = $MismatchedCleanupPlanCountAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MismatchedCleanupPlanCountGate) {
    throw "audit did not emit approval-discipline gate for mismatched cleanup-plan count"
}
if ($MismatchedCleanupPlanCountGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan count differs from the plan file, got $($MismatchedCleanupPlanCountGate.status)"
}

Write-MachineCleanupPlanEvidence -InstallDir "C:\Users\example\AppData\Local\Yune\OtherIme"
$MismatchedCleanupPlanInstallDirAudit = Invoke-TestAudit "mismatched-cleanup-plan-install-dir"
$MismatchedCleanupPlanInstallDirGate = $MismatchedCleanupPlanInstallDirAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MismatchedCleanupPlanInstallDirGate) {
    throw "audit did not emit approval-discipline gate for mismatched cleanup-plan install dir"
}
if ($MismatchedCleanupPlanInstallDirGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan install dir differs from cleanup approval evidence, got $($MismatchedCleanupPlanInstallDirGate.status)"
}

Write-MachineCleanupPlanEvidence -GeneratedAt "2026-06-25T09:30:00.0000000-07:00"
Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T09:30:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true
}
'@

$FutureCleanupPlanAudit = Invoke-TestAudit "future-cleanup-plan-provenance"
$FutureCleanupPlanGate = $FutureCleanupPlanAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $FutureCleanupPlanGate) {
    throw "audit did not emit approval-discipline gate for future cleanup-plan provenance"
}
if ($FutureCleanupPlanGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup plan was generated after the result, got $($FutureCleanupPlanGate.status)"
}

Write-MachineCleanupPlanEvidence
Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": "2",
  "cleanup_plan_current_residue_covered": true
}
'@

$StringCleanupPlanCountAudit = Invoke-TestAudit "string-cleanup-plan-count"
$StringCleanupPlanCountGate = $StringCleanupPlanCountAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StringCleanupPlanCountGate) {
    throw "audit did not emit approval-discipline gate for string cleanup-plan count"
}
if ($StringCleanupPlanCountGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan residue group count is a string, got $($StringCleanupPlanCountGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": "true"
}
'@

$StringCleanupCoverageAudit = Invoke-TestAudit "string-cleanup-current-residue-coverage"
$StringCleanupCoverageGate = $StringCleanupCoverageAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StringCleanupCoverageGate) {
    throw "audit did not emit approval-discipline gate for string cleanup current-residue coverage"
}
if ($StringCleanupCoverageGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose current-residue coverage flag is a string, got $($StringCleanupCoverageGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": true,
  "approval_required": true
}
'@

$ChangedBeforeApprovalResultAudit = Invoke-TestAudit "changed-before-cleanup-approval-result"
$ChangedBeforeApprovalResultGate = $ChangedBeforeApprovalResultAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $ChangedBeforeApprovalResultGate) {
    throw "audit did not emit approval-discipline gate for cleanup result with pre-approval machine-state change"
}
if ($ChangedBeforeApprovalResultGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON that records machine-state change before approval evidence, got $($ChangedBeforeApprovalResultGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": false,
  "approval_required": false
}
'@

$MissingApprovalRequiredResultAudit = Invoke-TestAudit "missing-cleanup-approval-required-result"
$MissingApprovalRequiredResultGate = $MissingApprovalRequiredResultAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingApprovalRequiredResultGate) {
    throw "audit did not emit approval-discipline gate for cleanup result without approval-required marker"
}
if ($MissingApprovalRequiredResultGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON that does not record approval_required=true, got $($MissingApprovalRequiredResultGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": false,
  "approval_required": true,
  "remaining_machine_state_issues": ["PendingFileRenameOperations contains YuneWindows residue"],
  "remaining_filesystem_leftovers": [],
  "errors": []
}
'@

$RemainingMachineResidueResultAudit = Invoke-TestAudit "remaining-machine-residue-result"
$RemainingMachineResidueResultGate = $RemainingMachineResidueResultAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $RemainingMachineResidueResultGate) {
    throw "audit did not emit approval-discipline gate for cleanup result with remaining machine residue"
}
if ($RemainingMachineResidueResultGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON with remaining machine-state issues, got $($RemainingMachineResidueResultGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": false,
  "approval_required": true,
  "remaining_machine_state_issues": [],
  "remaining_filesystem_leftovers": ["C:\\Windows\\System32\\YuneWindows.dll.old.0"],
  "errors": []
}
'@

$RemainingFilesystemResidueResultAudit = Invoke-TestAudit "remaining-filesystem-residue-result"
$RemainingFilesystemResidueResultGate = $RemainingFilesystemResidueResultAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $RemainingFilesystemResidueResultGate) {
    throw "audit did not emit approval-discipline gate for cleanup result with remaining filesystem residue"
}
if ($RemainingFilesystemResidueResultGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON with remaining filesystem leftovers, got $($RemainingFilesystemResidueResultGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": false,
  "approval_required": true,
  "remaining_machine_state_issues": [],
  "remaining_filesystem_leftovers": [],
  "errors": ["filesystem cleanup failed"]
}
'@

$CleanupErrorResultAudit = Invoke-TestAudit "cleanup-error-result"
$CleanupErrorResultGate = $CleanupErrorResultAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $CleanupErrorResultGate) {
    throw "audit did not emit approval-discipline gate for cleanup result with errors"
}
if ($CleanupErrorResultGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON with cleanup errors, got $($CleanupErrorResultGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": false,
  "approval_required": true,
  "remaining_machine_state_issues": [],
  "remaining_filesystem_leftovers": [],
  "errors": []
}
'@

$MissingCleanupSnapshotsAudit = Invoke-TestAudit "missing-cleanup-snapshots"
$MissingCleanupSnapshotsGate = $MissingCleanupSnapshotsAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingCleanupSnapshotsGate) {
    throw "audit did not emit approval-discipline gate for cleanup result without before/after snapshots"
}
if ($MissingCleanupSnapshotsGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON without before/after cleanup snapshot provenance, got $($MissingCleanupSnapshotsGate.status)"
}

Write-MachineCleanupSnapshotEvidence

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.json" @'
{
  "generated_at": "2026-06-25T09:00:00.0000000-07:00",
  "status": "passed",
  "cleanup_plan": "docs\\evidence\\p2-win01-installer\\machine-cleanup-plan.json",
  "cleanup_plan_generated_at": "2026-06-25T08:20:00.0000000-07:00",
  "cleanup_plan_residue_detector": "Get-YuneWindowsMachineResidue",
  "cleanup_plan_residue_group_count": 2,
  "cleanup_plan_current_residue_covered": true,
  "machine_state_changed_before_approval": false,
  "approval_required": true,
  "before_snapshot": "docs\\evidence\\p2-win01-installer\\machine-cleanup-before.json",
  "after_snapshot": "docs\\evidence\\p2-win01-installer\\machine-cleanup-after.json",
  "remaining_machine_state_issues": [],
  "remaining_filesystem_leftovers": [],
  "errors": []
}
'@

Write-UnactionableMachineCleanupPlanEvidence
$UnactionableCleanupPlanAudit = Invoke-TestAudit "unactionable-cleanup-plan"
$UnactionableCleanupPlanGate = $UnactionableCleanupPlanAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $UnactionableCleanupPlanGate) {
    throw "audit did not emit approval-discipline gate for unactionable cleanup plan"
}
if ($UnactionableCleanupPlanGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup-plan residue groups are not approval-required and actionable, got $($UnactionableCleanupPlanGate.status)"
}

Write-MachineCleanupPlanEvidence

Write-CleanBeforeMachineCleanupSnapshotEvidence
$CleanBeforeCleanupSnapshotAudit = Invoke-TestAudit "clean-before-cleanup-snapshot"
$CleanBeforeCleanupSnapshotGate = $CleanBeforeCleanupSnapshotAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $CleanBeforeCleanupSnapshotGate) {
    throw "audit did not emit approval-discipline gate for clean before-cleanup snapshot"
}
if ($CleanBeforeCleanupSnapshotGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose before-cleanup snapshot has no current residue, got $($CleanBeforeCleanupSnapshotGate.status)"
}

Write-MismatchedBeforeMachineCleanupSnapshotEvidence
$MismatchedBeforeCleanupSnapshotAudit = Invoke-TestAudit "mismatched-before-cleanup-snapshot"
$MismatchedBeforeCleanupSnapshotGate = $MismatchedBeforeCleanupSnapshotAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MismatchedBeforeCleanupSnapshotGate) {
    throw "audit did not emit approval-discipline gate for before-cleanup snapshot not covered by cleanup plan"
}
if ($MismatchedBeforeCleanupSnapshotGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose before-cleanup snapshot residue is absent from the cleanup plan, got $($MismatchedBeforeCleanupSnapshotGate.status)"
}

Write-MachineCleanupSnapshotEvidence
Write-OverbroadMachineCleanupPlanEvidence
$OverbroadCleanupPlanAudit = Invoke-TestAudit "overbroad-cleanup-plan"
$OverbroadCleanupPlanGate = $OverbroadCleanupPlanAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $OverbroadCleanupPlanGate) {
    throw "audit did not emit approval-discipline gate for cleanup plan with extra cleanup targets"
}
if ($OverbroadCleanupPlanGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result JSON whose cleanup plan contains targets absent from the before-cleanup snapshot, got $($OverbroadCleanupPlanGate.status)"
}

Write-MachineCleanupPlanEvidence

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.md" @'
# Approved Machine Cleanup Result

Date: 2026-06-25T09:00:00.0000000-07:00

Status: failed
'@

$FailedCleanupResultMarkdownAudit = Invoke-TestAudit "failed-cleanup-result-markdown"
$FailedCleanupResultMarkdownGate = $FailedCleanupResultMarkdownAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $FailedCleanupResultMarkdownGate) {
    throw "audit did not emit approval-discipline gate for failed machine-cleanup result markdown"
}
if ($FailedCleanupResultMarkdownGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result markdown with failed status, got $($FailedCleanupResultMarkdownGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.md" @'
# Approved Machine Cleanup Result

Date: 2026-06-25T08:59:59.0000000-07:00

Status: passed
'@

$StaleCleanupResultMarkdownAudit = Invoke-TestAudit "stale-cleanup-result-markdown"
$StaleCleanupResultMarkdownGate = $StaleCleanupResultMarkdownAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StaleCleanupResultMarkdownGate) {
    throw "audit did not emit approval-discipline gate for stale machine-cleanup result markdown"
}
if ($StaleCleanupResultMarkdownGate.status -ne "invalid") {
    throw "audit should reject machine-cleanup result markdown dated before cleanup result JSON, got $($StaleCleanupResultMarkdownGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-result.md" @'
# Approved Machine Cleanup Result

Date: 2026-06-25T09:00:00.0000000-07:00

Status: passed
'@

$CompleteCleanupApprovalAudit = Invoke-TestAudit "complete-cleanup-approval-note"
$CompleteCleanupApprovalGate = $CompleteCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $CompleteCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for complete machine-cleanup approval evidence"
}
if ($CompleteCleanupApprovalGate.status -ne "preflight") {
    throw "audit should accept complete machine-cleanup approval while still waiting for live approval evidence, got $($CompleteCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $MissingBrowserPath
"@

$MissingBrowserCompleteCleanupApprovalAudit = Invoke-TestAudit "missing-browser-complete-cleanup-approval"
$MissingBrowserCompleteCleanupApprovalGate = $MissingBrowserCompleteCleanupApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingBrowserCompleteCleanupApprovalGate) {
    throw "audit did not emit approval-discipline gate for missing-browser complete machine-cleanup approval evidence"
}
if ($MissingBrowserCompleteCleanupApprovalGate.status -ne "invalid") {
    throw "audit should reject otherwise complete machine-cleanup approval whose Browser path does not exist, got $($MissingBrowserCompleteCleanupApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\machine-cleanup-approval.md" @"
# Machine Cleanup Approval

Date: 2026-06-25T08:45:00.0000000-07:00

Approval note: User approved elevated machine cleanup in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

Write-EvidenceFile "p2-win01-installer\approval.md" @'
# Live Smoke Approval

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune
'@

$IncompleteApprovalNoteAudit = Invoke-TestAudit "incomplete-live-approval-note"
$IncompleteApprovalNoteGate = $IncompleteApprovalNoteAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $IncompleteApprovalNoteGate) {
    throw "audit did not emit approval-discipline gate for incomplete approval-note evidence"
}
if ($IncompleteApprovalNoteGate.status -ne "invalid") {
    throw "audit should reject incomplete live approval-note evidence, got $($IncompleteApprovalNoteGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @"
# Live Smoke Approval

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$MissingApprovalTimestampAudit = Invoke-TestAudit "missing-approval-timestamp"
$MissingApprovalTimestampGate = $MissingApprovalTimestampAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingApprovalTimestampGate) {
    throw "audit did not emit approval-discipline gate for missing approval timestamp evidence"
}
if ($MissingApprovalTimestampGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence without a Date timestamp, got $($MissingApprovalTimestampGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @'
# Live Smoke Approval

Date: 2026-06-25Tnot-a-valid-time

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$MalformedApprovalTimestampAudit = Invoke-TestAudit "malformed-approval-timestamp"
$MalformedApprovalTimestampGate = $MalformedApprovalTimestampAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MalformedApprovalTimestampGate) {
    throw "audit did not emit approval-discipline gate for malformed approval timestamp evidence"
}
if ($MalformedApprovalTimestampGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence with a malformed Date timestamp, got $($MalformedApprovalTimestampGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @'
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$MissingApprovalContextAudit = Invoke-TestAudit "missing-approval-context"
$MissingApprovalContextGate = $MissingApprovalContextAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingApprovalContextGate) {
    throw "audit did not emit approval-discipline gate for missing approval context evidence"
}
if ($MissingApprovalContextGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence without administrator and STA context, got $($MissingApprovalContextGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @'
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: (auto-detect)
'@

$AutoDetectBrowserApprovalAudit = Invoke-TestAudit "auto-detect-browser-approval"
$AutoDetectBrowserApprovalGate = $AutoDetectBrowserApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $AutoDetectBrowserApprovalGate) {
    throw "audit did not emit approval-discipline gate for auto-detect browser approval evidence"
}
if ($AutoDetectBrowserApprovalGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence that records Browser path as auto-detect instead of an actual path, got $($AutoDetectBrowserApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @'
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: C:\Program Files\Microsoft\Edge\Application\msedge.txt
'@

$NonExeBrowserApprovalAudit = Invoke-TestAudit "non-exe-browser-approval"
$NonExeBrowserApprovalGate = $NonExeBrowserApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $NonExeBrowserApprovalGate) {
    throw "audit did not emit approval-discipline gate for non-exe live browser approval evidence"
}
if ($NonExeBrowserApprovalGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence whose Browser path is not an .exe, got $($NonExeBrowserApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @"
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: relative\install

Yune root: relative\yune

Browser path: $ExistingBrowserPath
"@

$RelativePathLiveApprovalAudit = Invoke-TestAudit "relative-path-live-approval"
$RelativePathLiveApprovalGate = $RelativePathLiveApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $RelativePathLiveApprovalGate) {
    throw "audit did not emit approval-discipline gate for relative-path live approval evidence"
}
if ($RelativePathLiveApprovalGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence that records relative install or Yune paths, got $($RelativePathLiveApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @"
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $MissingBrowserPath
"@

$MissingBrowserApprovalAudit = Invoke-TestAudit "missing-browser-live-approval"
$MissingBrowserApprovalGate = $MissingBrowserApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $MissingBrowserApprovalGate) {
    throw "audit did not emit approval-discipline gate for missing-browser live approval evidence"
}
if ($MissingBrowserApprovalGate.status -ne "invalid") {
    throw "audit should reject live approval-note evidence whose Browser path does not exist, got $($MissingBrowserApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @"
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: <current-session approval note>

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$PlaceholderLiveApprovalAudit = Invoke-TestAudit "placeholder-live-approval-note"
$PlaceholderLiveApprovalGate = $PlaceholderLiveApprovalAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $PlaceholderLiveApprovalGate) {
    throw "audit did not emit approval-discipline gate for placeholder live approval evidence"
}
if ($PlaceholderLiveApprovalGate.status -ne "invalid") {
    throw "audit should reject placeholder live approval-note evidence, got $($PlaceholderLiveApprovalGate.status)"
}

Write-EvidenceFile "p2-win01-installer\approval.md" @"
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $ExistingBrowserPath
"@

$StrongAudit = Invoke-TestAudit "strong-approval"
$StrongGate = $StrongAudit.gates | Where-Object { $_.id -eq "approval-discipline" } | Select-Object -First 1
if (-not $StrongGate) {
    throw "audit did not emit approval-discipline gate for strong evidence"
}
if ($StrongGate.status -ne "complete") {
    throw "audit should accept complete approval evidence, got $($StrongGate.status)"
}

Write-Host "Closeout audit classifies approval discipline preflight until approved live evidence exists."
