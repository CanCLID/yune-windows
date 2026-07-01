param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BriefScript = Join-Path $RepoRoot "tools\write-m01-approval-brief.ps1"
if (-not (Test-Path -LiteralPath $BriefScript)) {
    throw "missing approval brief writer: tools\write-m01-approval-brief.ps1"
}

$Source = Get-Content -Raw -LiteralPath $BriefScript
foreach ($Required in @(
        'machine_state_changed\s*=\s*\$false',
        'approval_required\s*=\s*\$true',
        'ConvertFrom-Json',
        'residue_summary',
        'residue_groups',
        'powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\\clear-yune-windows-machine-residue\.ps1',
        'machine-cleanup-result\.md',
        'Preflight refresh command',
        'PreflightPath',
        'run-m01-live-smoke\.ps1',
        'ApprovedMachineStateChange',
        'ApprovalNote',
        'powershell -STA',
        'Cleanup plan generated_at',
        'Cleanup plan residue detector',
        'Closeout audit generated_at',
        'Cleanup plan residue groups must name affected_path and at least one residue entry.',
        'Cleanup plan must cover every current machine-state issue and filesystem leftover before cleanup starts.',
        'CurrentResiduePath',
        'RefreshCurrentResidue',
        'Current residue source:',
        'Approval brief current-residue validation requires -CurrentResiduePath or -RefreshCurrentResidue.',
        'Assert-CleanupPlanCoversCurrentResidue',
        'Get-YuneWindowsMachineResidue',
        'tools\\start-m01-elevated-live-smoke.ps1',
        'PrepPreflightPath',
        'A non-elevated prep preflight can confirm clean residue, source/runtime inputs, STA context, and browser availability; ready_for_live_smoke remains false until the elevated child reruns it with is_administrator=true.',
        'Use the single-UAC launcher from a non-elevated shell after the prep preflight records empty machine_state_issues, empty filesystem_leftovers, install_dir_exists=false, server_process_count=0, is_sta=true, and browser_available=true.',
        'Use the direct elevated STA command only from an already elevated shell; its preflight must record ready_for_live_smoke=true, empty residue arrays, is_administrator=true, is_sta=true, and browser_available=true before install starts.',
        'Replace the approval-note placeholders before running commands; placeholder values are rejected by the scripts and closeout audit.',
        'Non-mutating launcher validation command',
        'This validation command does not accept an approval switch or approval note because it cannot start the elevated child.',
        'ValidatePrepOnly',
        'LaunchResultPath',
        'elevated-live-smoke-prep-validation-result.json',
        'Latest launcher attempt',
        'Launcher transcript exists:',
        'Latest prep validation'
    )) {
    if ($Source -notmatch $Required) {
        throw "approval brief writer is missing required pattern: $Required"
    }
}

foreach ($Forbidden in @(
        'Remove-Item',
        'Remove-ItemProperty',
        'Set-ItemProperty',
        'New-ItemProperty',
        'reg\.exe',
        'regsvr32',
        'Stop-Process',
        'Start-Process'
    )) {
    if ($Source -match $Forbidden) {
        throw "approval brief writer must be non-mutating and must not contain: $Forbidden"
    }
}

$TempDir = Join-Path $env:TEMP "yune-windows\m01-approval-brief-test"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$CleanupPlanPath = Join-Path $TempDir "machine-cleanup-plan.json"
$AuditPath = Join-Path $TempDir "audit.json"
$OutputPath = Join-Path $TempDir "approval-brief.md"
$CurrentResiduePath = Join-Path $TempDir "current-residue.json"
$LaunchResultPath = Join-Path $TempDir "elevated-live-smoke-launch-result.json"
$PrepValidationResultPath = Join-Path $TempDir "elevated-live-smoke-prep-validation-result.json"
$LaunchAwareOutputPath = Join-Path $TempDir "approval-brief-with-launch.md"
$InvalidPrepOutputPath = Join-Path $TempDir "approval-brief-with-invalid-prep.md"
Remove-Item -LiteralPath $LaunchResultPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PrepValidationResultPath -Force -ErrorAction SilentlyContinue
$ExpectedCurrentResiduePath = [System.IO.Path]::GetFullPath($CurrentResiduePath)
$ExpectedLivePreflightPath = [System.IO.Path]::GetFullPath((Join-Path $TempDir "live-preflight.json"))
$ExpectedPrepValidationResultPath = [System.IO.Path]::GetFullPath((Join-Path $TempDir "elevated-live-smoke-prep-validation-result.json"))
$RelativeYuneRoot = "relative-yune-root"
$RelativeInstallDir = "relative-install-target"
$ExpectedYuneRoot = [System.IO.Path]::GetFullPath($RelativeYuneRoot)
$ExpectedInstallDir = [System.IO.Path]::GetFullPath($RelativeInstallDir)

$CleanupPlan = [ordered]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    install_dir = $ExpectedInstallDir
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
    generated_at = "2026-06-25T14:14:19.4882370-07:00"
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6
$CurrentResidue | Out-File -LiteralPath $CurrentResiduePath -Encoding utf8

$Audit = [ordered]@{
    generated_at = "2026-06-25T14:15:19.4882370-07:00"
    status = "incomplete"
    gates = @(
        [ordered]@{
            id = "live-preflight"
            status = "invalid"
            notes = "Preflight evidence is invalid: machine-state residue issues: 1; filesystem leftovers: 1."
        },
        [ordered]@{
            id = "tsf-notepad-smoke"
            status = "missing"
            notes = "Requires approved install/register/profile activation."
        }
    )
} | ConvertTo-Json -Depth 8
$Audit | Out-File -LiteralPath $AuditPath -Encoding utf8

& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $OutputPath `
    -YuneRoot $RelativeYuneRoot `
    -InstallDir $RelativeInstallDir `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "approval brief writer did not write output: $OutputPath"
}

$Brief = Get-Content -Raw -LiteralPath $OutputPath
foreach ($Expected in @(
        '# M01 Approval Brief',
        'Machine state changed: false',
        'Approval required: true',
        'Cleanup plan generated_at: 2026-06-25T14:13:35.2880334-07:00',
        'Cleanup plan residue detector: Get-YuneWindowsMachineResidue',
        "Current residue source: $ExpectedCurrentResiduePath",
        'Current residue generated_at: 2026-06-25T14:14:19.4882370-07:00',
        'Status: incomplete',
        'Closeout audit generated_at: 2026-06-25T14:15:19.4882370-07:00',
        '## Latest Prep Validation',
        'No elevated-live-smoke-prep-validation-result.json has been recorded next to this brief.',
        '## Latest Launcher Attempt',
        'No elevated-live-smoke-launch-result.json has been recorded next to this brief.',
        'live-preflight: invalid',
        'tsf-notepad-smoke: missing',
        'Pending rename entries: 1',
        'Filesystem leftovers: 1',
        'C:\Windows\System32\YuneWindows.dll.old.0',
        'tools\clear-yune-windows-machine-residue.ps1',
        'powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\clear-yune-windows-machine-residue.ps1',
        "-ApprovalNote '<current-session cleanup approval note>'",
        'machine-cleanup-result.md',
        'Cleanup scope: only residue groups listed in machine-cleanup-plan.json are approved for this helper run.',
        'Cleanup plan install directory must match the approved -InstallDir value.',
        'Cleanup plan must record machine_state_changed=false and residue_detector=Get-YuneWindowsMachineResidue.',
        'Cleanup plan residue groups must name affected_path and at least one residue entry.',
        'Cleanup plan must cover every current machine-state issue and filesystem leftover before cleanup starts.',
        'Cleanup plan must not include cleanup targets absent from the current residue snapshot.',
        'Cleanup plan current residue covered: true',
        'Replace the approval-note placeholders before running commands; placeholder values are rejected by the scripts and closeout audit.',
        'Non-mutating preflight refresh command: live-preflight.json.',
        'A non-elevated prep preflight can confirm clean residue, source/runtime inputs, STA context, and browser availability; ready_for_live_smoke remains false until the elevated child reruns it with is_administrator=true.',
        'Use the single-UAC launcher from a non-elevated shell after the prep preflight records empty machine_state_issues, empty filesystem_leftovers, install_dir_exists=false, server_process_count=0, is_sta=true, and browser_available=true.',
        'Use the direct elevated STA command only from an already elevated shell; its preflight must record ready_for_live_smoke=true, empty residue arrays, is_administrator=true, is_sta=true, and browser_available=true before install starts.',
        'powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\run-m01-live-smoke.ps1 -PreflightOnly -PreflightPath',
        '-RefreshCurrentResidue',
        "-ApprovalNote '<current-session approval note>'",
        'Non-mutating launcher validation command: elevated-live-smoke-prep-validation-result.json.',
        'Run this command after refreshing prep preflight and before using the single-UAC launcher; it checks the same prep evidence and returns without invoking UAC.',
        'This validation command does not accept an approval switch or approval note because it cannot start the elevated child.',
        'prep-preflight-ready',
        'powershell -NoProfile -ExecutionPolicy Bypass -File tools\start-m01-elevated-live-smoke.ps1',
        'tools\start-m01-elevated-live-smoke.ps1 -ApprovedMachineStateChange',
        "-PrepPreflightPath '$ExpectedLivePreflightPath'",
        "-LaunchResultPath '$ExpectedPrepValidationResultPath'",
        '-ValidatePrepOnly',
        'Single-UAC launcher command: elevated-live-smoke-launch-result.json.',
        'failed-to-start',
        'elevation-canceled',
        'elevated-live-smoke-launch-result.json',
        "tools\start-m01-elevated-live-smoke.ps1 -ApprovedMachineStateChange -ApprovalNote '<current-session approval note>' -YuneRoot '$ExpectedYuneRoot' -InstallDir '$ExpectedInstallDir' -PrepPreflightPath '$ExpectedLivePreflightPath'",
        'powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\run-m01-live-smoke.ps1',
        '-ApprovedMachineStateChange',
        '-ApprovalNote',
        "-YuneRoot '$ExpectedYuneRoot'",
        "-InstallDir '$ExpectedInstallDir'",
        'does not close M01'
    )) {
    if ($Brief -notmatch [regex]::Escape($Expected)) {
        throw "approval brief is missing expected text: $Expected"
    }
}

foreach ($Unexpected in @(
        "-YuneRoot '$RelativeYuneRoot'",
        "-InstallDir '$RelativeInstallDir'",
        "tools\run-m01-live-smoke.ps1 -ApprovedMachineStateChange -ApprovalNote '<current-session approval note>' -YuneRoot '$ExpectedYuneRoot' -InstallDir '$ExpectedInstallDir' -PrepPreflightPath"
    )) {
    if ($Brief -match [regex]::Escape($Unexpected)) {
        throw "approval brief should normalize operator command paths, but still contains: $Unexpected"
    }
}

$PrepValidationLine = @($Brief -split "`r?`n" | Where-Object {
        $_ -match [regex]::Escape("tools\start-m01-elevated-live-smoke.ps1") -and
        $_ -match [regex]::Escape("elevated-live-smoke-prep-validation-result.json")
    } | Select-Object -First 1)
if ($PrepValidationLine.Count -ne 1) {
    throw "approval brief must include exactly one prep-validation launcher command."
}
if ($PrepValidationLine[0] -match '-ApprovedMachineStateChange|-ApprovalNote') {
    throw "prep-validation launcher command must not require approval switches: $($PrepValidationLine[0])"
}
foreach ($ExpectedValidationPart in @(
        "-YuneRoot '$ExpectedYuneRoot'",
        "-InstallDir '$ExpectedInstallDir'",
        "-PrepPreflightPath '$ExpectedLivePreflightPath'",
        "-LaunchResultPath '$ExpectedPrepValidationResultPath'",
        "-ValidatePrepOnly"
    )) {
    if ($PrepValidationLine[0] -notmatch [regex]::Escape($ExpectedValidationPart)) {
        throw "prep-validation launcher command is missing: $ExpectedValidationPart"
    }
}

[ordered]@{
    generated_at = "2026-06-25T14:16:10.4882370-07:00"
    status = "prep-preflight-ready"
    approved_machine_state_change = $false
    approval_note = ""
    elevated_process_started = $false
    exit_code = $null
    error_message = ""
    transcript_exists = $false
    machine_state_changed_before_elevated_process = $false
    prep_preflight_path = $ExpectedLivePreflightPath
    transcript_path = "C:\evidence\elevated-live-smoke-prep-validation-transcript.txt"
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $PrepValidationResultPath -Encoding utf8

[ordered]@{
    generated_at = "2026-06-25T14:16:19.4882370-07:00"
    status = "elevation-canceled"
    approved_machine_state_change = $true
    approval_note = "User approved elevated live smoke in this session."
    elevated_process_started = $false
    exit_code = $null
    error_message = "The operation was canceled by the user."
    machine_state_changed_before_elevated_process = $false
    transcript_exists = $false
    transcript_path = "C:\evidence\elevated-live-smoke-transcript.txt"
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $LaunchResultPath -Encoding utf8

& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $LaunchAwareOutputPath `
    -YuneRoot $RelativeYuneRoot `
    -InstallDir $RelativeInstallDir `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with exit code $LASTEXITCODE for launch-result summary"
}
$LaunchAwareBrief = Get-Content -Raw -LiteralPath $LaunchAwareOutputPath
foreach ($ExpectedLaunchLine in @(
        '## Latest Prep Validation',
        'Prep validation result: ',
        'Prep validation generated_at: 2026-06-25T14:16:10.4882370-07:00',
        'Prep validation status: prep-preflight-ready',
        'Prep validation elevated process started: False',
        'Prep validation exit code: null',
        'Prep validation transcript exists: False',
        "Prep validation preflight path: $ExpectedLivePreflightPath",
        '## Latest Launcher Attempt',
        'Launch result: ',
        'Launcher generated_at: 2026-06-25T14:16:19.4882370-07:00',
        'Launcher status: elevation-canceled',
        'Elevated process started: False',
        'Exit code: null',
        'Machine state changed before elevated process: False',
        'Launcher transcript exists: False',
        'Launcher error: The operation was canceled by the user.',
        'Launcher transcript: C:\evidence\elevated-live-smoke-transcript.txt',
        'Fresh approval required before retry: True'
    )) {
if ($LaunchAwareBrief -notmatch [regex]::Escape($ExpectedLaunchLine)) {
        throw "approval brief with launch-result summary is missing: $ExpectedLaunchLine"
    }
}

[ordered]@{
    generated_at = "2026-06-25T14:17:19.4882370-07:00"
    status = "failed"
    approved_machine_state_change = $true
    approval_note = "User approved elevated live smoke in this session."
    elevated_process_started = $true
    exit_code = 1
    error_message = "Elevated live smoke exited with code 1."
    machine_state_changed_before_elevated_process = $false
    transcript_exists = $false
    transcript_path = "C:\evidence\missing-elevated-live-smoke-transcript.txt"
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $LaunchResultPath -Encoding utf8

$MissingTranscriptOutputPath = Join-Path $TempDir "approval-brief-with-missing-started-transcript.md"
& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $MissingTranscriptOutputPath `
    -YuneRoot $RelativeYuneRoot `
    -InstallDir $RelativeInstallDir `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with exit code $LASTEXITCODE for started missing-transcript launcher summary"
}
$MissingTranscriptBrief = Get-Content -Raw -LiteralPath $MissingTranscriptOutputPath
foreach ($ExpectedMissingTranscriptLine in @(
        'Launcher status: failed',
        'Elevated process started: True',
        'Launcher transcript exists: False',
        'Started launcher transcript missing: True'
    )) {
    if ($MissingTranscriptBrief -notmatch [regex]::Escape($ExpectedMissingTranscriptLine)) {
        throw "approval brief with started missing-transcript launcher summary is missing: $ExpectedMissingTranscriptLine"
    }
}

[ordered]@{
    generated_at = "2026-06-25T14:18:19.4882370-07:00"
    status = "elevation-canceled"
    approved_machine_state_change = "true"
    approval_note = "User approved elevated live smoke in this session."
    elevated_process_started = "false"
    exit_code = $null
    error_message = "The operation was canceled by the user."
    machine_state_changed_before_elevated_process = "false"
    transcript_exists = "false"
    transcript_path = "C:\evidence\string-typed-elevated-live-smoke-transcript.txt"
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $LaunchResultPath -Encoding utf8

$StringTypedLauncherOutputPath = Join-Path $TempDir "approval-brief-with-string-typed-launcher-booleans.md"
& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $StringTypedLauncherOutputPath `
    -YuneRoot $RelativeYuneRoot `
    -InstallDir $RelativeInstallDir `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with exit code $LASTEXITCODE for string-typed launcher boolean summary"
}
$StringTypedLauncherBrief = Get-Content -Raw -LiteralPath $StringTypedLauncherOutputPath
foreach ($ExpectedStringTypedLauncherLine in @(
        'Launcher boolean schema warning: approved_machine_state_change, elevated_process_started, transcript_exists, machine_state_changed_before_elevated_process must be JSON booleans.',
        'Elevated process started: false',
        'Launcher transcript exists: False',
        'Fresh approval required before retry: True'
    )) {
    if ($StringTypedLauncherBrief -notmatch [regex]::Escape($ExpectedStringTypedLauncherLine)) {
        throw "approval brief with string-typed launcher booleans is missing: $ExpectedStringTypedLauncherLine"
    }
}
if ($StringTypedLauncherBrief -match [regex]::Escape('Launcher transcript exists: True')) {
    throw "approval brief must not coerce string transcript_exists=false into True."
}

[ordered]@{
    generated_at = "2026-06-25T14:16:35.4882370-07:00"
    status = "prep-preflight-invalid"
    approved_machine_state_change = $false
    approval_note = ""
    elevated_process_started = $false
    exit_code = $null
    error_message = "prep preflight machine_residue_source must not point to itself."
    transcript_exists = $false
    machine_state_changed_before_elevated_process = $false
    prep_preflight_path = $ExpectedLivePreflightPath
    transcript_path = "C:\evidence\elevated-live-smoke-prep-validation-transcript.txt"
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $PrepValidationResultPath -Encoding utf8

& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $InvalidPrepOutputPath `
    -YuneRoot $RelativeYuneRoot `
    -InstallDir $RelativeInstallDir `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with exit code $LASTEXITCODE for invalid prep summary"
}
$InvalidPrepBrief = Get-Content -Raw -LiteralPath $InvalidPrepOutputPath
foreach ($ExpectedInvalidPrepLine in @(
        'Prep validation status: prep-preflight-invalid',
        'Prep validation error: prep preflight machine_residue_source must not point to itself.',
        'Do not run the single-UAC launcher until the latest prep validation status is prep-preflight-ready.'
    )) {
    if ($InvalidPrepBrief -notmatch [regex]::Escape($ExpectedInvalidPrepLine)) {
        throw "approval brief with invalid prep validation is missing: $ExpectedInvalidPrepLine"
    }
}

$CleanCleanupPlanPath = Join-Path $TempDir "clean-machine-cleanup-plan.json"
$CleanCurrentResiduePath = Join-Path $TempDir "clean-current-residue.json"
$CleanOutputPath = Join-Path $TempDir "clean-approval-brief.md"
[ordered]@{
    generated_at = "2026-06-25T14:16:35.2880334-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    install_dir = $ExpectedInstallDir
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = $true
    blocked_live_preflight = $false
    residue_summary = [ordered]@{
        machine_state_issue_count = 0
        pending_rename_count = 0
        registry_entry_count = 0
        registry_check_failure_count = 0
        filesystem_leftover_count = 0
        affected_path_count = 0
    }
    residue_groups = @()
} | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $CleanCleanupPlanPath -Encoding utf8
[ordered]@{
    generated_at = "2026-06-25T14:17:19.4882370-07:00"
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $CleanCurrentResiduePath -Encoding utf8

& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanCleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $CleanOutputPath `
    -YuneRoot $RelativeYuneRoot `
    -InstallDir $RelativeInstallDir `
    -CurrentResiduePath $CleanCurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed for clean residue with exit code $LASTEXITCODE"
}
$CleanBrief = Get-Content -Raw -LiteralPath $CleanOutputPath
foreach ($ExpectedCleanText in @(
        '- No current YuneWindows residue groups are recorded.',
        'No pre-live cleanup helper is needed for the current residue snapshot.'
    )) {
    if ($CleanBrief -notmatch [regex]::Escape($ExpectedCleanText)) {
        throw "clean approval brief is missing expected text: $ExpectedCleanText"
    }
}
foreach ($UnexpectedCleanText in @(
        'powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\clear-yune-windows-machine-residue.ps1',
        'Approved cleanup helper result:'
    )) {
    if ($CleanBrief -match [regex]::Escape($UnexpectedCleanText)) {
        throw "clean approval brief should not ask for pre-live cleanup helper UAC: $UnexpectedCleanText"
    }
}

$SelfReferentialResidueOutputPath = Join-Path $TempDir "self-referential-residue-approval-brief.md"
Remove-Item -LiteralPath $SelfReferentialResidueOutputPath -Force -ErrorAction SilentlyContinue
[ordered]@{
    generated_at = "2026-06-25T14:17:39.4882370-07:00"
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $ExpectedLivePreflightPath -Encoding utf8
$SelfReferentialResidueSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanCleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $SelfReferentialResidueOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $ExpectedLivePreflightPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $SelfReferentialResidueSucceeded = $false
    }
}
catch {
    $SelfReferentialResidueSucceeded = $false
}
if ($SelfReferentialResidueSucceeded) {
    throw "approval brief writer must reject live-preflight.json as supplied current-residue evidence."
}
if (Test-Path -LiteralPath $SelfReferentialResidueOutputPath) {
    throw "approval brief writer must not write output after rejecting live-preflight current-residue evidence."
}

$MismatchedCleanupPlanPath = Join-Path $TempDir "mismatched-machine-cleanup-plan.json"
$MismatchedCleanupPlan = $CleanupPlan | ConvertFrom-Json
$MismatchedCleanupPlan.install_dir = "C:\Users\example\AppData\Local\Yune\DifferentIme"
$MismatchedCleanupPlan | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $MismatchedCleanupPlanPath -Encoding utf8
$MismatchOutputPath = Join-Path $TempDir "mismatch-approval-brief.md"
$MismatchSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $MismatchedCleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $MismatchOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $CurrentResiduePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $MismatchSucceeded = $false
    }
}
catch {
    $MismatchSucceeded = $false
}
if ($MismatchSucceeded) {
    throw "approval brief writer must reject cleanup plans whose install_dir does not match the approved -InstallDir."
}

$StaleCurrentResiduePath = Join-Path $TempDir "stale-current-residue.json"
$StaleCurrentResidue = [ordered]@{
    generated_at = "2026-06-25T14:14:29.4882370-07:00"
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.1")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.1")
} | ConvertTo-Json -Depth 6
$StaleCurrentResidue | Out-File -LiteralPath $StaleCurrentResiduePath -Encoding utf8
$StaleOutputPath = Join-Path $TempDir "stale-approval-brief.md"
$StaleSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $StaleOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $StaleCurrentResiduePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $StaleSucceeded = $false
    }
}
catch {
    $StaleSucceeded = $false
}
if ($StaleSucceeded) {
    throw "approval brief writer must reject cleanup plans that do not cover current machine residue."
}

$InvalidTimestampResiduePath = Join-Path $TempDir "invalid-timestamp-current-residue.json"
[ordered]@{
    generated_at = "not-a-timestamp"
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $InvalidTimestampResiduePath -Encoding utf8
$InvalidTimestampOutputPath = Join-Path $TempDir "invalid-timestamp-approval-brief.md"
$InvalidTimestampSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $InvalidTimestampOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $InvalidTimestampResiduePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $InvalidTimestampSucceeded = $false
    }
}
catch {
    $InvalidTimestampSucceeded = $false
}
if ($InvalidTimestampSucceeded) {
    throw "approval brief writer must reject current-residue evidence without parseable generated_at."
}

$UncheckedCurrentResiduePath = Join-Path $TempDir "unchecked-current-residue.json"
[ordered]@{
    generated_at = "2026-06-25T14:14:19.4882370-07:00"
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $UncheckedCurrentResiduePath -Encoding utf8
$UncheckedOutputPath = Join-Path $TempDir "unchecked-approval-brief.md"
$UncheckedSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $UncheckedOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $UncheckedCurrentResiduePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $UncheckedSucceeded = $false
    }
}
catch {
    $UncheckedSucceeded = $false
}
if ($UncheckedSucceeded) {
    throw "approval brief writer must reject current-residue evidence without machine_state_checked=true."
}

$FalseCheckedCurrentResiduePath = Join-Path $TempDir "false-checked-current-residue.json"
[ordered]@{
    generated_at = "2026-06-25T14:14:19.4882370-07:00"
    machine_state_checked = $false
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $FalseCheckedCurrentResiduePath -Encoding utf8
$FalseCheckedOutputPath = Join-Path $TempDir "false-checked-approval-brief.md"
$FalseCheckedSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $AuditPath `
        -OutputPath $FalseCheckedOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $FalseCheckedCurrentResiduePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $FalseCheckedSucceeded = $false
    }
}
catch {
    $FalseCheckedSucceeded = $false
}
if ($FalseCheckedSucceeded) {
    throw "approval brief writer must reject current-residue evidence with machine_state_checked=false."
}

$InvalidAuditPath = Join-Path $TempDir "invalid-timestamp-audit.json"
$InvalidAudit = $Audit | ConvertFrom-Json
$InvalidAudit.generated_at = "not-a-timestamp"
$InvalidAudit | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $InvalidAuditPath -Encoding utf8
$InvalidAuditOutputPath = Join-Path $TempDir "invalid-audit-approval-brief.md"
$InvalidAuditSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath $CleanupPlanPath `
        -AuditPath $InvalidAuditPath `
        -OutputPath $InvalidAuditOutputPath `
        -YuneRoot $RelativeYuneRoot `
        -InstallDir $RelativeInstallDir `
        -CurrentResiduePath $CurrentResiduePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $InvalidAuditSucceeded = $false
    }
}
catch {
    $InvalidAuditSucceeded = $false
}
if ($InvalidAuditSucceeded) {
    throw "approval brief writer must reject closeout audit evidence without parseable generated_at."
}

$Plan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\plans\history\m01-plan-windows-product.md")
foreach ($RequiredPlanText in @(
        'tools\write-m01-approval-brief.ps1',
        'tools\test-approval-brief-contract.ps1',
        'docs\evidence\m01\installer\approval-brief.md'
    )) {
    if ($Plan -notmatch [regex]::Escape($RequiredPlanText)) {
        throw "active plan is missing approval brief reference: $RequiredPlanText"
    }
}

Write-Host "M01 approval brief is non-mutating and operator-ready."
