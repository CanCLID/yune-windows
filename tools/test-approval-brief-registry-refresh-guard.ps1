param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BriefScript = Join-Path $RepoRoot "tools\write-m01-approval-brief.ps1"
if (-not (Test-Path -LiteralPath $BriefScript)) {
    throw "missing approval brief writer: tools\write-m01-approval-brief.ps1"
}

$Source = Get-Content -Raw -LiteralPath $BriefScript
foreach ($Required in @(
        '[string]$ApprovalNote = ""',
        '[switch]$RefreshCurrentResidue',
        'Current residue source:',
        'Approval brief current-residue validation requires -CurrentResiduePath or -RefreshCurrentResidue.',
        'elseif ($RefreshCurrentResidue.IsPresent)',
        'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote',
        'Get-YuneWindowsMachineResidue -InstallDir $InstallDir'
    )) {
    if (-not $Source.Contains($Required)) {
        throw "approval brief writer is missing registry-refresh guard pattern: $Required"
    }
}

$CurrentResiduePathIndex = $Source.IndexOf('if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath))')
$RefreshIndex = $Source.IndexOf('elseif ($RefreshCurrentResidue.IsPresent)')
$ApprovalNoteIndex = $Source.IndexOf('Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote')
$DetectorIndex = $Source.IndexOf('Get-YuneWindowsMachineResidue -InstallDir $InstallDir')
if ($CurrentResiduePathIndex -lt 0 -or $RefreshIndex -lt 0 -or $ApprovalNoteIndex -lt 0 -or $DetectorIndex -lt 0) {
    throw "approval brief writer is missing current-residue branch anchors."
}
if ($ApprovalNoteIndex -lt $RefreshIndex -or $ApprovalNoteIndex -gt $DetectorIndex) {
    throw "approval brief writer must require an approval note before explicit machine-residue refresh."
}
if ($DetectorIndex -lt $RefreshIndex) {
    throw "approval brief writer must not call Get-YuneWindowsMachineResidue before the explicit refresh branch."
}

$TempDir = Join-Path $env:TEMP "yune-windows\m01-approval-brief-registry-refresh-guard-test"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$CleanupPlanPath = Join-Path $TempDir "machine-cleanup-plan.json"
$AuditPath = Join-Path $TempDir "audit.json"
$OutputPath = Join-Path $TempDir "approval-brief.md"
$CurrentResiduePath = Join-Path $TempDir "current-residue.json"
$ExpectedCurrentResiduePath = [System.IO.Path]::GetFullPath($CurrentResiduePath)

$CleanupPlan = [ordered]@{
    generated_at = "2026-06-26T03:17:00.0000000-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    install_dir = "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme"
    residue_detector = "Get-YuneWindowsMachineResidue"
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
$CleanupPlan | Out-File -LiteralPath $CleanupPlanPath -Encoding utf8

$CurrentResidue = [ordered]@{
    generated_at = "2026-06-26T03:17:30.0000000-07:00"
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6
$CurrentResidue | Out-File -LiteralPath $CurrentResiduePath -Encoding utf8

$Audit = [ordered]@{
    generated_at = "2026-06-26T03:18:00.0000000-07:00"
    status = "incomplete"
    gates = @(
        [ordered]@{
            id = "live-preflight"
            status = "invalid"
            notes = "Preflight evidence is invalid: machine-state residue issues: 1; filesystem leftovers: 1."
        }
    )
} | ConvertTo-Json -Depth 8
$Audit | Out-File -LiteralPath $AuditPath -Encoding utf8

$MissingResidueOutputPath = Join-Path $TempDir "missing-residue-approval-brief.md"
$MissingResidueSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $MissingResidueOutputPath `
        -YuneRoot "C:\Users\laubonghaudoi\Documents\GitHub\yune" `
        -InstallDir "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $MissingResidueSucceeded = $false
    }
}
catch {
    $MissingResidueSucceeded = $false
}
if ($MissingResidueSucceeded) {
    throw "approval brief writer must reject implicit current-residue refresh."
}
if (Test-Path -LiteralPath $MissingResidueOutputPath) {
    throw "approval brief writer must not write a brief after rejecting implicit current-residue refresh."
}

$RefreshWithoutNoteOutputPath = Join-Path $TempDir "refresh-without-note-approval-brief.md"
$RefreshWithoutNoteSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $RefreshWithoutNoteOutputPath `
        -YuneRoot "C:\Users\laubonghaudoi\Documents\GitHub\yune" `
        -InstallDir "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme" `
        -RefreshCurrentResidue 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $RefreshWithoutNoteSucceeded = $false
    }
}
catch {
    $RefreshWithoutNoteSucceeded = $false
}
if ($RefreshWithoutNoteSucceeded) {
    throw "approval brief writer must reject explicit machine-residue refresh without an approval note."
}
if (Test-Path -LiteralPath $RefreshWithoutNoteOutputPath) {
    throw "approval brief writer must not write a brief after rejecting refresh without an approval note."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $OutputPath `
    -YuneRoot "C:\Users\laubonghaudoi\Documents\GitHub\yune" `
    -InstallDir "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme" `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with supplied current-residue snapshot"
}

$Brief = Get-Content -Raw -LiteralPath $OutputPath
$ExpectedSourceLine = "Current residue source: $ExpectedCurrentResiduePath"
if ($Brief -notmatch [regex]::Escape($ExpectedSourceLine)) {
    throw "approval brief must record supplied current-residue evidence path: $ExpectedSourceLine"
}

Write-Host "Approval brief uses supplied residue evidence unless machine-residue refresh is explicit."
