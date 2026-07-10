param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [switch]$CorruptRecomputedMetric,

    [switch]$CorruptVerifierTooling,

    [switch]$CorruptBootBoundary,

    [switch]$CorruptTargetedCoverage
)

$ErrorActionPreference = "Stop"

$SourceRepoRoot = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) {
    throw "synthetic completed-evidence fixture root already exists: $OutputRoot"
}

$Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Write-Utf8Text([string]$Path, [string]$Content) {
    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    [IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Write-Json([string]$Path, [object]$Value) {
    Write-Utf8Text $Path (($Value | ConvertTo-Json -Depth 100) + "`n")
}

function Copy-RepoFile([string]$RelativePath) {
    $Source = Join-Path $SourceRepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "missing synthetic-fixture source file: $RelativePath"
    }
    $Destination = Join-Path $OutputRoot $RelativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) |
        Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination
}

foreach ($RelativePath in @(
        "tools/test-m10-evidence-summary-contract.ps1",
        "tools/dev/new-m10-completed-evidence-fixture.ps1",
        "tools/dev/capture-m10-toolbar-session.ps1",
        "tools/dev/finalize-m10-toolbar-session.ps1",
        "tools/dev/capture-m10-settings-geometry.ps1",
        "tools/dev/capture-m10-non-elevated-preflight.ps1",
        "tools/dev/capture-language-bar-topology.ps1",
        "tools/dev/verify-m10-frozen-candidate.ps1",
        "src/tools/yune_windows_settings.cpp",
        "docs/evidence/m10/README.md",
        "docs/evidence/m10/summary.template.json"
    )) {
    Copy-RepoFile $RelativePath
}

$EvidenceRoot = Join-Path $OutputRoot "docs/evidence/m10"
$Commit = "a" * 40
$BaselineCommit = "b" * 40
$ArtifactHash = "A" * 64
$DeploymentAt = [DateTimeOffset]::Parse("2026-07-10T00:00:00Z")
$VerifierAt = $DeploymentAt.AddHours(1)
$UserVerdictAt = $VerifierAt.AddHours(6)

$RecordedPreflightChecks = @(
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
    "tools/test-m11d-activation-trace-contract.ps1",
    "tools/test-m11d-reliability-smoke.ps1",
    "tools/test-m11d-multiprocess-reliability-smoke.ps1",
    "tools/test-tsf-ime-state-hotkey-contract.ps1",
    "tools/test-candidate-window-smoke.ps1",
    "tools/test-m10-evidence-summary-contract.ps1",
    "tools/test-m10-frozen-candidate-deploy-contract.ps1"
)
$PreflightStartedAt = $DeploymentAt.AddHours(-3)
$PreflightCompletedAt = $PreflightStartedAt.AddHours(1)
$PassingChecks = [Collections.Generic.List[object]]::new()
for ($CheckIndex = 0; $CheckIndex -lt $RecordedPreflightChecks.Count; $CheckIndex += 1) {
    $CheckStartedAt = $PreflightStartedAt.AddMinutes($CheckIndex * 2)
    $CheckCompletedAt = $CheckStartedAt.AddMinutes(1)
    $PassingChecks.Add([pscustomobject][ordered]@{
        command = $RecordedPreflightChecks[$CheckIndex]
        started_at = $CheckStartedAt.ToString("o")
        completed_at = $CheckCompletedAt.ToString("o")
        duration_ms = 60000
        exit_code = 0
        passed = $true
        last_output_line = "synthetic fixture pass"
    })
}

$Preflight = [pscustomobject][ordered]@{
    schema_version = 2
    milestone = "M10"
    evidence_kind = "non_elevated_preflight"
    captured_at = $PreflightCompletedAt.ToString("o")
    started_at = $PreflightStartedAt.ToString("o")
    completed_at = $PreflightCompletedAt.ToString("o")
    duration_ms = 3600000
    implementation_commit = $Commit
    checked_tree_commit = $Commit
    checked_tree_clean_before = $true
    checked_tree_clean_after = $true
    deployment_source_commit = $Commit
    commit_role_order_verified = $true
    candidate_equivalence = [pscustomobject][ordered]@{
        from_deployment_source_commit = $Commit
        to_checked_tree_commit = $Commit
        checked_pathspec = @(
            "src/**",
            "skins/**",
            "tools/build-tsf-shell.ps1")
        changed_paths = @()
        product_build_inputs_unchanged = $true
    }
    verdict = "pass"
    settings_dpi_percent_matrix = @(100, 125, 150, 200)
    settings_minimum_larger_scroll_each_dpi = $true
    checks = @($PassingChecks)
    stress_results = [pscustomobject][ordered]@{
        language_bar_repeated_drags = 50
        intermediate_moves_per_drag = 100
        movement_renders = 0
        final_renders_per_completed_drag = 1
        paced_server_cas_actions = 100
        paced_server_revision_advances = 100
        timeout_after_commit_reconciled_once = $true
        persistence_failure_atomic_and_recovered_once = $true
    }
    review = [pscustomobject][ordered]@{
        scope = "automated_non_elevated_checks_only"
        manual_review_findings_claimed = $false
        current_candidate_post_restart_machine_verified = $false
        completed_summary_exists = $false
    }
    m11_boundary = [pscustomobject][ordered]@{
        m11_acceptance_claimed = $false
    }
}
Write-Utf8Text `
    (Join-Path $EvidenceRoot "product-build-input.diff") `
    "Synthetic fixture: no product build input changes.`n"

$ManifestArtifacts = @(
    @("tsf", "server", "settings", "default_skin") | ForEach-Object {
        [pscustomobject][ordered]@{ name = $_; sha256 = $ArtifactHash }
    })
$CandidateManifest = [pscustomobject][ordered]@{
    schema_version = 1
    operation = "m10_frozen_candidate"
    mode = "Deploy"
    status = "deployed_restart_required"
    source = [pscustomobject][ordered]@{
        clean = $true
        post_build_verified = $true
        actual_commit = $Commit
        expected_commit = $Commit
    }
    package = [pscustomobject][ordered]@{ post_build_verified = $true }
    build = [pscustomobject][ordered]@{
        invocation_count = 1
        artifacts = $ManifestArtifacts
    }
    deployment = [pscustomobject][ordered]@{
        performed = $true
        session_restart_required = $true
        live_test_allowed_without_restart = $false
        completed_at = $DeploymentAt.ToString("o")
    }
}
$ManifestRelativePath = "docs/evidence/m10/machine-state/frozen-candidate.json"
$ManifestPath = Join-Path $OutputRoot $ManifestRelativePath
Write-Json $ManifestPath $CandidateManifest
$ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
$Preflight | Add-Member -NotePropertyName candidate_manifest_path `
    -NotePropertyValue $ManifestRelativePath
$Preflight | Add-Member -NotePropertyName candidate_manifest_sha256 `
    -NotePropertyValue $ManifestHash
Write-Json (Join-Path $EvidenceRoot "non-elevated-preflight.json") $Preflight

$VerifiedArtifacts = @(
    @("tsf", "server", "settings", "default_skin") | ForEach-Object {
        [pscustomobject][ordered]@{
            name = $_
            actual_sha256 = $ArtifactHash
            matches_candidate = $true
        }
    })
$VerifierScriptRelativePath = "tools/dev/verify-m10-frozen-candidate.ps1"
$VerifierScriptPath = Join-Path $OutputRoot $VerifierScriptRelativePath
$VerifierScriptHash = (Get-FileHash `
        -LiteralPath $VerifierScriptPath `
        -Algorithm SHA256).Hash
$TargetedUnresolved = @()
if ($CorruptTargetedCoverage) {
    $TargetedUnresolved = @(
        [pscustomobject]@{ process_id = 999; category = "synthetic" })
}
$PostRestartVerification = [pscustomobject][ordered]@{
    schema_version = 1
    operation = "m10_frozen_candidate_post_restart_verify"
    captured_at = $VerifierAt.ToString("o")
    pass = $true
    failures = @()
    tooling = [pscustomobject][ordered]@{
        verifier_script_path = $VerifierScriptPath
        verifier_repo_relative_path = $VerifierScriptRelativePath
        verifier_script_sha256 = $(if ($CorruptVerifierTooling) {
                $ArtifactHash
            }
            else {
                $VerifierScriptHash
            })
        repository_root = $OutputRoot
        repository_detected = $true
        tooling_source_commit = $(if ($CorruptVerifierTooling) { "unknown" } else { $Commit })
        tooling_source_commit_known = -not $CorruptVerifierTooling
        verifier_matches_tooling_commit = -not $CorruptVerifierTooling
        working_tree_clean = -not $CorruptVerifierTooling
        git_query_error = ""
    }
    restart_boundary = [pscustomobject][ordered]@{
        query_method = "Win32_OperatingSystem.LastBootUpTime"
        query_succeeded = $true
        query_error = ""
        last_boot_up_time = $(if ($CorruptBootBoundary) {
                $DeploymentAt.ToString("o")
            }
            else {
                $DeploymentAt.AddMinutes(30).ToString("o")
            })
        boot_time_known = $true
        booted_strictly_after_deployment = $true
        proof_complete = $true
    }
    candidate = [pscustomobject][ordered]@{
        manifest_sha256 = $ManifestHash
        source_actual_commit = $Commit
        source_clean = $true
        source_post_build_verified = $true
        package_post_build_verified = $true
        deployment_completed_at_valid = $true
        deployment_completed_at = $DeploymentAt.ToString("o")
    }
    holders = [pscustomobject][ordered]@{
        count = 1
        coverage_complete = -not $CorruptTargetedCoverage
        coverage = [pscustomobject][ordered]@{
            targeted_scan = [pscustomobject][ordered]@{
                method = "targeted_tasklist_module_filter"
                query_succeeded = -not $CorruptTargetedCoverage
                query_error = $(if ($CorruptTargetedCoverage) {
                        "synthetic targeted scan failure"
                    }
                    else {
                        ""
                    })
                process_count = 0
                processes = @()
                informational_output = @()
            }
            targeted_coverage_complete = $true
            targeted_unresolved_count = $(if ($CorruptTargetedCoverage) { 1 } else { 0 })
            targeted_unresolved = $TargetedUnresolved
        }
        all_match_candidate_image_size = $true
        all_use_current_installed_path = $true
        all_start_times_known = $true
        all_started_strictly_after_deployment = $true
        old_or_aside_install_root_path_count = 0
    }
    installed_processes = [pscustomobject][ordered]@{
        server = [pscustomobject][ordered]@{
            current_installed_path_count = 1
            exactly_one_running_installed_server = $true
            no_old_or_aside_processes = $true
            unknown_path_count = 0
            all_installed_start_times_known = $true
            all_installed_started_strictly_after_deployment = $true
        }
        settings = [pscustomobject][ordered]@{
            no_old_or_aside_processes = $true
            unknown_path_count = 0
            all_installed_start_times_known = $true
            all_installed_started_strictly_after_deployment = $true
        }
    }
    installed = [pscustomobject][ordered]@{
        artifacts = $VerifiedArtifacts
        pending_delete = [pscustomobject][ordered]@{ install_root_entry_count = 0 }
        profile = [pscustomobject][ordered]@{ registered = $true; active = $true }
        com_registration = [pscustomobject][ordered]@{ path_matches = $true }
    }
}
$VerifierRelativePath = "docs/evidence/m10/machine-state/post-restart-verification.json"
$VerifierPath = Join-Path $OutputRoot $VerifierRelativePath
Write-Json $VerifierPath $PostRestartVerification
$VerifierHash = (Get-FileHash -LiteralPath $VerifierPath -Algorithm SHA256).Hash

$ToolbarHosts = [Collections.Generic.List[object]]::new()
$HostDefinitions = @(
    [pscustomobject]@{ id = "notepad"; name = "Notepad"; process = "notepad" },
    [pscustomobject]@{ id = "chromium"; name = "Chromium"; process = "chrome" },
    [pscustomobject]@{ id = "explorer"; name = "Explorer"; process = "explorer" },
    [pscustomobject]@{ id = "electron"; name = "Visual Studio Code"; process = "Code" }
)
for ($HostIndex = 0; $HostIndex -lt $HostDefinitions.Count; $HostIndex += 1) {
    $HostDefinition = $HostDefinitions[$HostIndex]
    $WindowHandle = "0x{0:X4}" -f (0x1200 + $HostIndex)
    $CaptureBase = $VerifierAt.AddHours(1).AddMinutes($HostIndex * 10)
    $WatcherStart = $CaptureBase
    $CaptureStart = $CaptureBase.AddMinutes(1)
    $FirstSampleAt = $CaptureBase.AddMinutes(2)
    $SecondSampleAt = $CaptureBase.AddMinutes(3)
    $CaptureComplete = $CaptureBase.AddMinutes(4)
    $WatcherStop = $CaptureBase.AddMinutes(5)
    $SentinelCheck = $CaptureBase.AddMinutes(6)
    $ReceiptAt = $CaptureBase.AddMinutes(7)
    $FinalizedAt = $CaptureBase.AddMinutes(8)

    $WindowCaptured = [pscustomobject][ordered]@{
        visible = $true
        hwnd_hex = $WindowHandle
        process_name = $HostDefinition.process
        foreground = [pscustomobject][ordered]@{
            root_owner_matches_foreground_root_owner = $true
        }
        capture = [pscustomobject][ordered]@{ is_this_window = $true }
    }
    $WindowReleased = [pscustomobject][ordered]@{
        visible = $true
        hwnd_hex = $WindowHandle
        process_name = $HostDefinition.process
        foreground = [pscustomobject][ordered]@{
            root_owner_matches_foreground_root_owner = $true
        }
        capture = [pscustomobject][ordered]@{ is_this_window = $false }
    }
    $ProjectedMetrics = [pscustomobject][ordered]@{
        samples_with_visible_toolbar = $(if ($CorruptRecomputedMetric) { 99 } else { 2 })
        samples_with_toolbar_capture = 1
        maximum_visible_toolbar_windows = 1
        samples_with_multiple_visible_toolbars = 0
        samples_with_foreground_owner_mismatch = 0
        samples_with_unexpected_host_process = 0
        observed_visible_process_names = @($HostDefinition.process)
        distinct_visible_hwnds = @($WindowHandle)
        sampled_visible_hwnd_stable = $true
        final_sample_visible_toolbar_count = 1
        final_sample_visible_hwnds = @($WindowHandle)
        final_sample_has_toolbar_capture = $false
        final_sample_owner_matches_foreground_root = $true
        settings_process_ids_started_during_capture = @()
        topology_ready = $true
    }
    $Sentinel = [pscustomobject][ordered]@{
        name = "Local\YuneWindowsSettingsLaunchObserved.v1"
        capture_mutex_name = "Local\YuneWindowsM10ToolbarCapture.v1"
        capture_mutex_held = $true
        created_new = $true
        initialized_unsignaled_before_initial_process_snapshot = $true
        held_for_complete_capture = $true
        initialized_at_utc = $WatcherStart.ToString("o")
        checked_at_utc = $SentinelCheck.ToString("o")
        signaled = $false
        coverage_complete = $true
        failure = ""
    }
    $MachineObserved = [pscustomobject][ordered]@{}
    foreach ($Property in $ProjectedMetrics.PSObject.Properties) {
        $MachineObserved | Add-Member -NotePropertyName $Property.Name `
            -NotePropertyValue $Property.Value
    }
    $MachineObserved | Add-Member -NotePropertyName settings_launch_sentinel `
        -NotePropertyValue $Sentinel
    $MachineObserved | Add-Member -NotePropertyName settings_process_start_watcher `
        -NotePropertyValue ([pscustomobject][ordered]@{
            provider = "Win32_ProcessStartTrace"
            started_at_utc = $WatcherStart.ToString("o")
            stopped_at_utc = $WatcherStop.ToString("o")
            coverage_complete = $true
            failure = ""
            events = @()
        })

    $Capture = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_kind = "m10_toolbar_topology_capture"
        captured_at_utc = $CaptureStart.ToString("o")
        completed_at_utc = $CaptureComplete.ToString("o")
        host = [pscustomobject][ordered]@{
            id = $HostDefinition.id
            expected_process_name = $HostDefinition.process
        }
        sampling = [pscustomobject][ordered]@{
            requested_sample_count = 2
            captured_sample_count = 2
        }
        machine_observed = $MachineObserved
        operator_report = [pscustomobject][ordered]@{ verdict = "pending" }
        gate_ready = $false
        samples = @(
            [pscustomobject][ordered]@{
                sample_index = 0
                captured_at_utc = $FirstSampleAt.ToString("o")
                window_count = 1
                windows = @($WindowCaptured)
            },
            [pscustomobject][ordered]@{
                sample_index = 1
                captured_at_utc = $SecondSampleAt.ToString("o")
                window_count = 1
                windows = @($WindowReleased)
            }
        )
    }
    $SessionDirectoryRelative = "docs/evidence/m10/toolbar/$($HostDefinition.id)"
    $SessionDirectory = Join-Path $OutputRoot $SessionDirectoryRelative
    $CaptureName = "capture.json"
    $CapturePath = Join-Path $SessionDirectory $CaptureName
    Write-Json $CapturePath $Capture
    $CaptureHash = (Get-FileHash -LiteralPath $CapturePath -Algorithm SHA256).Hash

    $ReceiptName = "capture.json.receipt.json"
    $ReceiptPath = Join-Path $SessionDirectory $ReceiptName
    $Receipt = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_kind = "m10_toolbar_capture_receipt"
        created_at_utc = $ReceiptAt.ToString("o")
        capture_file_name = $CaptureName
        capture_sha256 = $CaptureHash
        capture_completed_at_utc = $CaptureComplete.ToString("o")
        settings_launch_sentinel_coverage_complete = $true
        settings_launch_sentinel_signaled = $false
    }
    Write-Json $ReceiptPath $Receipt
    $ReceiptHash = (Get-FileHash -LiteralPath $ReceiptPath -Algorithm SHA256).Hash

    $FinalSession = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_kind = "m10_toolbar_session_final"
        finalized_at_utc = $FinalizedAt.ToString("o")
        host = [pscustomobject][ordered]@{ id = $HostDefinition.id }
        source_capture = [pscustomobject][ordered]@{
            file_name = $CaptureName
            sha256 = $CaptureHash
            receipt_file_name = $ReceiptName
            receipt_sha256 = $ReceiptHash
            captured_at_utc = $CaptureStart.ToString("o")
            completed_at_utc = $CaptureComplete.ToString("o")
        }
        machine_observed = $MachineObserved
        operator_report = [pscustomobject][ordered]@{
            grip_drags_completed = 10
            settings_segment_drags_completed = 10
            total_drags_completed = 20
            report_complete = $true
        }
        gate_ready = $true
    }
    $FinalRelativePath = "$SessionDirectoryRelative/final.json"
    Write-Json (Join-Path $OutputRoot $FinalRelativePath) $FinalSession

    $ToolbarHosts.Add([pscustomobject][ordered]@{
        id = $HostDefinition.id
        host_name = $HostDefinition.name
        grip_drags = 10
        settings_segment_drags = 10
        total_drags = 20
        session_evidence = @($FinalRelativePath)
        maximum_visible_toolbar_windows = 1
        all_visible_owners_match_foreground_root = $true
        sampled_visible_hwnd_stable = $true
        no_stuck_capture = $true
        settings_process_launched_by_drag = $false
        settings_segment_drag_did_not_activate = $true
        focus_never_stolen = $true
        visual_copies_or_afterimages_absent = "pass"
        position_persisted_after_focus_movement = $true
        position_persisted_after_host_restart = $true
    })
}

$GeometryPaths = [Collections.Generic.List[string]]::new()
$GeometryDefinitions = @(
    [pscustomobject]@{ phase = "initial"; width = 800; height = 600; theme = "light" },
    [pscustomobject]@{ phase = "minimum"; width = 500; height = 400; theme = "dark" },
    [pscustomobject]@{ phase = "minimum_scrolled"; width = 500; height = 400; theme = "light" },
    [pscustomobject]@{ phase = "larger"; width = 1000; height = 800; theme = "dark" },
    [pscustomobject]@{ phase = "reopened"; width = 800; height = 600; theme = "light" }
)
for ($GeometryIndex = 0; $GeometryIndex -lt $GeometryDefinitions.Count; $GeometryIndex += 1) {
    $Definition = $GeometryDefinitions[$GeometryIndex]
    $AtEnd = $Definition.phase -eq "minimum_scrolled"
    $ScrollAxis = if ($AtEnd) {
        [pscustomobject][ordered]@{
            available = $true
            can_scroll = $true
            minimum = 0
            maximum = 999
            page = 500
            position = 500
            maximum_position = 500
            at_end = $true
        }
    }
    else {
        [pscustomobject][ordered]@{
            available = $false
            can_scroll = $false
            minimum = 0
            maximum = 0
            page = 0
            position = 0
            maximum_position = 0
            at_end = $false
        }
    }
    $Geometry = [pscustomobject][ordered]@{
        schema_version = 1
        evidence_kind = "m10_settings_geometry"
        captured_at_utc = $VerifierAt.AddHours(5).AddMinutes($GeometryIndex).ToString("o")
        phase = $Definition.phase
        theme_reported_by_operator = $Definition.theme
        window_count = 1
        windows = @(
            [pscustomobject][ordered]@{
                visible = $true
                process_name = "YuneWindowsSettings"
                dpi = 96
                client_rect = [pscustomobject][ordered]@{
                    available = $true
                    width = $Definition.width
                    height = $Definition.height
                }
                scroll = [pscustomobject][ordered]@{
                    horizontal = $ScrollAxis
                    vertical = $ScrollAxis
                }
            })
        operator_report = [pscustomobject][ordered]@{
            initial_viewport_usable = "pass"
            all_controls_reachable = "pass"
            no_overlap_or_clipping = "pass"
            typography_legible_and_crisp = "pass"
            cantonese_only = "pass"
            native_effect_or_flat_fallback_usable = "pass"
            no_focus_theft = "pass"
            close_reopen_stable_no_orphan = "pass"
        }
    }
    $RelativePath = "docs/evidence/m10/settings/$($Definition.phase).json"
    Write-Json (Join-Path $OutputRoot $RelativePath) $Geometry
    $GeometryPaths.Add($RelativePath)
}

foreach ($LegacyMilestone in @("m11", "m11c", "m11d")) {
    Write-Utf8Text `
        (Join-Path $OutputRoot "docs/evidence/$LegacyMilestone/summary.md") `
        "# Synthetic legacy evidence`n"
}

$Summary = [pscustomobject][ordered]@{
    schema_version = 1
    milestone = "M10"
    title = "Native UI Presentation Closeout"
    status = "complete"
    evidence = "docs/evidence/m10/summary.md"
    source = [pscustomobject][ordered]@{
        source_commit = $Commit
        implementation_commit = $Commit
        pre_rebaseline_baseline = $BaselineCommit
        product_build_input_diff_recorded = $true
        product_build_input_diff_path = "docs/evidence/m10/product-build-input.diff"
    }
    non_elevated = [pscustomobject][ordered]@{
        verdict = "pass"
        settings_dpi_percent_matrix = @(100, 125, 150, 200)
        settings_minimum_larger_scroll_each_dpi = $true
        checks = @($PassingChecks)
    }
    artifacts = [pscustomobject][ordered]@{
        tsf = [pscustomobject]@{ built_sha256 = $ArtifactHash; installed_sha256 = $ArtifactHash }
        server = [pscustomobject]@{ built_sha256 = $ArtifactHash; installed_sha256 = $ArtifactHash }
        settings = [pscustomobject]@{ built_sha256 = $ArtifactHash; installed_sha256 = $ArtifactHash }
        default_skin = [pscustomobject]@{ built_sha256 = $ArtifactHash; installed_sha256 = $ArtifactHash }
        all_built_and_installed_hashes_match = $true
        all_loaded_tsf_holders_match = $true
        holder_evidence_path = $VerifierRelativePath
        candidate_manifest_path = $ManifestRelativePath
        candidate_manifest_sha256 = $ManifestHash
        post_restart_verification_path = $VerifierRelativePath
        post_restart_verification_sha256 = $VerifierHash
    }
    toolbar_gate = [pscustomobject][ordered]@{
        verdict = "pass"
        hosts = @($ToolbarHosts)
        total_drags = 80
        ascii_active_cantonese_state_exercised = $true
        octagram_schema_cantonese_state_exercised = $true
        backdrop_or_flat_fallback_usable = "pass"
        operator_visual_verdict = [pscustomobject][ordered]@{
            verdict = "pass"
            reported_by = "user"
            recorded_at_utc = $UserVerdictAt.ToString("o")
        }
    }
    settings_gate = [pscustomobject][ordered]@{
        verdict = "pass"
        exercised_dpi = @(96)
        geometry_evidence = @($GeometryPaths)
        initial_client_size = [pscustomobject]@{ width = 800; height = 600 }
        minimum_client_size = [pscustomobject]@{ width = 500; height = 400 }
        larger_client_size = [pscustomobject]@{ width = 1000; height = 800 }
        initial_viewport_usable = $true
        horizontal_scroll_reaches_canvas_end = $true
        vertical_scroll_reaches_canvas_end = $true
        every_existing_control_reachable = $true
        no_overlap_or_clipping = $true
        typography_legible_and_crisp = $true
        cantonese_only = $true
        display_labels_do_not_leak_to_protocol_values = $true
        native_effect_or_flat_fallback_usable = $true
        close_reopen_stable_no_orphan = $true
        focus_never_stolen = $true
        themes = [pscustomobject]@{ light = "pass"; dark = "pass" }
        operator_visual_verdict = [pscustomobject][ordered]@{
            verdict = "pass"
            reported_by = "user"
            recorded_at_utc = $UserVerdictAt.ToString("o")
        }
    }
    legacy_evidence = @(
        "docs/evidence/m11/summary.md",
        "docs/evidence/m11c/summary.md",
        "docs/evidence/m11d/summary.md"
    )
    machine_state_evidence_committed_separately = $true
}
Write-Json (Join-Path $EvidenceRoot "summary.json") $Summary
Write-Utf8Text `
    (Join-Path $EvidenceRoot "summary.md") `
    "# M10 complete`n`nToolbar and settings evidence is complete and SHA-256 bound.`n"

Write-Output (Join-Path $OutputRoot "tools/test-m10-evidence-summary-contract.ps1")
