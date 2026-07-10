param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$EvidenceRoot = Join-Path $RepoRoot "docs\evidence\m10"
$ReadmePath = Join-Path $EvidenceRoot "README.md"
$TemplatePath = Join-Path $EvidenceRoot "summary.template.json"
$PreflightPath = Join-Path $EvidenceRoot "non-elevated-preflight.json"
$SummaryPath = Join-Path $EvidenceRoot "summary.json"
$SummaryMarkdownPath = Join-Path $EvidenceRoot "summary.md"
$ToolbarCapture = Join-Path $RepoRoot "tools\dev\capture-m10-toolbar-session.ps1"
$ToolbarFinalize = Join-Path $RepoRoot "tools\dev\finalize-m10-toolbar-session.ps1"
$SettingsCapture = Join-Path $RepoRoot "tools\dev\capture-m10-settings-geometry.ps1"

foreach ($Path in @(
        $ReadmePath,
        $TemplatePath,
        $PreflightPath,
        $ToolbarCapture,
        $ToolbarFinalize,
        $SettingsCapture
    )) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M10 evidence-tooling input: $Path"
    }
}

function Require-Property([object]$Object, [string]$Name, [string]$Context) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
        throw "$Context is missing property: $Name"
    }
    return $Object.$Name
}

function Require-Text([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-IsoTimestamp([string]$Value, [string]$Context) {
    $Parsed = [DateTimeOffset]::MinValue
    if ([string]::IsNullOrWhiteSpace($Value) -or
        -not [DateTimeOffset]::TryParse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$Parsed)) {
        throw "$Context must be an ISO-8601 round-trip timestamp."
    }
}

function Assert-Sha256([string]$Value, [string]$Context) {
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "$Context must be a 64-character SHA-256 value."
    }
}

function Resolve-EvidencePath([string]$RelativePath, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Context must be a non-empty repository-relative path."
    }
    $Candidate = [IO.Path]::GetFullPath((Join-Path $RepoRoot $RelativePath))
    if (-not $Candidate.StartsWith(
            $RepoRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escapes the repository: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        throw "$Context does not exist: $RelativePath"
    }
    return $Candidate
}

function Assert-ScriptParses([string]$Path) {
    $Tokens = $null
    $ParseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$ParseErrors)
    if ($ParseErrors.Count -ne 0) {
        throw "$Path has PowerShell parse errors: $($ParseErrors -join '; ')"
    }
}

foreach ($CaptureScript in @($ToolbarCapture, $ToolbarFinalize, $SettingsCapture)) {
    Assert-ScriptParses $CaptureScript
    $Source = Get-Content -Raw -LiteralPath $CaptureScript
    foreach ($Forbidden in @(
            'GetWindowText',
            'GetWindowTextLength',
            'MainWindowTitle',
            'SendInput',
            'keybd_event',
            'SetForegroundWindow',
            'SetWindowPos',
            'MoveWindow',
            'ShowWindow',
            'SetCapture',
            'ReleaseCapture',
            'Stop-Process',
            'Start-Process'
        )) {
        if ($Source -match [regex]::Escape($Forbidden)) {
            throw "M10 evidence capture must remain read-only and privacy-safe: $Forbidden in $CaptureScript"
        }
    }
}

$ToolbarSource = Get-Content -Raw -LiteralPath $ToolbarCapture
foreach ($Required in @(
        'capture-language-bar-topology.ps1',
        'm10_toolbar_topology_capture',
        'machine_observed',
        'operator_report',
        'not collected during capture',
        'maximum_visible_toolbar_windows',
        'samples_with_foreground_owner_mismatch',
        'samples_with_unexpected_host_process',
        'sampled_visible_hwnd_stable',
        'final_sample_visible_toolbar_count',
        'final_sample_has_toolbar_capture',
        'final_sample_owner_matches_foreground_root',
        'NewSettingsProcessIdsObserved',
        'settings_process_ids_started_during_capture',
        'ExpectedHostProcessName',
        'operator-verdict=pending'
    )) {
    Require-Text $ToolbarSource ([regex]::Escape($Required)) `
        "M10 toolbar recorder is missing required pattern: $Required"
}
if ($ToolbarSource -match 'VisualCopiesOrAfterimages|GripDragsCompleted|SettingsSegmentDragsCompleted') {
    throw "M10 topology capture must not accept operator counts or pass/fail verdicts before the actions finish."
}
$SamplingLoopIndex = $ToolbarSource.IndexOf('for ($SampleIndex = 0;')
$SettingsSampleIndex = $ToolbarSource.IndexOf(
    'foreach ($SettingsProcessId in @(Get-SettingsProcessIds))',
    [Math]::Max(0, $SamplingLoopIndex))
$PostLoopSettingsIndex = $ToolbarSource.IndexOf(
    '$SettingsProcessesAfter = @(Get-SettingsProcessIds)',
    [Math]::Max(0, $SamplingLoopIndex))
if ($SamplingLoopIndex -lt 0 -or
    $SettingsSampleIndex -lt $SamplingLoopIndex -or
    $PostLoopSettingsIndex -lt 0 -or
    $SettingsSampleIndex -gt $PostLoopSettingsIndex) {
    throw "M10 topology capture must sample newly created settings processes inside every topology iteration."
}

$ToolbarFinalizeSource = Get-Content -Raw -LiteralPath $ToolbarFinalize
foreach ($Required in @(
        'm10_toolbar_topology_capture',
        'm10_toolbar_session_final',
        'Get-FileHash',
        'source_capture',
        'must not overwrite the immutable capture file',
        'manually reported after capture',
        'GripDragsCompleted',
        'SettingsSegmentDragsCompleted',
        'VisualCopiesOrAfterimagesAbsent',
        'PositionPersistedAfterHostRestart'
    )) {
    Require-Text $ToolbarFinalizeSource ([regex]::Escape($Required)) `
        "M10 toolbar finalizer is missing required pattern: $Required"
}

$SettingsSource = Get-Content -Raw -LiteralPath $SettingsCapture
foreach ($Required in @(
        'YuneWindowsSettingsWindow',
        'GetDpiForWindow',
        'GetClientRect',
        'GetScrollInfo',
        'visible_children_fully_within_client',
        'm10_settings_geometry',
        'operator_report',
        'manually reported; not inferred',
        'Theme',
        'AllControlsReachable',
        'TypographyLegibleAndCrisp',
        'CloseReopenStableNoOrphan'
    )) {
    Require-Text $SettingsSource ([regex]::Escape($Required)) `
        "M10 settings geometry collector is missing required pattern: $Required"
}

$Readme = Get-Content -Raw -LiteralPath $ReadmePath
foreach ($Required in @(
        'No file in this directory currently claims that M10 passed',
        '10 grip and 10 settings-segment drags',
        'light and dark themes',
        'exact capture SHA-256',
        'cannot accept pass/fail verdicts',
        'Machine-state evidence must be committed separately'
    )) {
    Require-Text $Readme ([regex]::Escape($Required)) `
        "M10 evidence README is missing honesty or acceptance guidance: $Required"
}

$Scratch = Join-Path $env:TEMP ("yune-windows\m10-evidence-contract-" + $PID)
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
try {
    $ToolbarSmokePath = Join-Path $Scratch "toolbar.json"
    & $ToolbarCapture `
        -HostId notepad `
        -ExpectedHostProcessName notepad `
        -OutputPath $ToolbarSmokePath `
        -SampleCount 1 `
        -IntervalMs 20 | Out-Null
    $ToolbarSmoke = Get-Content -Raw -LiteralPath $ToolbarSmokePath | ConvertFrom-Json
    if ($ToolbarSmoke.evidence_kind -ne "m10_toolbar_topology_capture" -or
        [int]$ToolbarSmoke.sampling.captured_sample_count -ne 1 -or
        $ToolbarSmoke.operator_report.verdict -ne "pending" -or
        @($ToolbarSmoke.machine_observed.settings_process_ids_started_during_capture).Count -ne 0 -or
        [bool]$ToolbarSmoke.gate_ready) {
        throw "M10 toolbar recorder smoke must emit one honest pending session."
    }

    $ToolbarFinalPath = Join-Path $Scratch "toolbar-final.json"
    & $ToolbarFinalize `
        -CapturePath $ToolbarSmokePath `
        -OutputPath $ToolbarFinalPath `
        -GripDragsCompleted 10 `
        -SettingsSegmentDragsCompleted 10 `
        -VisualCopiesOrAfterimagesAbsent pass `
        -FocusNeverStolen pass `
        -SettingsDragDidNotActivate pass `
        -CantoneseOnly pass `
        -PositionPersistedAfterFocus pass `
        -PositionPersistedAfterHostRestart pass | Out-Null
    $ToolbarFinal = Get-Content -Raw -LiteralPath $ToolbarFinalPath | ConvertFrom-Json
    $ExpectedCaptureHash = (Get-FileHash -LiteralPath $ToolbarSmokePath -Algorithm SHA256).Hash
    if ($ToolbarFinal.evidence_kind -ne "m10_toolbar_session_final" -or
        $ToolbarFinal.source_capture.sha256 -ne $ExpectedCaptureHash -or
        $ToolbarFinal.operator_report.total_drags_completed -ne 20 -or
        -not [bool]$ToolbarFinal.operator_report.report_complete -or
        [bool]$ToolbarFinal.gate_ready) {
        throw "M10 toolbar finalizer must bind the later complete operator report to the exact non-passing smoke capture."
    }

    $SettingsSmokePath = Join-Path $Scratch "settings.json"
    & $SettingsCapture `
        -OutputPath $SettingsSmokePath `
        -Phase initial `
        -Theme unknown | Out-Null
    $SettingsSmokeJson = Get-Content -Raw -LiteralPath $SettingsSmokePath
    $SettingsSmoke = $SettingsSmokeJson | ConvertFrom-Json
    if ($SettingsSmoke.evidence_kind -ne "m10_settings_geometry" -or
        $SettingsSmoke.phase -ne "initial" -or
        $SettingsSmoke.theme_reported_by_operator -ne "unknown" -or
        $SettingsSmoke.operator_report.all_controls_reachable -ne "pending") {
        throw "M10 settings collector smoke must emit honest pending geometry evidence."
    }
    foreach ($Json in @(
            (Get-Content -Raw -LiteralPath $ToolbarSmokePath),
            (Get-Content -Raw -LiteralPath $ToolbarFinalPath),
            $SettingsSmokeJson
        )) {
        if ($Json -match '"(?:title|text|keystrokes?)"\s*:') {
            throw "M10 capture output exposed a prohibited title/text/keystroke field."
        }
    }
}
finally {
    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

$EvidenceJsonPath = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
    $SummaryPath
}
else {
    $TemplatePath
}
$Evidence = Get-Content -Raw -LiteralPath $EvidenceJsonPath | ConvertFrom-Json

if ([int](Require-Property $Evidence "schema_version" "M10 evidence") -ne 1 -or
    (Require-Property $Evidence "milestone" "M10 evidence") -ne "M10") {
    throw "M10 evidence must use schema_version 1 and milestone M10."
}

$NonElevated = Require-Property $Evidence "non_elevated" "M10 evidence"
$DpiMatrix = @($NonElevated.settings_dpi_percent_matrix | ForEach-Object { [int]$_ })
if (($DpiMatrix -join ',') -ne '100,125,150,200') {
    throw "M10 evidence must retain the 100/125/150/200 percent settings matrix."
}
$RequiredChecks = @(
    "git diff --check",
    "tools/test-tsf-shell-build.ps1",
    "tools/test-language-bar-smoke.ps1",
    "tools/test-settings-window-smoke.ps1",
    "tools/test-m08-modern-toolbar-contract.ps1",
    "tools/test-m09-settings-panel-contract.ps1",
    "tools/test-m11-ui-modernization-contract.ps1",
    "tools/test-m11c-dcomp-glass-toolbar-contract.ps1",
    "tools/test-language-bar-window-contract.ps1",
    "tools/test-language-bar-topology-diagnostic-contract.ps1",
    "tools/test-settings-ime-state-contract.ps1",
    "tools/test-server-ime-state-protocol-contract.ps1",
    "tools/test-tsf-server-response-validation-contract.ps1",
    "tools/test-m11d-activation-reliability-contract.ps1",
    "tools/test-m11d-multiprocess-reliability-smoke.ps1"
)
foreach ($RequiredCheck in $RequiredChecks) {
    $Match = @($NonElevated.checks | Where-Object { $_.command -eq $RequiredCheck })
    if ($Match.Count -ne 1) {
        throw "M10 evidence schema is missing required preflight check: $RequiredCheck"
    }
}
$Preflight = Get-Content -Raw -LiteralPath $PreflightPath | ConvertFrom-Json
if ([int]$Preflight.schema_version -ne 1 -or
    $Preflight.milestone -ne "M10" -or
    $Preflight.evidence_kind -ne "non_elevated_preflight" -or
    $Preflight.verdict -ne "pass" -or
    $Preflight.implementation_commit -ne $Evidence.source.implementation_commit -or
    $Preflight.checked_tree_commit -ne $Evidence.source.implementation_commit -or
    (@($Preflight.settings_dpi_percent_matrix | ForEach-Object { [int]$_ }) -join ',') -ne
        '100,125,150,200' -or
    -not [bool]$Preflight.settings_minimum_larger_scroll_each_dpi -or
    [bool]$Preflight.m11_boundary.m11_acceptance_claimed) {
    throw "M10 non-elevated preflight is not a passing, scope-honest record for the implementation commit."
}
foreach ($RequiredCheck in $RequiredChecks) {
    $Match = @($Preflight.checks | Where-Object { $_.command -eq $RequiredCheck })
    if ($Match.Count -ne 1 -or -not [bool]$Match[0].passed) {
        throw "M10 non-elevated preflight is missing a passing check: $RequiredCheck"
    }
}

$ToolbarGate = Require-Property $Evidence "toolbar_gate" "M10 evidence"
$Artifacts = Require-Property $Evidence "artifacts" "M10 evidence"
foreach ($BindingField in @(
        "holder_evidence_path",
        "candidate_manifest_path",
        "candidate_manifest_sha256",
        "post_restart_verification_path",
        "post_restart_verification_sha256"
    )) {
    [void](Require-Property $Artifacts $BindingField "M10 artifact evidence")
}
$Hosts = @($ToolbarGate.hosts)
$ExpectedHostIds = @("notepad", "chromium", "explorer", "electron")
if ($Hosts.Count -ne 4 -or
    ((@($Hosts.id | Sort-Object) -join ',') -ne (@($ExpectedHostIds | Sort-Object) -join ','))) {
    throw "M10 toolbar evidence must contain exactly Notepad, Chromium, Explorer, and Electron host entries."
}

if ($Evidence.status -eq "pending") {
    if ($EvidenceJsonPath -ne $TemplatePath -or
        $NonElevated.verdict -ne "pending" -or
        $ToolbarGate.verdict -ne "pending" -or
        $Evidence.settings_gate.verdict -ne "pending" -or
        [int]$ToolbarGate.total_drags -ne 0 -or
        [bool]$Evidence.artifacts.all_built_and_installed_hashes_match -or
        -not [string]::IsNullOrWhiteSpace([string]$Artifacts.candidate_manifest_path) -or
        -not [string]::IsNullOrWhiteSpace([string]$Artifacts.post_restart_verification_path) -or
        $Preflight.deployment_source_commit -ne
            "pending_until_frozen_docs_commit" -or
        [bool]$Evidence.machine_state_evidence_committed_separately) {
        throw "M10 pending template must not pre-claim non-elevated, installed, or publication success."
    }
    Write-Host "M10 evidence tooling/template contract passed; installed summary remains honestly pending."
    return
}

if ($Evidence.status -ne "complete" -or $EvidenceJsonPath -ne $SummaryPath) {
    throw "A non-pending M10 evidence record must be docs/evidence/m10/summary.json with status complete."
}
if (-not (Test-Path -LiteralPath $SummaryMarkdownPath -PathType Leaf)) {
    throw "completed M10 evidence requires docs/evidence/m10/summary.md."
}

$SourceEvidence = Require-Property $Evidence "source" "M10 evidence"
foreach ($CommitField in @("source_commit", "implementation_commit", "pre_rebaseline_baseline")) {
    $Commit = [string](Require-Property $SourceEvidence $CommitField "M10 source evidence")
    if ($Commit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "M10 source evidence $CommitField must be a full commit hash."
    }
}
if ($SourceEvidence.source_commit -eq "1f419837b0575dc1ea47dba2785cbb6949b7e73c" -or
    -not [bool]$SourceEvidence.product_build_input_diff_recorded) {
    throw "M10 cannot close on the older clone-proof commit or without a product-input diff record."
}
[void](Assert-IsoTimestamp ([string]$Preflight.captured_at) `
    "M10 non-elevated preflight")
if ($Preflight.deployment_source_commit -ne $SourceEvidence.source_commit) {
    throw "M10 non-elevated preflight is not bound to the deployed source commit."
}
[void](Resolve-EvidencePath $SourceEvidence.product_build_input_diff_path "M10 product-input diff evidence")

if ($NonElevated.verdict -ne "pass" -or
    -not [bool]$NonElevated.settings_minimum_larger_scroll_each_dpi) {
    throw "M10 completion requires passing non-elevated checks and the full settings DPI matrix."
}
foreach ($RequiredCheck in $RequiredChecks) {
    $Match = @($NonElevated.checks | Where-Object { $_.command -eq $RequiredCheck })
    if ($Match.Count -ne 1 -or -not [bool]$Match[0].passed) {
        throw "M10 completed evidence is missing a passing preflight check: $RequiredCheck"
    }
}

$CandidateManifestPath = Resolve-EvidencePath `
    ([string](Require-Property $Artifacts "candidate_manifest_path" "M10 artifact evidence")) `
    "M10 frozen-candidate manifest"
$CandidateManifestHash = [string](Require-Property `
        $Artifacts "candidate_manifest_sha256" "M10 artifact evidence")
Assert-Sha256 $CandidateManifestHash "M10 frozen-candidate manifest hash"
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateManifestPath).Hash -ne
    $CandidateManifestHash) {
    throw "M10 frozen-candidate manifest hash does not match its evidence file."
}
$CandidateManifest = Get-Content -Raw -LiteralPath $CandidateManifestPath |
    ConvertFrom-Json
if ([int]$CandidateManifest.schema_version -ne 1 -or
    $CandidateManifest.operation -ne "m10_frozen_candidate" -or
    $CandidateManifest.mode -ne "Deploy" -or
    $CandidateManifest.status -ne "deployed_restart_required" -or
    -not [bool]$CandidateManifest.source.clean -or
    -not [bool]$CandidateManifest.source.post_build_verified -or
    -not [bool]$CandidateManifest.package.post_build_verified -or
    [int]$CandidateManifest.build.invocation_count -ne 1 -or
    -not [bool]$CandidateManifest.deployment.performed -or
    -not [bool]$CandidateManifest.deployment.session_restart_required -or
    [bool]$CandidateManifest.deployment.live_test_allowed_without_restart -or
    $CandidateManifest.source.actual_commit -ne $SourceEvidence.source_commit -or
    $CandidateManifest.source.expected_commit -ne $SourceEvidence.source_commit) {
    throw "M10 frozen-candidate manifest is not the clean deployed source recorded by the summary."
}

$PostRestartVerificationPath = Resolve-EvidencePath `
    ([string](Require-Property $Artifacts "post_restart_verification_path" "M10 artifact evidence")) `
    "M10 post-restart verification"
$PostRestartVerificationHash = [string](Require-Property `
        $Artifacts "post_restart_verification_sha256" "M10 artifact evidence")
Assert-Sha256 $PostRestartVerificationHash "M10 post-restart verification hash"
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $PostRestartVerificationPath).Hash -ne
    $PostRestartVerificationHash) {
    throw "M10 post-restart verification hash does not match its evidence file."
}
$PostRestartVerification =
    Get-Content -Raw -LiteralPath $PostRestartVerificationPath |
    ConvertFrom-Json
if ([int]$PostRestartVerification.schema_version -ne 1 -or
    $PostRestartVerification.operation -ne
        "m10_frozen_candidate_post_restart_verify" -or
    -not [bool]$PostRestartVerification.pass -or
    @($PostRestartVerification.failures).Count -ne 0 -or
    $PostRestartVerification.candidate.manifest_sha256 -ne
        $CandidateManifestHash -or
    $PostRestartVerification.candidate.source_actual_commit -ne
        $SourceEvidence.source_commit -or
    -not [bool]$PostRestartVerification.candidate.source_clean -or
    -not [bool]$PostRestartVerification.candidate.source_post_build_verified -or
    -not [bool]$PostRestartVerification.candidate.package_post_build_verified -or
    -not [bool]$PostRestartVerification.candidate.deployment_completed_at_valid -or
    $PostRestartVerification.candidate.deployment_completed_at -ne
        $CandidateManifest.deployment.completed_at -or
    [int]$PostRestartVerification.holders.count -lt 1 -or
    -not [bool]$PostRestartVerification.holders.all_match_candidate_image_size -or
    -not [bool]$PostRestartVerification.holders.all_use_current_installed_path -or
    -not [bool]$PostRestartVerification.holders.all_start_times_known -or
    -not [bool]$PostRestartVerification.holders.all_started_strictly_after_deployment -or
    [int]$PostRestartVerification.holders.old_or_aside_install_root_path_count -ne 0 -or
    [int]$PostRestartVerification.installed_processes.server.current_installed_path_count -ne 1 -or
    -not [bool]$PostRestartVerification.installed_processes.server.exactly_one_running_installed_server -or
    -not [bool]$PostRestartVerification.installed_processes.server.no_old_or_aside_processes -or
    [int]$PostRestartVerification.installed_processes.server.unknown_path_count -ne 0 -or
    -not [bool]$PostRestartVerification.installed_processes.server.all_installed_start_times_known -or
    -not [bool]$PostRestartVerification.installed_processes.server.all_installed_started_strictly_after_deployment -or
    -not [bool]$PostRestartVerification.installed_processes.settings.no_old_or_aside_processes -or
    [int]$PostRestartVerification.installed_processes.settings.unknown_path_count -ne 0 -or
    -not [bool]$PostRestartVerification.installed_processes.settings.all_installed_start_times_known -or
    -not [bool]$PostRestartVerification.installed_processes.settings.all_installed_started_strictly_after_deployment -or
    [int]$PostRestartVerification.installed.pending_delete.install_root_entry_count -ne 0 -or
    -not [bool]$PostRestartVerification.installed.profile.registered -or
    -not [bool]$PostRestartVerification.installed.profile.active -or
    -not [bool]$PostRestartVerification.installed.com_registration.path_matches) {
    throw "M10 post-restart verifier is not a passing proof for the exact deployed candidate."
}

$ManifestArtifacts = @{}
foreach ($ManifestArtifact in @($CandidateManifest.build.artifacts)) {
    $ManifestArtifacts[[string]$ManifestArtifact.name] = $ManifestArtifact
}
$VerifiedArtifacts = @{}
foreach ($VerifiedArtifact in @($PostRestartVerification.installed.artifacts)) {
    $VerifiedArtifacts[[string]$VerifiedArtifact.name] = $VerifiedArtifact
}
foreach ($ArtifactName in @("tsf", "server", "settings", "default_skin")) {
    $Artifact = Require-Property $Artifacts $ArtifactName "M10 artifact evidence"
    Assert-Sha256 ([string]$Artifact.built_sha256) "M10 $ArtifactName built hash"
    Assert-Sha256 ([string]$Artifact.installed_sha256) "M10 $ArtifactName installed hash"
    if ($Artifact.built_sha256 -ne $Artifact.installed_sha256) {
        throw "M10 $ArtifactName built and installed hashes differ."
    }
    if (-not $ManifestArtifacts.ContainsKey($ArtifactName) -or
        -not $VerifiedArtifacts.ContainsKey($ArtifactName) -or
        $Artifact.built_sha256 -ne
            [string]$ManifestArtifacts[$ArtifactName].sha256 -or
        $Artifact.installed_sha256 -ne
            [string]$VerifiedArtifacts[$ArtifactName].actual_sha256 -or
        -not [bool]$VerifiedArtifacts[$ArtifactName].matches_candidate) {
        throw "M10 $ArtifactName hashes are not bound to the frozen manifest and post-restart verifier."
    }
}
if (-not [bool]$Artifacts.all_built_and_installed_hashes_match -or
    -not [bool]$Artifacts.all_loaded_tsf_holders_match) {
    throw "M10 completed evidence requires matching installed artifacts and loaded TSF holders."
}
$HolderEvidencePath = Resolve-EvidencePath `
    $Artifacts.holder_evidence_path `
    "M10 holder evidence"
if (-not [string]::Equals(
        $HolderEvidencePath,
        $PostRestartVerificationPath,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "M10 holder evidence must be the exact bound post-restart verification."
}

if ($ToolbarGate.verdict -ne "pass") {
    throw "M10 toolbar gate must pass before completion."
}
$ComputedTotalDrags = 0
foreach ($Host in $Hosts) {
    if ([int]$Host.grip_drags -lt 10 -or
        [int]$Host.settings_segment_drags -lt 10 -or
        [int]$Host.total_drags -ne ([int]$Host.grip_drags + [int]$Host.settings_segment_drags)) {
        throw "M10 host $($Host.id) requires at least 10 grip and 10 settings-segment drags with a consistent total."
    }
    $ComputedTotalDrags += [int]$Host.total_drags
    if ($Host.id -eq "electron" -and
        ([string]::IsNullOrWhiteSpace([string]$Host.host_name) -or
         [string]$Host.host_name -eq "Electron")) {
        throw "M10 Electron evidence must name the tested product."
    }
    if ([int]$Host.maximum_visible_toolbar_windows -gt 1 -or
        -not [bool]$Host.all_visible_owners_match_foreground_root -or
        -not [bool]$Host.sampled_visible_hwnd_stable -or
        -not [bool]$Host.no_stuck_capture -or
        [bool]$Host.settings_process_launched_by_drag -or
        -not [bool]$Host.settings_segment_drag_did_not_activate -or
        -not [bool]$Host.focus_never_stolen -or
        $Host.visual_copies_or_afterimages_absent -ne "pass" -or
        -not [bool]$Host.position_persisted_after_focus_movement -or
        -not [bool]$Host.position_persisted_after_host_restart) {
        throw "M10 host $($Host.id) does not satisfy the ownership/drag/visual/persistence gate."
    }
    $SessionPaths = @($Host.session_evidence)
    if ($SessionPaths.Count -eq 0) {
        throw "M10 host $($Host.id) has no topology-session evidence."
    }
    $SessionGripDrags = 0
    $SessionSettingsDrags = 0
    $SessionMaximumVisible = 0
    foreach ($SessionPath in $SessionPaths) {
        $ResolvedSession = Resolve-EvidencePath ([string]$SessionPath) "M10 $($Host.id) topology session"
        $Session = Get-Content -Raw -LiteralPath $ResolvedSession | ConvertFrom-Json
        if ($Session.evidence_kind -ne "m10_toolbar_session_final" -or
            $Session.host.id -ne $Host.id -or
            -not [bool]$Session.machine_observed.topology_ready -or
            [int]$Session.machine_observed.final_sample_visible_toolbar_count -ne 1 -or
            [bool]$Session.machine_observed.final_sample_has_toolbar_capture -or
            -not [bool]$Session.machine_observed.final_sample_owner_matches_foreground_root -or
            -not [bool]$Session.operator_report.report_complete -or
            -not [bool]$Session.gate_ready) {
            throw "M10 $($Host.id) topology session is not a complete passing recorder result."
        }
        $SourceCaptureName = [string]$Session.source_capture.file_name
        if ([string]::IsNullOrWhiteSpace($SourceCaptureName) -or
            [IO.Path]::GetFileName($SourceCaptureName) -ne $SourceCaptureName) {
            throw "M10 $($Host.id) finalized session has an unsafe source capture name."
        }
        $SourceCapturePath = Join-Path (Split-Path -Parent $ResolvedSession) $SourceCaptureName
        if (-not (Test-Path -LiteralPath $SourceCapturePath -PathType Leaf)) {
            throw "M10 $($Host.id) finalized session is missing its immutable source capture."
        }
        $SourceCaptureHash = (Get-FileHash -LiteralPath $SourceCapturePath -Algorithm SHA256).Hash
        if ($SourceCaptureHash -ne [string]$Session.source_capture.sha256) {
            throw "M10 $($Host.id) finalized session source capture hash does not match."
        }
        $SessionGripDrags += [int]$Session.operator_report.grip_drags_completed
        $SessionSettingsDrags += [int]$Session.operator_report.settings_segment_drags_completed
        $SessionMaximumVisible = [Math]::Max(
            $SessionMaximumVisible,
            [int]$Session.machine_observed.maximum_visible_toolbar_windows)
    }
    if ($SessionGripDrags -ne [int]$Host.grip_drags -or
        $SessionSettingsDrags -ne [int]$Host.settings_segment_drags -or
        $SessionMaximumVisible -ne [int]$Host.maximum_visible_toolbar_windows) {
        throw "M10 host $($Host.id) summary counts do not match its SHA-pinned finalized session evidence."
    }
    if (-not [bool]$Host.no_stuck_capture) {
        throw "M10 host $($Host.id) cannot claim completion without machine-observed released capture in every session."
    }
}
if ($ComputedTotalDrags -lt 80 -or [int]$ToolbarGate.total_drags -ne $ComputedTotalDrags) {
    throw "M10 completed toolbar evidence requires at least 80 total drags and a consistent aggregate."
}
if (-not [bool]$ToolbarGate.ascii_active_cantonese_state_exercised -or
    -not [bool]$ToolbarGate.octagram_schema_cantonese_state_exercised -or
    $ToolbarGate.backdrop_or_flat_fallback_usable -ne "pass") {
    throw "M10 toolbar evidence must exercise Cantonese states and the effective backdrop/fallback."
}
if ($ToolbarGate.operator_visual_verdict.verdict -ne "pass" -or
    $ToolbarGate.operator_visual_verdict.reported_by -ne "user") {
    throw "M10 toolbar visual acceptance requires an explicit user pass verdict."
}
Assert-IsoTimestamp ([string]$ToolbarGate.operator_visual_verdict.recorded_at_utc) `
    "M10 toolbar user verdict"

$SettingsGate = Require-Property $Evidence "settings_gate" "M10 evidence"
if ($SettingsGate.verdict -ne "pass" -or @($SettingsGate.exercised_dpi).Count -eq 0) {
    throw "M10 settings gate must pass and record at least one exercised installed DPI."
}
foreach ($Dpi in @($SettingsGate.exercised_dpi)) {
    if ([int]$Dpi -lt 96 -or [int]$Dpi -gt 768) {
        throw "M10 settings exercised_dpi contains an implausible value: $Dpi"
    }
}
foreach ($SizeName in @("initial_client_size", "minimum_client_size", "larger_client_size")) {
    $Size = Require-Property $SettingsGate $SizeName "M10 settings evidence"
    if ([int]$Size.width -le 0 -or [int]$Size.height -le 0) {
        throw "M10 settings $SizeName must record positive dimensions."
    }
}
if ([int]$SettingsGate.larger_client_size.width -le [int]$SettingsGate.minimum_client_size.width -or
    [int]$SettingsGate.larger_client_size.height -le [int]$SettingsGate.minimum_client_size.height) {
    throw "M10 settings larger client size must exceed the minimum in both dimensions."
}
foreach ($BooleanField in @(
        "initial_viewport_usable",
        "horizontal_scroll_reaches_canvas_end",
        "vertical_scroll_reaches_canvas_end",
        "every_existing_control_reachable",
        "no_overlap_or_clipping",
        "typography_legible_and_crisp",
        "cantonese_only",
        "display_labels_do_not_leak_to_protocol_values",
        "native_effect_or_flat_fallback_usable",
        "close_reopen_stable_no_orphan",
        "focus_never_stolen"
    )) {
    if (-not [bool](Require-Property $SettingsGate $BooleanField "M10 settings evidence")) {
        throw "M10 settings evidence requires true: $BooleanField"
    }
}
if ($SettingsGate.themes.light -ne "pass" -or $SettingsGate.themes.dark -ne "pass") {
    throw "M10 settings evidence must pass both Windows light and dark themes."
}
if ($SettingsGate.operator_visual_verdict.verdict -ne "pass" -or
    $SettingsGate.operator_visual_verdict.reported_by -ne "user") {
    throw "M10 settings visual acceptance requires an explicit user pass verdict."
}
Assert-IsoTimestamp ([string]$SettingsGate.operator_visual_verdict.recorded_at_utc) `
    "M10 settings user verdict"
$GeometryPaths = @($SettingsGate.geometry_evidence)
if ($GeometryPaths.Count -lt 5) {
    throw "M10 completed settings evidence requires initial, minimum, minimum-scrolled, larger, and reopened geometry captures."
}
$ObservedGeometryPhases = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$ObservedGeometryThemes = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$ObservedSettingsOperatorPasses = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($GeometryPath in $GeometryPaths) {
    $ResolvedGeometry = Resolve-EvidencePath ([string]$GeometryPath) "M10 settings geometry"
    $Geometry = Get-Content -Raw -LiteralPath $ResolvedGeometry | ConvertFrom-Json
    if ($Geometry.evidence_kind -ne "m10_settings_geometry" -or
        [int]$Geometry.window_count -lt 1) {
        throw "M10 settings geometry is not a populated settings-window capture: $GeometryPath"
    }
    [void]$ObservedGeometryPhases.Add([string]$Geometry.phase)
    [void]$ObservedGeometryThemes.Add([string]$Geometry.theme_reported_by_operator)
    foreach ($OperatorField in @(
            "initial_viewport_usable",
            "all_controls_reachable",
            "no_overlap_or_clipping",
            "typography_legible_and_crisp",
            "cantonese_only",
            "native_effect_or_flat_fallback_usable",
            "no_focus_theft",
            "close_reopen_stable_no_orphan"
        )) {
        $OperatorValue = [string](Require-Property `
                $Geometry.operator_report `
                $OperatorField `
                "M10 settings geometry operator report")
        if ($OperatorValue -eq "fail") {
            throw "M10 settings geometry contains an operator failure for $OperatorField`: $GeometryPath"
        }
        if ($OperatorValue -eq "pass") {
            [void]$ObservedSettingsOperatorPasses.Add($OperatorField)
        }
    }
}
foreach ($RequiredPhase in @("initial", "minimum", "minimum_scrolled", "larger", "reopened")) {
    if (-not $ObservedGeometryPhases.Contains($RequiredPhase)) {
        throw "M10 settings geometry is missing phase: $RequiredPhase"
    }
}
foreach ($RequiredTheme in @("light", "dark")) {
    if (-not $ObservedGeometryThemes.Contains($RequiredTheme)) {
        throw "M10 settings geometry is missing an operator-reported $RequiredTheme theme capture."
    }
}
foreach ($RequiredOperatorPass in @(
        "initial_viewport_usable",
        "all_controls_reachable",
        "no_overlap_or_clipping",
        "typography_legible_and_crisp",
        "cantonese_only",
        "native_effect_or_flat_fallback_usable",
        "no_focus_theft",
        "close_reopen_stable_no_orphan"
    )) {
    if (-not $ObservedSettingsOperatorPasses.Contains($RequiredOperatorPass)) {
        throw "M10 settings geometry never records an explicit operator pass for: $RequiredOperatorPass"
    }
}

foreach ($LegacyPath in @(
        "docs/evidence/m11/summary.md",
        "docs/evidence/m11c/summary.md",
        "docs/evidence/m11d/summary.md"
    )) {
    if (@($Evidence.legacy_evidence) -notcontains $LegacyPath) {
        throw "M10 evidence must preserve a legacy provenance link: $LegacyPath"
    }
    [void](Resolve-EvidencePath $LegacyPath "M10 legacy evidence")
}
if (-not [bool]$Evidence.machine_state_evidence_committed_separately) {
    throw "M10 completion must record that machine-state evidence was committed separately."
}

$SummaryMarkdown = Get-Content -Raw -LiteralPath $SummaryMarkdownPath
foreach ($Required in @("M10", "complete", "toolbar", "settings", "SHA-256")) {
    Require-Text $SummaryMarkdown ([regex]::Escape($Required)) `
        "M10 summary.md is missing closeout term: $Required"
}

Write-Host "M10 evidence summary contract passed for complete current-hash installed evidence."
