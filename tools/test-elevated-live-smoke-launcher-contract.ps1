param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Launcher = Join-Path $RepoRoot "tools\start-p2-win01-elevated-live-smoke.ps1"

if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "missing elevated live-smoke launcher: tools\start-p2-win01-elevated-live-smoke.ps1"
}

$Source = Get-Content -Raw -LiteralPath $Launcher

foreach ($Required in @(
        '$ErrorActionPreference = "Stop"',
        '$PowerShellPath',
        'Require-ApprovedMachineStateChange',
        'Require-LiveSmokeApprovalNote',
        'Start-Process',
        '-Verb RunAs',
        '-WindowStyle Hidden',
        '-Wait',
        '-PassThru',
        'elevation-canceled',
        'PrepPreflightPath',
        'Assert-PrepPreflightReadyForElevation',
        'prep-preflight-invalid',
        'ValidatePrepOnly',
        'prep-preflight-ready',
        'approved_machine_state_change',
        'elevated_process_started',
        'transcript_exists',
        'machine_state_changed_before_elevated_process'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "elevated live-smoke launcher is missing contract text: $Required"
    }
}

$ApprovalGuardIndex = $Source.IndexOf('Require-ApprovedMachineStateChange')
$ApprovalNoteIndex = $Source.IndexOf('Require-LiveSmokeApprovalNote')
$StartProcessIndex = $Source.IndexOf('Start-Process')
$ResultWriterIndex = $Source.IndexOf('function Write-ElevatedLiveSmokeLaunchResult')
$PrepPreflightIndex = $Source.LastIndexOf('Assert-PrepPreflightReadyForElevation')

if ($ApprovalGuardIndex -lt 0 -or $ApprovalNoteIndex -lt 0 -or $StartProcessIndex -lt 0 -or $ResultWriterIndex -lt 0 -or $PrepPreflightIndex -lt 0) {
    throw "elevated live-smoke launcher is missing ordered approval, result, or Start-Process blocks."
}
if ($ApprovalGuardIndex -gt $StartProcessIndex -or $ApprovalNoteIndex -gt $StartProcessIndex) {
    throw "elevated live-smoke launcher must validate approval before Start-Process -Verb RunAs."
}
if ($ResultWriterIndex -gt $StartProcessIndex) {
    throw "elevated live-smoke launcher must define durable launch-result writing before Start-Process."
}
if ($PrepPreflightIndex -gt $StartProcessIndex) {
    throw "elevated live-smoke launcher must validate prep preflight evidence before Start-Process -Verb RunAs."
}

function Invoke-LauncherChild {
    param([string[]]$Arguments)

    function Quote-ProcessArgument {
        param([string]$Value)
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    $Psi = [System.Diagnostics.ProcessStartInfo]::new()
    $Psi.FileName = "powershell.exe"
    $Psi.UseShellExecute = $false
    $Psi.RedirectStandardOutput = $true
    $Psi.RedirectStandardError = $true
    $Psi.Arguments = (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Launcher) + $Arguments |
        ForEach-Object { Quote-ProcessArgument $_ }) -join " "
    $Process = [System.Diagnostics.Process]::Start($Psi)
    $Stdout = $Process.StandardOutput.ReadToEnd()
    $Stderr = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Text = (@($Stdout, $Stderr) -join "`n")
    }
}

$TempDirRoot = Join-Path $env:TEMP "yune-windows\p2-win01-elevated-launcher-test"
$TempDir = Join-Path $TempDirRoot ([guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $TempDir | Out-Null
$DefaultYuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune"
$DefaultInstallDir = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Yune\WindowsIme"))
$ExistingBrowserPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"

$UnapprovedEvidenceRoot = Join-Path $TempDir "unapproved-evidence"
$NoApprovalOutput = Invoke-LauncherChild -Arguments @(
    "-EvidenceRoot",
    $UnapprovedEvidenceRoot,
    "-BrowserPath",
    $ExistingBrowserPath,
    "-ApprovalNote",
    "User approved elevated live smoke in this session."
)
if ($NoApprovalOutput.ExitCode -eq 0 -or $NoApprovalOutput.Text -notmatch "without explicit approval") {
    throw "elevated live-smoke launcher must refuse before UAC without -ApprovedMachineStateChange."
}
if (Test-Path -LiteralPath $UnapprovedEvidenceRoot) {
    throw "elevated live-smoke launcher must not create evidence directories before explicit approval."
}

$BlankNoteEvidenceRoot = Join-Path $TempDir "blank-note-evidence"
$BlankNoteOutput = Invoke-LauncherChild -Arguments @(
    "-ApprovedMachineStateChange",
    "-EvidenceRoot",
    $BlankNoteEvidenceRoot,
    "-BrowserPath",
    $ExistingBrowserPath
)
if ($BlankNoteOutput.ExitCode -eq 0 -or $BlankNoteOutput.Text -notmatch "requires -ApprovalNote") {
    throw "elevated live-smoke launcher must refuse blank approval notes before UAC."
}
if (Test-Path -LiteralPath $BlankNoteEvidenceRoot) {
    throw "elevated live-smoke launcher must not create evidence directories before a valid approval note."
}

$LaunchResultPath = Join-Path $TempDir "launch-result.json"
Remove-Item -LiteralPath $LaunchResultPath -Force -ErrorAction SilentlyContinue
$MissingPowerShell = Join-Path $TempDir "missing-powershell.exe"
$ValidPrepPreflightPath = Join-Path $TempDir "valid-prep-preflight.json"
$InvalidPrepPreflightPath = Join-Path $TempDir "invalid-prep-preflight.json"
$SelfReferentialPrepPreflightPath = Join-Path $TempDir "self-referential-prep-preflight.json"
[ordered]@{
    generated_at = "2026-06-27T02:29:00.0000000-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    machine_residue_source = "test"
    machine_state_issues = @()
    filesystem_leftovers = @()
    ready_for_live_smoke = $false
    install_dir = $DefaultInstallDir
    install_dir_exists = $false
    server_process_count = 0
    yune_root = $DefaultYuneRoot
    yune_runtime_exists = $true
    yune_schema_exists = $true
    tsf_source_exists = $true
    server_source_exists = $true
    build_script_exists = $true
    is_administrator = $false
    is_sta = $true
    browser_available = $true
    browser_path = $ExistingBrowserPath
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $ValidPrepPreflightPath -Encoding utf8
[ordered]@{
    generated_at = "2026-06-27T02:30:00.0000000-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    machine_residue_source = "test"
    machine_state_issues = @("dirty prep preflight residue")
    filesystem_leftovers = @()
    ready_for_live_smoke = $false
    install_dir = $DefaultInstallDir
    install_dir_exists = $false
    server_process_count = 0
    yune_root = $DefaultYuneRoot
    yune_runtime_exists = $true
    yune_schema_exists = $true
    tsf_source_exists = $true
    server_source_exists = $true
    build_script_exists = $true
    is_administrator = $false
    is_sta = $true
    browser_available = $true
    browser_path = $ExistingBrowserPath
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $InvalidPrepPreflightPath -Encoding utf8
[ordered]@{
    generated_at = "2026-06-27T02:31:00.0000000-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    machine_residue_source = [System.IO.Path]::GetFullPath($SelfReferentialPrepPreflightPath)
    machine_state_issues = @()
    filesystem_leftovers = @()
    ready_for_live_smoke = $false
    install_dir = $DefaultInstallDir
    install_dir_exists = $false
    server_process_count = 0
    yune_root = $DefaultYuneRoot
    yune_runtime_exists = $true
    yune_schema_exists = $true
    tsf_source_exists = $true
    server_source_exists = $true
    build_script_exists = $true
    is_administrator = $false
    is_sta = $true
    browser_available = $true
    browser_path = $ExistingBrowserPath
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $SelfReferentialPrepPreflightPath -Encoding utf8

$ValidateOnlyOutput = Invoke-LauncherChild -Arguments @(
    "-PrepPreflightPath",
    $ValidPrepPreflightPath,
    "-LaunchResultPath",
    $LaunchResultPath,
    "-PowerShellPath",
    $MissingPowerShell,
    "-ValidatePrepOnly",
    "-BrowserPath",
    $ExistingBrowserPath
)
if ($ValidateOnlyOutput.ExitCode -ne 0 -or $ValidateOnlyOutput.Text -notmatch "prep-preflight-ready") {
    throw "elevated live-smoke launcher must validate prep evidence without starting UAC when -ValidatePrepOnly is set."
}
if (-not (Test-Path -LiteralPath $LaunchResultPath)) {
    throw "elevated live-smoke launcher must write launch-result evidence for prep validation."
}
$ReadyLaunchResult = Get-Content -Raw -LiteralPath $LaunchResultPath | ConvertFrom-Json
if ($ReadyLaunchResult.status -ne "prep-preflight-ready" -or
    $ReadyLaunchResult.approved_machine_state_change -ne $false -or
    $ReadyLaunchResult.elevated_process_started -ne $false -or
    $ReadyLaunchResult.transcript_exists -ne $false -or
    $null -ne $ReadyLaunchResult.exit_code -or
    $ReadyLaunchResult.machine_state_changed_before_elevated_process -ne $false -or
    $ReadyLaunchResult.prep_preflight_path -ne [System.IO.Path]::GetFullPath($ValidPrepPreflightPath)) {
    throw "elevated live-smoke prep validation result has weak ready fields."
}
Remove-Item -LiteralPath $LaunchResultPath -Force -ErrorAction SilentlyContinue

$ValidateOnlyWithApprovalOutput = Invoke-LauncherChild -Arguments @(
    "-PrepPreflightPath",
    $ValidPrepPreflightPath,
    "-LaunchResultPath",
    $LaunchResultPath,
    "-ValidatePrepOnly",
    "-ApprovedMachineStateChange",
    "-ApprovalNote",
    "User approved elevated live smoke in this session.",
    "-BrowserPath",
    $ExistingBrowserPath
)
if ($ValidateOnlyWithApprovalOutput.ExitCode -eq 0 -or
    $ValidateOnlyWithApprovalOutput.Text -notmatch "ValidatePrepOnly") {
    throw "elevated live-smoke launcher must reject approval switches in non-mutating prep validation mode."
}
if (Test-Path -LiteralPath $LaunchResultPath) {
    throw "elevated live-smoke launcher must not write launch-result evidence for invalid prep-validation switches."
}

$InvalidPrepOutput = Invoke-LauncherChild -Arguments @(
    "-PrepPreflightPath",
    $InvalidPrepPreflightPath,
    "-LaunchResultPath",
    $LaunchResultPath,
    "-ValidatePrepOnly",
    "-BrowserPath",
    $ExistingBrowserPath
)
if ($InvalidPrepOutput.ExitCode -eq 0 -or $InvalidPrepOutput.Text -notmatch "prep-preflight-invalid") {
    throw "elevated live-smoke launcher must reject invalid prep preflight evidence before UAC."
}
if (-not (Test-Path -LiteralPath $LaunchResultPath)) {
    throw "elevated live-smoke launcher must write launch-result evidence for invalid prep preflight."
}
$PrepLaunchResult = Get-Content -Raw -LiteralPath $LaunchResultPath | ConvertFrom-Json
if ($PrepLaunchResult.status -ne "prep-preflight-invalid" -or
    $PrepLaunchResult.elevated_process_started -ne $false -or
    $PrepLaunchResult.transcript_exists -ne $false -or
    $PrepLaunchResult.machine_state_changed_before_elevated_process -ne $false) {
    throw "elevated live-smoke launch-result evidence has weak invalid-prep fields."
}
Remove-Item -LiteralPath $LaunchResultPath -Force -ErrorAction SilentlyContinue

$SelfReferentialPrepOutput = Invoke-LauncherChild -Arguments @(
    "-PrepPreflightPath",
    $SelfReferentialPrepPreflightPath,
    "-LaunchResultPath",
    $LaunchResultPath,
    "-ValidatePrepOnly",
    "-BrowserPath",
    $ExistingBrowserPath
)
if ($SelfReferentialPrepOutput.ExitCode -eq 0 -or $SelfReferentialPrepOutput.Text -notmatch "prep-preflight-invalid") {
    throw "elevated live-smoke launcher must reject self-referential prep preflight evidence before UAC."
}
$SelfReferentialLaunchResult = Get-Content -Raw -LiteralPath $LaunchResultPath | ConvertFrom-Json
if ($SelfReferentialLaunchResult.status -ne "prep-preflight-invalid" -or
    $SelfReferentialLaunchResult.elevated_process_started -ne $false -or
    $SelfReferentialLaunchResult.transcript_exists -ne $false) {
    throw "elevated live-smoke launch-result evidence has weak self-referential prep fields."
}
Remove-Item -LiteralPath $LaunchResultPath -Force -ErrorAction SilentlyContinue

$StartFailureOutput = Invoke-LauncherChild -Arguments @(
    "-ApprovedMachineStateChange",
    "-ApprovalNote",
    "User approved elevated live smoke in this session.",
    "-PowerShellPath",
    $MissingPowerShell,
    "-PrepPreflightPath",
    $ValidPrepPreflightPath,
    "-LaunchResultPath",
    $LaunchResultPath,
    "-BrowserPath",
    "C:\Program Files\Google\Chrome\Application\chrome.exe"
)
if ($StartFailureOutput.ExitCode -eq 0 -or $StartFailureOutput.Text -notmatch "failed-to-start") {
    throw "elevated live-smoke launcher must report failed-to-start when the elevated process cannot be created."
}
if (-not (Test-Path -LiteralPath $LaunchResultPath)) {
    throw "elevated live-smoke launcher must write launch-result evidence when process creation fails."
}
$LaunchResult = Get-Content -Raw -LiteralPath $LaunchResultPath | ConvertFrom-Json
if ($LaunchResult.status -ne "failed-to-start" -or
    $LaunchResult.elevated_process_started -ne $false -or
    $LaunchResult.transcript_exists -ne $false -or
    $LaunchResult.machine_state_changed_before_elevated_process -ne $false -or
    $LaunchResult.approved_machine_state_change -ne $true) {
    throw "elevated live-smoke launch-result evidence has weak failed-to-start fields."
}
if ($null -ne $LaunchResult.exit_code) {
    throw "elevated live-smoke launch-result evidence must record exit_code=null when no elevated process started."
}
if ([string]::IsNullOrWhiteSpace([string]$LaunchResult.generated_at) -or
    [string]::IsNullOrWhiteSpace([string]$LaunchResult.error_message) -or
    [string]::IsNullOrWhiteSpace([string]$LaunchResult.transcript_path)) {
    throw "elevated live-smoke launch-result evidence must include generated_at, error_message, and transcript_path."
}

Write-Host "Elevated live-smoke launcher is approval-gated and records failed or canceled elevation distinctly."
