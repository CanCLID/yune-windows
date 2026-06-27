param(
    [string]$CleanupPlanPath = "",
    [string]$AuditPath = "",
    [string]$OutputPath = "",
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$BrowserPath = "",
    [string]$CurrentResiduePath = "",
    [switch]$RefreshCurrentResidue,
    [string]$ApprovalNote = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($CleanupPlanPath -eq "") {
    $CleanupPlanPath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\machine-cleanup-plan.json"
}
if ($AuditPath -eq "") {
    $AuditPath = Join-Path $RepoRoot "docs\evidence\p2-win01-closeout\audit.json"
}
if ($OutputPath -eq "") {
    $OutputPath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\approval-brief.md"
}

$CleanupPlanPath = [System.IO.Path]::GetFullPath($CleanupPlanPath)
$AuditPath = [System.IO.Path]::GetFullPath($AuditPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$YuneRoot = [System.IO.Path]::GetFullPath($YuneRoot)
if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath)) {
    $CurrentResiduePath = [System.IO.Path]::GetFullPath($CurrentResiduePath)
}

function Test-IsConcreteBrowserPath {
    param([object]$PathValue)

    if (($null -eq $PathValue) -or (-not ($PathValue -is [string]))) {
        return $false
    }

    $Candidate = $PathValue.Trim()
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $false
    }
    if ($Candidate -match '^<.*>$') {
        return $false
    }
    if ($Candidate -match '[<>"|?*]') {
        return $false
    }
    if ($Candidate -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)') {
        return $false
    }
    if ([System.IO.Path]::GetExtension($Candidate) -ine ".exe") {
        return $false
    }

    return $true
}

function Assert-ConcreteBrowserPath {
    param(
        [object]$PathValue,
        [string]$Source
    )

    if (-not (Test-IsConcreteBrowserPath $PathValue)) {
        throw "$Source must provide a concrete Chromium browser path: an absolute .exe path, not a placeholder."
    }
}

if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    if (($BrowserPath.Trim() -match '^<.*>$') -or
        ($BrowserPath -match '[<>"|?*]')) {
        Assert-ConcreteBrowserPath -PathValue $BrowserPath -Source "Requested -BrowserPath"
    }
    Assert-ConcreteBrowserPath -PathValue $BrowserPath -Source "Requested -BrowserPath"
    $RequestedBrowserPath = [System.IO.Path]::GetFullPath($BrowserPath)
    if (-not (Test-Path -LiteralPath $RequestedBrowserPath -PathType Leaf)) {
        throw "Requested -BrowserPath must provide a concrete Chromium browser path: an existing absolute .exe path."
    }
    Assert-YuneWindowsChromiumBrowserArchitecture `
        -Path $RequestedBrowserPath `
        -Source "Requested -BrowserPath"
    $BrowserPath = $RequestedBrowserPath
}

$machine_state_changed = $false
$approval_required = $true

function Read-JsonEvidence {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing $Description evidence: $Path"
    }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-RequiredGeneratedAtText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Evidence,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $GeneratedAtProperty = $Evidence.PSObject.Properties["generated_at"]
    if ($null -eq $GeneratedAtProperty -or [string]::IsNullOrWhiteSpace([string]$GeneratedAtProperty.Value)) {
        throw "$Context must record parseable generated_at."
    }

    $ParsedGeneratedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            [string]$GeneratedAtProperty.Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$ParsedGeneratedAt)) {
        throw "$Context must record parseable generated_at."
    }

    return [string]$GeneratedAtProperty.Value
}

function Format-CommandValue {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-JsonBooleanSchemaIssueNames {
    param(
        [object]$Evidence,
        [string[]]$Names
    )

    $Issues = [System.Collections.Generic.List[string]]::new()
    foreach ($Name in $Names) {
        $Property = $Evidence.PSObject.Properties[$Name]
        if (($null -eq $Property) -or ($Property.Value -isnot [bool])) {
            $Issues.Add($Name) | Out-Null
        }
    }
    return @($Issues)
}

function Add-ResidueLines {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [object]$Group
    )

    $Lines.Add("- Affected path: $($Group.affected_path)") | Out-Null
    $Lines.Add("  - Approval required: $($Group.approval_required)") | Out-Null
    $Lines.Add("  - Pending rename entries: $(@($Group.pending_rename_entries).Count)") | Out-Null
    foreach ($Entry in @($Group.pending_rename_entries)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Entry)) {
            $Lines.Add("    - $Entry") | Out-Null
        }
    }
    $Lines.Add("  - Registry entries: $(@($Group.registry_entries).Count)") | Out-Null
    $Lines.Add("  - Registry check failures: $(@($Group.registry_check_failures).Count)") | Out-Null
    $Lines.Add("  - Machine-state entries: $(@($Group.machine_state_entries).Count)") | Out-Null
    $Lines.Add("  - Filesystem leftovers: $(@($Group.filesystem_leftovers).Count)") | Out-Null
    foreach ($Leftover in @($Group.filesystem_leftovers)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Leftover)) {
            $Lines.Add("    - $Leftover") | Out-Null
        }
    }
}

$CleanupPlan = Read-JsonEvidence -Path $CleanupPlanPath -Description "machine cleanup plan"
$Audit = Read-JsonEvidence -Path $AuditPath -Description "closeout audit"
$AuditGeneratedAt = Get-RequiredGeneratedAtText `
    -Evidence $Audit `
    -Context "approval brief closeout audit evidence"
$ResidueSummary = $CleanupPlan.residue_summary
$ResidueGroups = @($CleanupPlan.residue_groups)
$NeedsPreLiveCleanup = $CleanupPlan.blocked_live_preflight -eq $true -or $ResidueGroups.Count -gt 0
Assert-CleanupPlanProvenance `
    -Plan $CleanupPlan `
    -Context "approval brief cleanup plan"
Assert-CleanupPlanInstallDir `
    -Plan $CleanupPlan `
    -InstallDir $InstallDir `
    -Context "approval brief cleanup plan"
if ($NeedsPreLiveCleanup) {
    Assert-CleanupPlanResidueGroups `
        -Plan $CleanupPlan `
        -Context "approval brief cleanup plan"
}
$InstallerEvidenceDir = Split-Path -Parent $OutputPath
$LivePreflightPath = Join-Path $InstallerEvidenceDir "live-preflight.json"
if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath)) {
    if ([string]::Equals(
            $CurrentResiduePath,
            [System.IO.Path]::GetFullPath($LivePreflightPath),
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Approval brief current-residue input must not be live-preflight output: $CurrentResiduePath"
    }
    $CurrentResidue = Read-JsonEvidence -Path $CurrentResiduePath -Description "current machine residue"
    $CurrentResidueSource = $CurrentResiduePath
}
elseif ($RefreshCurrentResidue.IsPresent) {
    Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
    $RefreshedCurrentResidue = Get-YuneWindowsMachineResidue -InstallDir $InstallDir
    $CurrentResidue = [pscustomobject]([ordered]@{
            generated_at = (Get-Date).ToString("o")
            machine_state_checked = $true
            machine_state_issues = @($RefreshedCurrentResidue.machine_state_issues)
            filesystem_leftovers = @($RefreshedCurrentResidue.filesystem_leftovers)
        })
    $CurrentResidueSource = "Get-YuneWindowsMachineResidue"
}
else {
    throw "Approval brief current-residue validation requires -CurrentResiduePath or -RefreshCurrentResidue."
}
$CurrentResidueGeneratedAt = Get-RequiredGeneratedAtText `
    -Evidence $CurrentResidue `
    -Context "approval brief current-residue evidence"
Assert-JsonBooleanProperty `
    -Object $CurrentResidue `
    -Name "machine_state_checked" `
    -Expected $true `
    -Context "approval brief current-residue evidence"
Assert-CleanupPlanCoversCurrentResidue `
    -Plan $CleanupPlan `
    -CurrentResidue $CurrentResidue `
    -Context "approval brief cleanup plan"
$PrepValidationResultPath = Join-Path $InstallerEvidenceDir "elevated-live-smoke-prep-validation-result.json"
$PrepValidationResult = $null
$PrepValidationResultError = ""
if (Test-Path -LiteralPath $PrepValidationResultPath -PathType Leaf) {
    try {
        $PrepValidationResult = Read-JsonEvidence `
            -Path $PrepValidationResultPath `
            -Description "latest elevated live-smoke prep validation result"
    }
    catch {
        $PrepValidationResultError = $_.Exception.Message
    }
}
$LiveLauncherResultPath = Join-Path $InstallerEvidenceDir "elevated-live-smoke-launch-result.json"
$LiveLauncherResult = $null
$LiveLauncherResultError = ""
if (Test-Path -LiteralPath $LiveLauncherResultPath -PathType Leaf) {
    try {
        $LiveLauncherResult = Read-JsonEvidence `
            -Path $LiveLauncherResultPath `
            -Description "latest elevated live-smoke launch result"
    }
    catch {
        $LiveLauncherResultError = $_.Exception.Message
    }
}

if ([string]::IsNullOrWhiteSpace($BrowserPath) -and (Test-Path -LiteralPath $LivePreflightPath)) {
    $LivePreflight = Read-JsonEvidence -Path $LivePreflightPath -Description "live preflight"
    $LiveBrowserPathProperty = $LivePreflight.PSObject.Properties["browser_path"]
    if ($null -ne $LiveBrowserPathProperty) {
        $LiveBrowserPath = $LiveBrowserPathProperty.Value
        if (($null -ne $LiveBrowserPath) -and
            ((-not ($LiveBrowserPath -is [string])) -or
                (-not [string]::IsNullOrWhiteSpace($LiveBrowserPath)))) {
            Assert-ConcreteBrowserPath `
                -PathValue $LiveBrowserPath `
                -Source "live-preflight browser_path"
            $LiveBrowserFullPath = [System.IO.Path]::GetFullPath([string]$LiveBrowserPath)
            if (-not (Test-Path -LiteralPath $LiveBrowserFullPath -PathType Leaf)) {
                throw "live-preflight browser_path must provide a concrete Chromium browser path: an existing absolute .exe path."
            }
            Assert-YuneWindowsChromiumBrowserArchitecture `
                -Path $LiveBrowserFullPath `
                -Source "live-preflight browser_path"
            $BrowserPath = $LiveBrowserFullPath
        }
    }
}

$CleanupCommandParts = @(
    "powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\clear-yune-windows-machine-residue.ps1",
    "-ApprovedMachineStateChange",
    "-ApprovalNote '<current-session cleanup approval note>'",
    "-CleanupPlanPath $(Format-CommandValue $CleanupPlanPath)",
    "-EvidenceDir $(Format-CommandValue $InstallerEvidenceDir)",
    "-InstallDir $(Format-CommandValue $InstallDir)",
    "-YuneRoot $(Format-CommandValue $YuneRoot)"
)
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $CleanupCommandParts += "-BrowserPath $(Format-CommandValue $BrowserPath)"
}
$CleanupCommand = $CleanupCommandParts -join " "

$PreflightCommandParts = @(
    "powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\run-p2-win01-live-smoke.ps1",
    "-PreflightOnly",
    "-PreflightPath $(Format-CommandValue $LivePreflightPath)",
    "-YuneRoot $(Format-CommandValue $YuneRoot)",
    "-InstallDir $(Format-CommandValue $InstallDir)",
    "-RefreshCurrentResidue",
    "-ApprovalNote '<current-session approval note>'"
)
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $PreflightCommandParts += "-BrowserPath $(Format-CommandValue $BrowserPath)"
}
$PreflightCommand = $PreflightCommandParts -join " "

$LiveCommandParts = @(
    "powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\run-p2-win01-live-smoke.ps1",
    "-ApprovedMachineStateChange",
    "-ApprovalNote '<current-session approval note>'",
    "-YuneRoot $(Format-CommandValue $YuneRoot)",
    "-InstallDir $(Format-CommandValue $InstallDir)"
)
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $LiveCommandParts += "-BrowserPath $(Format-CommandValue $BrowserPath)"
}
$LiveCommand = $LiveCommandParts -join " "

$PrepValidationResultPath = Join-Path $InstallerEvidenceDir "elevated-live-smoke-prep-validation-result.json"
$PrepValidationCommandParts = @(
    "powershell -NoProfile -ExecutionPolicy Bypass -File tools\start-p2-win01-elevated-live-smoke.ps1",
    "-YuneRoot $(Format-CommandValue $YuneRoot)",
    "-InstallDir $(Format-CommandValue $InstallDir)",
    "-PrepPreflightPath $(Format-CommandValue $LivePreflightPath)",
    "-LaunchResultPath $(Format-CommandValue $PrepValidationResultPath)",
    "-ValidatePrepOnly"
)
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $PrepValidationCommandParts += "-BrowserPath $(Format-CommandValue $BrowserPath)"
}
$PrepValidationCommand = $PrepValidationCommandParts -join " "

$LiveLauncherCommandParts = @(
    "powershell -NoProfile -ExecutionPolicy Bypass -File tools\start-p2-win01-elevated-live-smoke.ps1",
    "-ApprovedMachineStateChange",
    "-ApprovalNote '<current-session approval note>'",
    "-YuneRoot $(Format-CommandValue $YuneRoot)",
    "-InstallDir $(Format-CommandValue $InstallDir)",
    "-PrepPreflightPath $(Format-CommandValue $LivePreflightPath)"
)
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $LiveLauncherCommandParts += "-BrowserPath $(Format-CommandValue $BrowserPath)"
}
$LiveLauncherCommand = $LiveLauncherCommandParts -join " "

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add("# P2-WIN01 Approval Brief") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Date: $((Get-Date).ToString('o'))") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Machine state changed: $($machine_state_changed.ToString().ToLowerInvariant())") | Out-Null
$Lines.Add("Approval required: $($approval_required.ToString().ToLowerInvariant())") | Out-Null
$Lines.Add("Cleanup plan: $CleanupPlanPath") | Out-Null
$Lines.Add("Cleanup plan generated_at: $($CleanupPlan.generated_at)") | Out-Null
$Lines.Add("Cleanup plan residue detector: $($CleanupPlan.residue_detector)") | Out-Null
$Lines.Add("Current residue source: $CurrentResidueSource") | Out-Null
$Lines.Add("Current residue generated_at: $CurrentResidueGeneratedAt") | Out-Null
$Lines.Add("Closeout audit: $AuditPath") | Out-Null
$Lines.Add("Closeout audit generated_at: $AuditGeneratedAt") | Out-Null
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $Lines.Add("Chromium browser path: $BrowserPath") | Out-Null
}
$Lines.Add("") | Out-Null
$Lines.Add("## Current Closeout") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Status: $($Audit.status)") | Out-Null
foreach ($Gate in @($Audit.gates)) {
    if ($Gate.status -ne "complete") {
        $Lines.Add("- $($Gate.id): $($Gate.status) - $($Gate.notes)") | Out-Null
    }
}
$Lines.Add("") | Out-Null
$Lines.Add("## Latest Prep Validation") | Out-Null
$Lines.Add("") | Out-Null
if (-not (Test-Path -LiteralPath $PrepValidationResultPath -PathType Leaf)) {
    $Lines.Add("No elevated-live-smoke-prep-validation-result.json has been recorded next to this brief.") | Out-Null
}
elseif ($null -eq $PrepValidationResult) {
    $Lines.Add("Prep validation result: $PrepValidationResultPath") | Out-Null
    $Lines.Add("Prep validation result could not be parsed: $PrepValidationResultError") | Out-Null
}
else {
    $PrepExitCode = if ($null -eq $PrepValidationResult.exit_code) {
        "null"
    }
    else {
        [string]$PrepValidationResult.exit_code
    }
    $PrepBooleanIssueNames = Get-JsonBooleanSchemaIssueNames `
        -Evidence $PrepValidationResult `
        -Names @(
            "approved_machine_state_change",
            "elevated_process_started",
            "transcript_exists",
            "machine_state_changed_before_elevated_process"
        )
    $PrepTranscriptExistsProperty = $PrepValidationResult.PSObject.Properties["transcript_exists"]
    $PrepTranscriptPath = [string]$PrepValidationResult.transcript_path
    $PrepTranscriptExists = if (($null -ne $PrepTranscriptExistsProperty) -and
        ($PrepTranscriptExistsProperty.Value -is [bool])) {
        [bool]$PrepTranscriptExistsProperty.Value
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PrepTranscriptPath)) {
        Test-Path -LiteralPath $PrepTranscriptPath -PathType Leaf
    }
    else {
        $false
    }
    $Lines.Add("Prep validation result: $PrepValidationResultPath") | Out-Null
    $Lines.Add("Prep validation generated_at: $($PrepValidationResult.generated_at)") | Out-Null
    $Lines.Add("Prep validation status: $($PrepValidationResult.status)") | Out-Null
    if ($PrepBooleanIssueNames.Count -gt 0) {
        $Lines.Add("Prep validation boolean schema warning: $($PrepBooleanIssueNames -join ', ') must be JSON booleans.") | Out-Null
    }
    $Lines.Add("Prep validation elevated process started: $($PrepValidationResult.elevated_process_started)") | Out-Null
    $Lines.Add("Prep validation exit code: $PrepExitCode") | Out-Null
    $Lines.Add("Prep validation transcript exists: $PrepTranscriptExists") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace([string]$PrepValidationResult.prep_preflight_path)) {
        $Lines.Add("Prep validation preflight path: $($PrepValidationResult.prep_preflight_path)") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$PrepValidationResult.error_message)) {
        $Lines.Add("Prep validation error: $($PrepValidationResult.error_message)") | Out-Null
    }
    if ([string]$PrepValidationResult.status -ne "prep-preflight-ready") {
        $Lines.Add("Do not run the single-UAC launcher until the latest prep validation status is prep-preflight-ready.") | Out-Null
    }
}
$Lines.Add("") | Out-Null
$Lines.Add("## Latest Launcher Attempt") | Out-Null
$Lines.Add("") | Out-Null
if (-not (Test-Path -LiteralPath $LiveLauncherResultPath -PathType Leaf)) {
    $Lines.Add("No elevated-live-smoke-launch-result.json has been recorded next to this brief.") | Out-Null
}
elseif ($null -eq $LiveLauncherResult) {
    $Lines.Add("Launch result: $LiveLauncherResultPath") | Out-Null
    $Lines.Add("Launcher result could not be parsed: $LiveLauncherResultError") | Out-Null
}
else {
    $LauncherExitCode = if ($null -eq $LiveLauncherResult.exit_code) {
        "null"
    }
    else {
        [string]$LiveLauncherResult.exit_code
    }
    $LauncherBooleanIssueNames = Get-JsonBooleanSchemaIssueNames `
        -Evidence $LiveLauncherResult `
        -Names @(
            "approved_machine_state_change",
            "elevated_process_started",
            "transcript_exists",
            "machine_state_changed_before_elevated_process"
        )
    $Lines.Add("Launch result: $LiveLauncherResultPath") | Out-Null
    $Lines.Add("Launcher generated_at: $($LiveLauncherResult.generated_at)") | Out-Null
    $Lines.Add("Launcher status: $($LiveLauncherResult.status)") | Out-Null
    if ($LauncherBooleanIssueNames.Count -gt 0) {
        $Lines.Add("Launcher boolean schema warning: $($LauncherBooleanIssueNames -join ', ') must be JSON booleans.") | Out-Null
    }
    $Lines.Add("Elevated process started: $($LiveLauncherResult.elevated_process_started)") | Out-Null
    $Lines.Add("Exit code: $LauncherExitCode") | Out-Null
    $Lines.Add("Machine state changed before elevated process: $($LiveLauncherResult.machine_state_changed_before_elevated_process)") | Out-Null
    $TranscriptExistsProperty = $LiveLauncherResult.PSObject.Properties["transcript_exists"]
    $LauncherTranscriptPath = [string]$LiveLauncherResult.transcript_path
    $LauncherTranscriptExists = if (($null -ne $TranscriptExistsProperty) -and
        ($TranscriptExistsProperty.Value -is [bool])) {
        [bool]$TranscriptExistsProperty.Value
    }
    elseif (-not [string]::IsNullOrWhiteSpace($LauncherTranscriptPath)) {
        Test-Path -LiteralPath $LauncherTranscriptPath -PathType Leaf
    }
    else {
        $false
    }
    $Lines.Add("Launcher transcript exists: $LauncherTranscriptExists") | Out-Null
    $LauncherStartedProperty = $LiveLauncherResult.PSObject.Properties["elevated_process_started"]
    $LauncherStarted = ($null -ne $LauncherStartedProperty) -and
        ($LauncherStartedProperty.Value -is [bool]) -and
        ($LauncherStartedProperty.Value -eq $true)
    if ($LauncherStarted -and (-not $LauncherTranscriptExists)) {
        $Lines.Add("Started launcher transcript missing: True") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$LiveLauncherResult.error_message)) {
        $Lines.Add("Launcher error: $($LiveLauncherResult.error_message)") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$LiveLauncherResult.transcript_path)) {
        $Lines.Add("Launcher transcript: $($LiveLauncherResult.transcript_path)") | Out-Null
    }
    if ((-not $LauncherStarted) -and
        ([string]$LiveLauncherResult.status -in @("elevation-canceled", "failed-to-start"))) {
        $Lines.Add("Fresh approval required before retry: True") | Out-Null
    }
}
$Lines.Add("") | Out-Null
$Lines.Add("## Machine Residue") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Machine state checked: $($CleanupPlan.machine_state_checked)") | Out-Null
$Lines.Add("Cleanup plan current residue covered: true") | Out-Null
$Lines.Add("Blocked live preflight: $($CleanupPlan.blocked_live_preflight)") | Out-Null
$Lines.Add("Machine-state issues: $($ResidueSummary.machine_state_issue_count)") | Out-Null
$Lines.Add("Pending rename entries: $($ResidueSummary.pending_rename_count)") | Out-Null
$Lines.Add("Registry entries: $($ResidueSummary.registry_entry_count)") | Out-Null
$Lines.Add("Registry check failures: $($ResidueSummary.registry_check_failure_count)") | Out-Null
$Lines.Add("Filesystem leftovers: $($ResidueSummary.filesystem_leftover_count)") | Out-Null
$Lines.Add("Affected paths: $($ResidueSummary.affected_path_count)") | Out-Null
$Lines.Add("") | Out-Null
if ($ResidueGroups.Count -eq 0) {
    $Lines.Add("- No current YuneWindows residue groups are recorded.") | Out-Null
} else {
    foreach ($Group in $ResidueGroups) {
        Add-ResidueLines -Lines $Lines -Group $Group
    }
}
$Lines.Add("") | Out-Null
$Lines.Add("## Approved Sequence") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Run only after explicit approval in the current session from an elevated STA PowerShell session.") | Out-Null
$Lines.Add("Replace the approval-note placeholders before running commands; placeholder values are rejected by the scripts and closeout audit.") | Out-Null
$Lines.Add("The approved sequence writes approval evidence before command transcript entries or machine-state work.") | Out-Null
if ($CleanupPlan.blocked_live_preflight -eq $true) {
    $Lines.Add("The current residue blocks live preflight; run the approved cleanup helper or reboot if required, then regenerate preflight evidence before expecting the full live sequence to pass.") | Out-Null
}
$Lines.Add("") | Out-Null
if ($NeedsPreLiveCleanup) {
    $Lines.Add("Approved cleanup helper result: `machine-cleanup-result.md`.") | Out-Null
    $Lines.Add("Cleanup scope: only residue groups listed in $(Split-Path -Leaf $CleanupPlanPath) are approved for this helper run.") | Out-Null
    $Lines.Add("Cleanup plan install directory must match the approved -InstallDir value.") | Out-Null
    $Lines.Add("Cleanup plan must record machine_state_changed=false and residue_detector=Get-YuneWindowsMachineResidue.") | Out-Null
    $Lines.Add("Cleanup plan residue groups must name affected_path and at least one residue entry.") | Out-Null
    $Lines.Add("Cleanup plan must cover every current machine-state issue and filesystem leftover before cleanup starts.") | Out-Null
    $Lines.Add("Cleanup plan must not include cleanup targets absent from the current residue snapshot.") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add('```powershell') | Out-Null
    $Lines.Add($CleanupCommand) | Out-Null
    $Lines.Add('```') | Out-Null
    $Lines.Add("") | Out-Null
} else {
    $Lines.Add("No pre-live cleanup helper is needed for the current residue snapshot.") | Out-Null
    $Lines.Add("") | Out-Null
}
$Lines.Add("Non-mutating preflight refresh command: live-preflight.json.") | Out-Null
$Lines.Add("Run this non-mutating check after cleanup or reboot and before the full approved live sequence.") | Out-Null
$Lines.Add("A non-elevated prep preflight can confirm clean residue, source/runtime inputs, STA context, and browser availability; ready_for_live_smoke remains false until the elevated child reruns it with is_administrator=true.") | Out-Null
if (-not [string]::IsNullOrWhiteSpace($BrowserPath)) {
    $Lines.Add("The commands below carry the resolved Chromium browser path; approval.md records this resolved browser path for transcript matching.") | Out-Null
}
$Lines.Add("") | Out-Null
$Lines.Add('```powershell') | Out-Null
$Lines.Add($PreflightCommand) | Out-Null
$Lines.Add('```') | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Non-mutating launcher validation command: elevated-live-smoke-prep-validation-result.json.") | Out-Null
$Lines.Add("Run this command after refreshing prep preflight and before using the single-UAC launcher; it checks the same prep evidence and returns without invoking UAC.") | Out-Null
$Lines.Add("This validation command does not accept an approval switch or approval note because it cannot start the elevated child.") | Out-Null
$Lines.Add("A passing validation writes prep-preflight-ready; it does not install, register, launch apps, clean residue, or close P2-WIN01.") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add('```powershell') | Out-Null
$Lines.Add($PrepValidationCommand) | Out-Null
$Lines.Add('```') | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Single-UAC launcher command: elevated-live-smoke-launch-result.json.") | Out-Null
$Lines.Add("Use the single-UAC launcher from a non-elevated shell after the prep preflight records empty machine_state_issues, empty filesystem_leftovers, install_dir_exists=false, server_process_count=0, is_sta=true, and browser_available=true.") | Out-Null
$Lines.Add("The elevated child reruns live-preflight and must record ready_for_live_smoke=true before install starts; failed process creation is recorded as failed-to-start and canceled UAC is recorded as elevation-canceled before any elevated process starts.") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add('```powershell') | Out-Null
$Lines.Add($LiveLauncherCommand) | Out-Null
$Lines.Add('```') | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("Direct elevated STA command for an already elevated PowerShell session.") | Out-Null
$Lines.Add("Use the direct elevated STA command only from an already elevated shell; its preflight must record ready_for_live_smoke=true, empty residue arrays, is_administrator=true, is_sta=true, and browser_available=true before install starts.") | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add('```powershell') | Out-Null
$Lines.Add($LiveCommand) | Out-Null
$Lines.Add('```') | Out-Null
$Lines.Add("") | Out-Null
$Lines.Add("This brief is non-mutating advisory evidence and does not close P2-WIN01.") | Out-Null

New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null
$Lines | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
