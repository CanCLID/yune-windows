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
$PreflightCapture = Join-Path $RepoRoot "tools\dev\capture-m10-non-elevated-preflight.ps1"
$CompletedFixtureBuilder = Join-Path $RepoRoot "tools\dev\new-m10-completed-evidence-fixture.ps1"
$FrozenCandidateVerifier = Join-Path $RepoRoot "tools\dev\verify-m10-frozen-candidate.ps1"
$SettingsProductSourcePath = Join-Path $RepoRoot "src\tools\yune_windows_settings.cpp"

foreach ($Path in @(
        $ReadmePath,
        $TemplatePath,
        $PreflightPath,
        $ToolbarCapture,
        $ToolbarFinalize,
        $SettingsCapture,
        $PreflightCapture,
        $CompletedFixtureBuilder,
        $FrozenCandidateVerifier,
        $SettingsProductSourcePath
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

function Convert-IsoTimestamp([string]$Value, [string]$Context) {
    $Parsed = [DateTimeOffset]::MinValue
    if ([string]::IsNullOrWhiteSpace($Value) -or
        -not [DateTimeOffset]::TryParse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$Parsed)) {
        throw "$Context must be an ISO-8601 round-trip timestamp."
    }
    return $Parsed
}

function Assert-IsoTimestamp([string]$Value, [string]$Context) {
    [void](Convert-IsoTimestamp $Value $Context)
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

function Assert-M10PreflightV2Timing(
    [object]$Preflight,
    [string[]]$ExpectedCommands) {
    if ([int]$Preflight.schema_version -ne 2) {
        throw "completed M10 evidence requires schema_version 2 timed preflight evidence."
    }
    $StartedAt = Convert-IsoTimestamp `
        ([string]$Preflight.started_at) "M10 preflight start"
    $CompletedAt = Convert-IsoTimestamp `
        ([string]$Preflight.completed_at) "M10 preflight completion"
    $CapturedAt = Convert-IsoTimestamp `
        ([string]$Preflight.captured_at) "M10 preflight capture"
    if ($CompletedAt -lt $StartedAt -or $CapturedAt -ne $CompletedAt) {
        throw "M10 preflight capture/completion timing is inconsistent."
    }
    $MeasuredDurationMs = ($CompletedAt - $StartedAt).TotalMilliseconds
    if ([Math]::Abs(
            [double]$Preflight.duration_ms - $MeasuredDurationMs) -gt 1.0) {
        throw "M10 preflight total duration is inconsistent with its timestamps."
    }

    $Checks = @($Preflight.checks)
    if ($Checks.Count -ne $ExpectedCommands.Count) {
        throw "M10 preflight must record exactly $($ExpectedCommands.Count) measured checks."
    }
    $PreviousCompletedAt = $StartedAt
    for ($Index = 0; $Index -lt $ExpectedCommands.Count; $Index += 1) {
        $Check = $Checks[$Index]
        if ([string]$Check.command -ne $ExpectedCommands[$Index]) {
            throw "M10 preflight check order mismatch at index ${Index}: $($Check.command)"
        }
        $CheckStartedAt = Convert-IsoTimestamp `
            ([string]$Check.started_at) "M10 preflight check $Index start"
        $CheckCompletedAt = Convert-IsoTimestamp `
            ([string]$Check.completed_at) "M10 preflight check $Index completion"
        if ($CheckStartedAt -lt $StartedAt -or
            $CheckStartedAt -lt $PreviousCompletedAt -or
            $CheckCompletedAt -lt $CheckStartedAt -or
            $CheckCompletedAt -gt $CompletedAt -or
            -not [bool]$Check.passed -or
            [int]$Check.exit_code -ne 0) {
            throw "M10 preflight check $Index has invalid timing or result."
        }
        $MeasuredCheckDurationMs =
            ($CheckCompletedAt - $CheckStartedAt).TotalMilliseconds
        if ([Math]::Abs(
                [double]$Check.duration_ms - $MeasuredCheckDurationMs) -gt 1.0) {
            throw "M10 preflight check $Index duration is inconsistent with its timestamps."
        }
        $PreviousCompletedAt = $CheckCompletedAt
    }
}

function Get-RecomputedToolbarCaptureMetrics(
    [object]$Capture,
    [DateTimeOffset]$EvidenceBoundary,
    [string]$Context) {
    if ([int]$Capture.schema_version -ne 1 -or
        $Capture.evidence_kind -ne "m10_toolbar_topology_capture" -or
        $Capture.operator_report.verdict -ne "pending" -or
        [bool]$Capture.gate_ready) {
        throw "$Context is not an original pending topology capture."
    }
    $CaptureStartedAt = Convert-IsoTimestamp `
        ([string]$Capture.captured_at_utc) "$Context capture start"
    $CaptureCompletedAt = Convert-IsoTimestamp `
        ([string]$Capture.completed_at_utc) "$Context capture completion"
    if ($CaptureStartedAt -le $EvidenceBoundary -or
        $CaptureCompletedAt -lt $CaptureStartedAt) {
        throw "$Context was not captured strictly after the verified deployment boundary."
    }

    $Samples = @($Capture.samples)
    if ($Samples.Count -le 0 -or
        $Samples.Count -ne [int]$Capture.sampling.captured_sample_count -or
        $Samples.Count -ne [int]$Capture.sampling.requested_sample_count) {
        throw "$Context has an incomplete sample sequence."
    }
    $DistinctVisibleHwnds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $ObservedVisibleProcessNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $SamplesWithVisibleWindow = 0
    $SamplesWithToolbarCapture = 0
    $MaximumVisibleWindows = 0
    $SamplesWithMultipleVisibleWindows = 0
    $SamplesWithForegroundOwnerMismatch = 0
    $SamplesWithUnexpectedHostProcess = 0
    $FinalVisibleWindows = @()
    $LastSampleAt = $CaptureStartedAt
    for ($SampleIndex = 0; $SampleIndex -lt $Samples.Count; $SampleIndex += 1) {
        $Sample = $Samples[$SampleIndex]
        if ([int]$Sample.sample_index -ne $SampleIndex -or
            [int]$Sample.window_count -ne @($Sample.windows).Count) {
            throw "$Context sample sequence or window count is inconsistent at index $SampleIndex."
        }
        $SampleAt = Convert-IsoTimestamp `
            ([string]$Sample.captured_at_utc) "$Context sample $SampleIndex"
        if ($SampleAt -le $EvidenceBoundary -or
            $SampleAt -lt $CaptureStartedAt -or
            $SampleAt -lt $LastSampleAt -or
            $SampleAt -gt $CaptureCompletedAt) {
            throw "$Context sample $SampleIndex is outside its post-verification capture interval."
        }
        $LastSampleAt = $SampleAt
        $VisibleWindows = @($Sample.windows | Where-Object { [bool]$_.visible })
        $FinalVisibleWindows = $VisibleWindows
        $MaximumVisibleWindows = [Math]::Max(
            $MaximumVisibleWindows,
            $VisibleWindows.Count)
        if ($VisibleWindows.Count -gt 0) {
            $SamplesWithVisibleWindow += 1
        }
        if ($VisibleWindows.Count -gt 1) {
            $SamplesWithMultipleVisibleWindows += 1
        }
        foreach ($Window in $VisibleWindows) {
            [void]$DistinctVisibleHwnds.Add([string]$Window.hwnd_hex)
            [void]$ObservedVisibleProcessNames.Add([string]$Window.process_name)
            if (-not [string]::Equals(
                    [string]$Window.process_name,
                    [string]$Capture.host.expected_process_name,
                    [StringComparison]::OrdinalIgnoreCase)) {
                $SamplesWithUnexpectedHostProcess += 1
            }
            if (-not [bool]$Window.foreground.root_owner_matches_foreground_root_owner) {
                $SamplesWithForegroundOwnerMismatch += 1
            }
            if ([bool]$Window.capture.is_this_window) {
                $SamplesWithToolbarCapture += 1
            }
        }
    }

    $Sentinel = Require-Property `
        $Capture.machine_observed `
        "settings_launch_sentinel" `
        $Context
    $SentinelInitializedAt = Convert-IsoTimestamp `
        ([string]$Sentinel.initialized_at_utc) "$Context launch sentinel initialization"
    $SentinelCheckedAt = Convert-IsoTimestamp `
        ([string]$Sentinel.checked_at_utc) "$Context launch sentinel check"
    if ($Sentinel.name -ne "Local\YuneWindowsSettingsLaunchObserved.v1" -or
        $Sentinel.capture_mutex_name -ne "Local\YuneWindowsM10ToolbarCapture.v1" -or
        -not [bool]$Sentinel.capture_mutex_held -or
        -not [bool]$Sentinel.created_new -or
        -not [bool]$Sentinel.initialized_unsignaled_before_initial_process_snapshot -or
        -not [bool]$Sentinel.held_for_complete_capture -or
        -not [bool]$Sentinel.coverage_complete -or
        -not [string]::IsNullOrWhiteSpace([string]$Sentinel.failure) -or
        $SentinelInitializedAt -le $EvidenceBoundary -or
        $SentinelInitializedAt -gt $CaptureStartedAt -or
        $SentinelCheckedAt -lt $LastSampleAt -or
        $SentinelCheckedAt -lt $CaptureCompletedAt) {
        throw "$Context does not have complete race-safe settings launch sentinel coverage."
    }

    $Watcher = Require-Property `
        $Capture.machine_observed `
        "settings_process_start_watcher" `
        $Context
    $WatcherStartedAt = $null
    $WatcherStoppedAt = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Watcher.provider)) {
        if (@("Win32_ProcessStartTrace", "continuous_process_poll") -notcontains
            [string]$Watcher.provider) {
            throw "$Context uses an unknown auxiliary process-start provider."
        }
        $WatcherStartedAt = Convert-IsoTimestamp `
            ([string]$Watcher.started_at_utc) "$Context process watcher start"
        $WatcherStoppedAt = Convert-IsoTimestamp `
            ([string]$Watcher.stopped_at_utc) "$Context process watcher stop"
        if ($WatcherStartedAt -le $EvidenceBoundary -or
            $WatcherStartedAt -gt $CaptureStartedAt -or
            $WatcherStoppedAt -lt $CaptureCompletedAt -or
            ($Watcher.provider -eq "continuous_process_poll" -and
             [bool]$Watcher.coverage_complete) -or
            ([bool]$Watcher.coverage_complete -and
             -not [string]::IsNullOrWhiteSpace([string]$Watcher.failure))) {
            throw "$Context has inconsistent auxiliary process-start telemetry."
        }
    }
    elseif ([bool]$Watcher.coverage_complete) {
        throw "$Context claims process-start coverage without a provider."
    }
    foreach ($StartEvent in @($Watcher.events)) {
        $ObservedAt = Convert-IsoTimestamp `
            ([string]$StartEvent.observed_at_utc) "$Context process-start event"
        if ($null -eq $WatcherStartedAt -or
            $ObservedAt -lt $WatcherStartedAt -or
            $ObservedAt -gt $WatcherStoppedAt) {
            throw "$Context contains a process-start event observation outside the watcher interval."
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$StartEvent.started_at_utc)) {
            $StartedAt = Convert-IsoTimestamp `
                ([string]$StartEvent.started_at_utc) "$Context settings process start"
            if ($StartedAt -lt $WatcherStartedAt -or $StartedAt -gt $WatcherStoppedAt) {
                throw "$Context contains a settings process start outside watcher coverage."
            }
        }
    }

    $FinalHasCapture = [bool](
        @($FinalVisibleWindows | Where-Object { [bool]$_.capture.is_this_window }).Count -gt 0)
    $FinalOwnerMatchesForeground = [bool](
        $FinalVisibleWindows.Count -eq 1 -and
        [bool]$FinalVisibleWindows[0].foreground.root_owner_matches_foreground_root_owner)
    $SettingsProcessIdsStarted = @(
        $Capture.machine_observed.settings_process_ids_started_during_capture |
            ForEach-Object { [int]$_ } |
            Sort-Object -Unique)
    $TopologyReady = [bool](
        $SamplesWithVisibleWindow -gt 0 -and
        $SamplesWithToolbarCapture -gt 0 -and
        $FinalVisibleWindows.Count -eq 1 -and
        -not $FinalHasCapture -and
        $FinalOwnerMatchesForeground -and
        $MaximumVisibleWindows -le 1 -and
        $SamplesWithMultipleVisibleWindows -eq 0 -and
        $SamplesWithForegroundOwnerMismatch -eq 0 -and
        $SamplesWithUnexpectedHostProcess -eq 0 -and
        $DistinctVisibleHwnds.Count -le 1 -and
        -not [bool]$Sentinel.signaled -and
        @($Watcher.events).Count -eq 0 -and
        $SettingsProcessIdsStarted.Count -eq 0)

    return [pscustomobject][ordered]@{
        capture_started_at = $CaptureStartedAt
        capture_completed_at = $CaptureCompletedAt
        samples_with_visible_toolbar = $SamplesWithVisibleWindow
        samples_with_toolbar_capture = $SamplesWithToolbarCapture
        maximum_visible_toolbar_windows = $MaximumVisibleWindows
        samples_with_multiple_visible_toolbars = $SamplesWithMultipleVisibleWindows
        samples_with_foreground_owner_mismatch = $SamplesWithForegroundOwnerMismatch
        samples_with_unexpected_host_process = $SamplesWithUnexpectedHostProcess
        observed_visible_process_names = @($ObservedVisibleProcessNames | Sort-Object)
        distinct_visible_hwnds = @($DistinctVisibleHwnds | Sort-Object)
        sampled_visible_hwnd_stable = ($DistinctVisibleHwnds.Count -le 1)
        final_sample_visible_toolbar_count = $FinalVisibleWindows.Count
        final_sample_visible_hwnds = @(
            $FinalVisibleWindows | ForEach-Object { [string]$_.hwnd_hex })
        final_sample_has_toolbar_capture = $FinalHasCapture
        final_sample_owner_matches_foreground_root = $FinalOwnerMatchesForeground
        settings_process_ids_started_during_capture = $SettingsProcessIdsStarted
        settings_launch_sentinel_signaled = [bool]$Sentinel.signaled
        settings_launch_sentinel_coverage_complete = [bool]$Sentinel.coverage_complete
        topology_ready = $TopologyReady
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
Assert-ScriptParses $CompletedFixtureBuilder
Assert-ScriptParses $PreflightCapture
$PreflightCaptureSource = Get-Content -Raw -LiteralPath $PreflightCapture
foreach ($Required in @(
        'schema_version = 2',
        'Invoke-RecordedCheck',
        'Write-M10AtomicPreflightReport',
        '[IO.File]::Replace($TemporaryOutput, $OutputPath, $BackupOutput)',
        'started_at = Convert-ToIsoTimestamp $RunStarted',
        'completed_at = Convert-ToIsoTimestamp $RunCompleted',
        'source commit/tree changed during the M10 preflight run',
        'checked_tree_clean_before = $true',
        'checked_tree_clean_after = $true',
        'commit_role_order_verified = $true',
        '"merge-base"',
        'ProductBuildInputPathspec',
        'product_build_inputs_unchanged = $true',
        'checked tree changes frozen product build inputs',
        'candidate_manifest_sha256',
        'manual_review_findings_claimed = $false'
    )) {
    Require-Text $PreflightCaptureSource ([regex]::Escape($Required)) `
        "M10 preflight capture helper is missing measured-run marker: $Required"
}
$PreflightTokens = $null
$PreflightParseErrors = $null
$PreflightAst = [Management.Automation.Language.Parser]::ParseFile(
    $PreflightCapture,
    [ref]$PreflightTokens,
    [ref]$PreflightParseErrors)
$AtomicWriterAst = $PreflightAst.Find({
        param($Node)
        $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $Node.Name -eq 'Write-M10AtomicPreflightReport'
    }, $true)
if (@($PreflightParseErrors).Count -ne 0 -or $null -eq $AtomicWriterAst) {
    throw "M10 preflight capture helper has no parseable atomic writer."
}
Invoke-Expression $AtomicWriterAst.Extent.Text
$AtomicWriterScratch = Join-Path $env:TEMP (
    "yune-windows\m10-preflight-atomic-$PID-$([Guid]::NewGuid().ToString('N'))")
try {
    New-Item -Path $AtomicWriterScratch -ItemType Directory -Force | Out-Null
    $AtomicWriterOutput = Join-Path $AtomicWriterScratch 'preflight.json'
    Set-Content -LiteralPath $AtomicWriterOutput -Value '{"verdict":"old"}' `
        -Encoding utf8
    Write-M10AtomicPreflightReport `
        -Report ([pscustomobject]@{ verdict = 'pass' }) `
        -OutputPath $AtomicWriterOutput
    $AtomicWriterResult = Get-Content -Raw -LiteralPath $AtomicWriterOutput |
        ConvertFrom-Json
    if ($AtomicWriterResult.verdict -ne 'pass' -or
        @(Get-ChildItem -LiteralPath $AtomicWriterScratch -Force).Count -ne 1) {
        throw "M10 preflight atomic writer did not replace an existing record cleanly."
    }
}
finally {
    Remove-Item -LiteralPath $AtomicWriterScratch -Recurse -Force `
        -ErrorAction SilentlyContinue
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
        'BaselineProcessIdsJson',
        '$Baseline.Contains([int]$Process.Id)',
        'Local\YuneWindowsM10ToolbarCapture.v1',
        'Local\YuneWindowsSettingsLaunchObserved.v1',
        'settings_launch_sentinel',
        'initialized_unsignaled_before_initial_process_snapshot',
        'Win32_ProcessStartTrace',
        'continuous_process_poll',
        'settings_process_start_watcher',
        'coverage_complete',
        'settings_process_ids_started_during_capture',
        'm10_toolbar_capture_receipt',
        'settings_launch_sentinel_coverage_complete',
        'settings_launch_sentinel_signaled',
        'Capture receipt written',
        'ExpectedHostProcessName',
        'operator-verdict=pending'
    )) {
    Require-Text $ToolbarSource ([regex]::Escape($Required)) `
        "M10 toolbar recorder is missing required pattern: $Required"
}
$BaselineTransportJob = Start-Job -ScriptBlock {
    param([string]$BaselineJson, [string]$ObservedJson)
    $Baseline = [Collections.Generic.HashSet[int]]::new()
    $BaselineValues = $BaselineJson | ConvertFrom-Json
    foreach ($ProcessId in $BaselineValues) {
        [void]$Baseline.Add([int]$ProcessId)
    }
    $ObservedValues = $ObservedJson | ConvertFrom-Json
    return @($ObservedValues | Where-Object {
            -not $Baseline.Contains([int]$_)
        })
} -ArgumentList @(
    (ConvertTo-Json -Compress -InputObject @(101, 202)),
    (ConvertTo-Json -Compress -InputObject @(101, 202, 303)))
try {
    $BaselineTransportResult = @(Receive-Job `
            -Job $BaselineTransportJob `
            -Wait `
            -AutoRemoveJob)
}
finally {
    if ($null -ne (Get-Job -Id $BaselineTransportJob.Id -ErrorAction SilentlyContinue)) {
        Remove-Job -Job $BaselineTransportJob -Force -ErrorAction SilentlyContinue
    }
}
if (($BaselineTransportResult -join ',') -ne '303') {
    throw "M10 fallback poller baseline transport does not preserve every pre-existing PID."
}
if ($ToolbarSource -match 'VisualCopiesOrAfterimages|GripDragsCompleted|SettingsSegmentDragsCompleted') {
    throw "M10 topology capture must not accept operator counts or pass/fail verdicts before the actions finish."
}
$CaptureMutexIndex = $ToolbarSource.IndexOf('$CaptureMutex.WaitOne(0)')
$SentinelInitializeIndex = $ToolbarSource.IndexOf(
    '$SettingsLaunchSentinelInitializedUnsignaled = $true')
$InitialSettingsSnapshotIndex = $ToolbarSource.IndexOf(
    '$SettingsProcessesBefore = @(Get-SettingsProcessIds)')
$SamplingLoopIndex = $ToolbarSource.IndexOf('for ($SampleIndex = 0;')
$SentinelCheckIndex = $ToolbarSource.IndexOf(
    '$SettingsLaunchSentinel.WaitOne(0)',
    [Math]::Max(0, $SamplingLoopIndex))
$SentinelDisposeIndex = $ToolbarSource.IndexOf(
    '$SettingsLaunchSentinel.Dispose()',
    [Math]::Max(0, $SentinelCheckIndex))
if ($CaptureMutexIndex -lt 0 -or
    $SentinelInitializeIndex -lt $CaptureMutexIndex -or
    $InitialSettingsSnapshotIndex -lt $SentinelInitializeIndex -or
    $SamplingLoopIndex -lt $InitialSettingsSnapshotIndex -or
    $SentinelCheckIndex -lt $SamplingLoopIndex -or
    $SentinelDisposeIndex -lt $SentinelCheckIndex) {
    throw "M10 recorder must exclusively initialize, hold, sample, and then dispose the launch sentinel around the complete capture."
}
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
$CompletionBoundaryIndex = $ToolbarSource.IndexOf(
    '$CaptureCompletedAt = [DateTimeOffset]::UtcNow.ToString(',
    [Math]::Max(0, $SamplingLoopIndex))
$WatcherDrainIndex = $ToolbarSource.IndexOf(
    'if ($SettingsWatcherProvider -eq "continuous_process_poll"',
    [Math]::Max(0, $CompletionBoundaryIndex))
$FinalPidSnapshotIndex = $ToolbarSource.IndexOf(
    '$SettingsProcessesAfter = @(Get-SettingsProcessIds)',
    [Math]::Max(0, $CompletionBoundaryIndex))
$FinalSentinelCheckIndex = $ToolbarSource.IndexOf(
    '$SettingsLaunchSentinel.WaitOne(0)',
    [Math]::Max(0, $FinalPidSnapshotIndex))
if ($CompletionBoundaryIndex -lt 0 -or
    $WatcherDrainIndex -le $CompletionBoundaryIndex -or
    $FinalPidSnapshotIndex -le $WatcherDrainIndex -or
    $FinalSentinelCheckIndex -le $FinalPidSnapshotIndex) {
    throw "M10 capture must freeze completion before post-boundary watcher, PID, and sentinel observations."
}

$ToolbarFinalizeSource = Get-Content -Raw -LiteralPath $ToolbarFinalize
foreach ($Required in @(
        'm10_toolbar_topology_capture',
        'm10_toolbar_session_final',
        'Get-FileHash',
        'source_capture',
        'm10_toolbar_capture_receipt',
        'SettingsLaunchSentinelReady',
        'receipt_file_name',
        'receipt_sha256',
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
        'maximum_position',
        'at_end',
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
$SettingsProductSource = Get-Content -Raw -LiteralPath $SettingsProductSourcePath
foreach ($Required in @(
        'Local\\YuneWindowsSettingsLaunchObserved.v1',
        'OpenEventW(EVENT_MODIFY_STATE',
        'SetEvent(launch_observed)',
        'SignalSettingsLaunchObserver();'
    )) {
    Require-Text $SettingsProductSource ([regex]::Escape($Required)) `
        "M10 settings startup sentinel is missing required pattern: $Required"
}
$SentinelSignalIndex = $SettingsProductSource.IndexOf(
    'SignalSettingsLaunchObserver();')
$SingletonIndex = $SettingsProductSource.IndexOf(
    'CreateMutexW(nullptr, TRUE,',
    [Math]::Max(0, $SentinelSignalIndex))
if ($SentinelSignalIndex -lt 0 -or
    $SingletonIndex -lt 0 -or
    $SentinelSignalIndex -gt $SingletonIndex) {
    throw "M10 settings startup must signal the launch sentinel before singleton handling."
}

$Readme = Get-Content -Raw -LiteralPath $ReadmePath
foreach ($Required in @(
        'No file in this directory currently claims that M10 passed',
        '10 grip and 10 settings-segment drags',
        'light and dark themes',
        'exact capture SHA-256',
        'capture-time receipt',
        'YuneWindowsSettingsLaunchObserved.v1',
        'cannot accept pass/fail verdicts',
        'Machine-state evidence must be committed separately'
    )) {
    Require-Text $Readme ([regex]::Escape($Required)) `
        "M10 evidence README is missing honesty or acceptance guidance: $Required"
}

$Scratch = Join-Path $env:TEMP (
    "yune-windows\m10-evidence-contract-$PID-$([Guid]::NewGuid().ToString('N'))")
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
    $ToolbarReceiptPath = $ToolbarSmokePath + ".receipt.json"
    if (-not (Test-Path -LiteralPath $ToolbarReceiptPath -PathType Leaf)) {
        throw "M10 toolbar recorder smoke did not emit its capture-time receipt."
    }
    $ToolbarReceipt = Get-Content -Raw -LiteralPath $ToolbarReceiptPath |
        ConvertFrom-Json
    $ToolbarSmokeHash = (Get-FileHash -LiteralPath $ToolbarSmokePath -Algorithm SHA256).Hash
    if ($ToolbarSmoke.evidence_kind -ne "m10_toolbar_topology_capture" -or
        [int]$ToolbarSmoke.sampling.captured_sample_count -ne 1 -or
        $ToolbarSmoke.operator_report.verdict -ne "pending" -or
        @($ToolbarSmoke.machine_observed.settings_process_ids_started_during_capture).Count -ne 0 -or
        [bool]$ToolbarSmoke.gate_ready -or
        $ToolbarReceipt.evidence_kind -ne "m10_toolbar_capture_receipt" -or
        $ToolbarReceipt.capture_sha256 -ne $ToolbarSmokeHash -or
        $ToolbarReceipt.capture_file_name -ne [IO.Path]::GetFileName($ToolbarSmokePath) -or
        -not [bool]$ToolbarReceipt.settings_launch_sentinel_coverage_complete -or
        [bool]$ToolbarReceipt.settings_launch_sentinel_signaled -or
        -not [bool]$ToolbarSmoke.machine_observed.settings_launch_sentinel.coverage_complete -or
        [bool]$ToolbarSmoke.machine_observed.settings_launch_sentinel.signaled) {
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
    $ExpectedReceiptHash = (Get-FileHash -LiteralPath $ToolbarReceiptPath -Algorithm SHA256).Hash
    if ($ToolbarFinal.evidence_kind -ne "m10_toolbar_session_final" -or
        $ToolbarFinal.source_capture.sha256 -ne $ExpectedCaptureHash -or
        $ToolbarFinal.source_capture.receipt_sha256 -ne $ExpectedReceiptHash -or
        $ToolbarFinal.operator_report.total_drags_completed -ne 20 -or
        -not [bool]$ToolbarFinal.operator_report.report_complete -or
        [bool]$ToolbarFinal.gate_ready) {
        throw "M10 toolbar finalizer must bind the later complete operator report to the exact non-passing smoke capture."
    }

    Add-Content -LiteralPath $ToolbarSmokePath -Value " " -Encoding utf8
    $TamperRejected = $false
    try {
        & $ToolbarFinalize `
            -CapturePath $ToolbarSmokePath `
            -OutputPath (Join-Path $Scratch "toolbar-tampered-final.json") `
            -GripDragsCompleted 10 `
            -SettingsSegmentDragsCompleted 10 `
            -VisualCopiesOrAfterimagesAbsent pass `
            -FocusNeverStolen pass `
            -SettingsDragDidNotActivate pass `
            -CantoneseOnly pass `
            -PositionPersistedAfterFocus pass `
            -PositionPersistedAfterHostRestart pass | Out-Null
    }
    catch {
        $TamperRejected = $_.Exception.Message -match 'receipt does not bind'
    }
    if (-not $TamperRejected) {
        throw "M10 toolbar finalizer accepted a capture changed after its receipt was emitted."
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

    $SyntheticBoundary = [DateTimeOffset]::UtcNow.AddMinutes(-10)
    $SyntheticWatcherStart = $SyntheticBoundary.AddMinutes(1)
    $SyntheticCaptureStart = $SyntheticBoundary.AddMinutes(2)
    $SyntheticSampleOne = $SyntheticBoundary.AddMinutes(3)
    $SyntheticSampleTwo = $SyntheticBoundary.AddMinutes(4)
    $SyntheticCaptureComplete = $SyntheticBoundary.AddMinutes(5)
    $SyntheticWatcherStop = $SyntheticBoundary.AddMinutes(6)
    $SyntheticSentinelCheck = $SyntheticBoundary.AddMinutes(7)
    $SyntheticWindowCaptured = [pscustomobject]@{
        visible = $true
        hwnd_hex = "0x1234"
        process_name = "notepad"
        foreground = [pscustomobject]@{
            root_owner_matches_foreground_root_owner = $true
        }
        capture = [pscustomobject]@{ is_this_window = $true }
    }
    $SyntheticWindowReleased = [pscustomobject]@{
        visible = $true
        hwnd_hex = "0x1234"
        process_name = "notepad"
        foreground = [pscustomobject]@{
            root_owner_matches_foreground_root_owner = $true
        }
        capture = [pscustomobject]@{ is_this_window = $false }
    }
    $SyntheticCapture = [pscustomobject]@{
        schema_version = 1
        evidence_kind = "m10_toolbar_topology_capture"
        captured_at_utc = $SyntheticCaptureStart.ToString("o")
        completed_at_utc = $SyntheticCaptureComplete.ToString("o")
        host = [pscustomobject]@{
            id = "notepad"
            expected_process_name = "notepad"
        }
        sampling = [pscustomobject]@{
            requested_sample_count = 2
            captured_sample_count = 2
        }
        machine_observed = [pscustomobject]@{
            maximum_visible_toolbar_windows = 999
            settings_process_ids_started_during_capture = @()
            settings_launch_sentinel = [pscustomobject]@{
                name = "Local\YuneWindowsSettingsLaunchObserved.v1"
                capture_mutex_name = "Local\YuneWindowsM10ToolbarCapture.v1"
                capture_mutex_held = $true
                created_new = $true
                initialized_unsignaled_before_initial_process_snapshot = $true
                held_for_complete_capture = $true
                initialized_at_utc = $SyntheticWatcherStart.ToString("o")
                checked_at_utc = $SyntheticSentinelCheck.ToString("o")
                signaled = $false
                coverage_complete = $true
                failure = ""
            }
            settings_process_start_watcher = [pscustomobject]@{
                provider = "Win32_ProcessStartTrace"
                started_at_utc = $SyntheticWatcherStart.ToString("o")
                stopped_at_utc = $SyntheticWatcherStop.ToString("o")
                coverage_complete = $true
                failure = ""
                events = @()
            }
        }
        operator_report = [pscustomobject]@{ verdict = "pending" }
        gate_ready = $false
        samples = @(
            [pscustomobject]@{
                sample_index = 0
                captured_at_utc = $SyntheticSampleOne.ToString("o")
                window_count = 1
                windows = @($SyntheticWindowCaptured)
            },
            [pscustomobject]@{
                sample_index = 1
                captured_at_utc = $SyntheticSampleTwo.ToString("o")
                window_count = 1
                windows = @($SyntheticWindowReleased)
            }
        )
    }
    $SyntheticMetrics = Get-RecomputedToolbarCaptureMetrics `
        -Capture $SyntheticCapture `
        -EvidenceBoundary $SyntheticBoundary `
        -Context "synthetic M10 capture"
    if (-not [bool]$SyntheticMetrics.topology_ready -or
        [int]$SyntheticMetrics.maximum_visible_toolbar_windows -ne 1) {
        throw "M10 topology recomputation trusted a copied aggregate instead of source samples."
    }
    $SyntheticCapture.samples[0].captured_at_utc = $SyntheticBoundary.ToString("o")
    $StaleSampleRejected = $false
    try {
        [void](Get-RecomputedToolbarCaptureMetrics `
                -Capture $SyntheticCapture `
                -EvidenceBoundary $SyntheticBoundary `
                -Context "synthetic stale M10 capture")
    }
    catch {
        $StaleSampleRejected = $_.Exception.Message -match 'outside its post-verification capture interval'
    }
    if (-not $StaleSampleRejected) {
        throw "M10 topology recomputation accepted a sample at the deployment evidence boundary."
    }
    $SyntheticCapture.samples[0].captured_at_utc = $SyntheticSampleOne.ToString("o")
    $SyntheticCapture.machine_observed.settings_launch_sentinel.signaled = $true
    $SignaledMetrics = Get-RecomputedToolbarCaptureMetrics `
        -Capture $SyntheticCapture `
        -EvidenceBoundary $SyntheticBoundary `
        -Context "synthetic signaled M10 capture"
    if ([bool]$SignaledMetrics.topology_ready -or
        -not [bool]$SignaledMetrics.settings_launch_sentinel_signaled) {
        throw "M10 topology recomputation accepted a signaled settings launch sentinel."
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
foreach ($RequiredCheck in $RequiredChecks) {
    $Match = @($NonElevated.checks | Where-Object { $_.command -eq $RequiredCheck })
    if ($Match.Count -ne 1) {
        throw "M10 evidence schema is missing required preflight check: $RequiredCheck"
    }
}
$Preflight = Get-Content -Raw -LiteralPath $PreflightPath | ConvertFrom-Json
$PreflightSchemaVersion = [int]$Preflight.schema_version
if (@(1, 2) -notcontains $PreflightSchemaVersion -or
    $Preflight.milestone -ne "M10" -or
    $Preflight.evidence_kind -ne "non_elevated_preflight" -or
    $Preflight.verdict -ne "pass" -or
    $Preflight.implementation_commit -ne $Evidence.source.implementation_commit -or
    ($PreflightSchemaVersion -eq 1 -and
        $Preflight.checked_tree_commit -ne $Evidence.source.implementation_commit) -or
    ($PreflightSchemaVersion -eq 2 -and
        [string]$Preflight.checked_tree_commit -notmatch '^[0-9a-fA-F]{40}$') -or
    (@($Preflight.settings_dpi_percent_matrix | ForEach-Object { [int]$_ }) -join ',') -ne
        '100,125,150,200' -or
    -not [bool]$Preflight.settings_minimum_larger_scroll_each_dpi -or
    [bool]$Preflight.m11_boundary.m11_acceptance_claimed) {
    throw "M10 non-elevated preflight is not a passing, scope-honest record for the implementation commit."
}
if ($PreflightSchemaVersion -eq 2) {
    if (-not [bool]$Preflight.checked_tree_clean_before -or
        -not [bool]$Preflight.checked_tree_clean_after -or
        -not [bool]$Preflight.commit_role_order_verified -or
        [string]$Preflight.deployment_source_commit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "M10 schema-v2 preflight must bind a clean checked tree and deployed source commit."
    }
    $CandidateEquivalence = Require-Property `
        $Preflight "candidate_equivalence" "M10 schema-v2 preflight"
    $ExpectedProductPathspec = @(
        "src/**",
        "skins/**",
        "tools/build-tsf-shell.ps1")
    if ($CandidateEquivalence.from_deployment_source_commit -ne
            $Preflight.deployment_source_commit -or
        $CandidateEquivalence.to_checked_tree_commit -ne
            $Preflight.checked_tree_commit -or
        (@($CandidateEquivalence.checked_pathspec) -join ',') -ne
            ($ExpectedProductPathspec -join ',') -or
        @($CandidateEquivalence.changed_paths).Count -ne 0 -or
        -not [bool]$CandidateEquivalence.product_build_inputs_unchanged) {
        throw "M10 schema-v2 preflight does not prove candidate-preserving product-input equivalence."
    }
    Assert-Sha256 `
        ([string]$Preflight.candidate_manifest_sha256) `
        "M10 preflight candidate manifest"
    Assert-M10PreflightV2Timing $Preflight $RecordedPreflightChecks
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
        ([string]$Preflight.deployment_source_commit -ne
            "pending_until_frozen_docs_commit" -and
            [string]$Preflight.deployment_source_commit -notmatch
                '^[0-9a-fA-F]{40}$') -or
        [bool]$Evidence.machine_state_evidence_committed_separately) {
        throw "M10 pending template must not pre-claim non-elevated, installed, or publication success."
    }
    # Run this same contract from an isolated, canonical-layout repository fixture.
    # This exercises the complete branch without adding a production path override.
    $CompletedFixtureScratch = Join-Path $env:TEMP (
        "yune-windows\m10-completed-evidence-contract-$PID-$([Guid]::NewGuid().ToString('N'))")
    $CorruptFixtureRoots = [Collections.Generic.List[string]]::new()
    try {
        & $CompletedFixtureBuilder `
            -SourceRepoRoot $RepoRoot `
            -OutputRoot $CompletedFixtureScratch | Out-Null
        & (Join-Path $CompletedFixtureScratch "tools\test-m10-evidence-summary-contract.ps1") |
            Out-Null

        $CorruptionCases = @(
            [pscustomobject]@{
                fixture_switch = "CorruptRecomputedMetric"
                expected_error = "samples_with_visible_toolbar is not recomputed consistently from source samples"
            },
            [pscustomobject]@{
                fixture_switch = "CorruptVerifierTooling"
                expected_error = "verifier tooling is not bound to the clean current verifier script"
            },
            [pscustomobject]@{
                fixture_switch = "CorruptBootBoundary"
                expected_error = "does not mechanically prove a boot after deployment"
            },
            [pscustomobject]@{
                fixture_switch = "CorruptTargetedCoverage"
                expected_error = "holder coverage is not a complete targeted TSF module scan"
            }
        )
        foreach ($CorruptionCase in $CorruptionCases) {
            $CorruptFixtureScratch = Join-Path $env:TEMP (
                "yune-windows\m10-completed-evidence-corrupt-$PID-$([Guid]::NewGuid().ToString('N'))")
            $CorruptFixtureRoots.Add($CorruptFixtureScratch)
            $FixtureParameters = @{
                SourceRepoRoot = $RepoRoot
                OutputRoot = $CorruptFixtureScratch
            }
            $FixtureParameters[$CorruptionCase.fixture_switch] = $true
            & $CompletedFixtureBuilder @FixtureParameters | Out-Null
            $CorruptionRejected = $false
            try {
                & (Join-Path $CorruptFixtureScratch "tools\test-m10-evidence-summary-contract.ps1") |
                    Out-Null
            }
            catch {
                $CorruptionRejected = $_.Exception.Message.Contains(
                    [string]$CorruptionCase.expected_error)
            }
            if (-not $CorruptionRejected) {
                throw "M10 synthetic completed-summary contract did not reject $($CorruptionCase.fixture_switch)."
            }
        }
        Write-Host "M10 synthetic completed-summary, recomputation, verifier provenance, boot-boundary, and holder-coverage contracts passed."
    }
    finally {
        Remove-Item -LiteralPath $CompletedFixtureScratch -Recurse -Force `
            -ErrorAction SilentlyContinue
        foreach ($CorruptFixtureScratch in $CorruptFixtureRoots) {
            Remove-Item -LiteralPath $CorruptFixtureScratch -Recurse -Force `
                -ErrorAction SilentlyContinue
        }
    }
    Write-Host "M10 evidence tooling/template contract passed; installed summary remains honestly pending."
    return
}

if ($Evidence.status -ne "complete" -or $EvidenceJsonPath -ne $SummaryPath) {
    throw "A non-pending M10 evidence record must be docs/evidence/m10/summary.json with status complete."
}
if ($PreflightSchemaVersion -ne 2) {
    throw "completed M10 evidence requires an honestly timed schema-v2 preflight run."
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
if ($Preflight.candidate_manifest_path -ne $Artifacts.candidate_manifest_path -or
    -not [string]::Equals(
        [string]$Preflight.candidate_manifest_sha256,
        [string]$Artifacts.candidate_manifest_sha256,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "M10 non-elevated preflight is not bound to the completed candidate manifest."
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
$ExpectedVerifierRelativePath = "tools/dev/verify-m10-frozen-candidate.ps1"
$RecordedTooling = Require-Property `
    $PostRestartVerification `
    "tooling" `
    "M10 post-restart verification"
$ExpectedVerifierHash = (Get-FileHash `
        -Algorithm SHA256 `
        -LiteralPath $FrozenCandidateVerifier).Hash
Assert-Sha256 `
    ([string]$RecordedTooling.verifier_script_sha256) `
    "M10 post-restart verifier script"
if (-not [bool]$RecordedTooling.tooling_source_commit_known -or
    [string]$RecordedTooling.tooling_source_commit -notmatch '^[0-9A-Fa-f]{40}$' -or
    -not [bool]$RecordedTooling.verifier_matches_tooling_commit -or
    -not [bool]$RecordedTooling.working_tree_clean -or
    [string]$RecordedTooling.verifier_repo_relative_path -ne
        $ExpectedVerifierRelativePath -or
    -not [string]::Equals(
        [string]$RecordedTooling.verifier_script_sha256,
        $ExpectedVerifierHash,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "M10 post-restart verifier tooling is not bound to the clean current verifier script."
}

$HolderCoverage = Require-Property `
    $PostRestartVerification.holders `
    "coverage" `
    "M10 post-restart holder evidence"
$TargetedScan = Require-Property `
    $HolderCoverage `
    "targeted_scan" `
    "M10 post-restart holder coverage"
if (-not [bool]$TargetedScan.query_succeeded -or
    -not [string]::IsNullOrWhiteSpace([string]$TargetedScan.query_error) -or
    [int]$HolderCoverage.targeted_unresolved_count -ne 0 -or
    @($HolderCoverage.targeted_unresolved).Count -ne 0 -or
    -not [bool]$HolderCoverage.targeted_coverage_complete -or
    [bool]$PostRestartVerification.holders.coverage_complete -ne
        [bool]$HolderCoverage.targeted_coverage_complete) {
    throw "M10 post-restart holder coverage is not a complete targeted TSF module scan."
}
$DeploymentCompletedAt = Convert-IsoTimestamp `
    ([string]$CandidateManifest.deployment.completed_at) `
    "M10 frozen-candidate deployment completion"
$VerifierCapturedAt = Convert-IsoTimestamp `
    ([string]$PostRestartVerification.captured_at) `
    "M10 post-restart verification capture"
if ($VerifierCapturedAt -le $DeploymentCompletedAt) {
    throw "M10 post-restart verification must be strictly after deployment completion."
}
$RestartBoundary = Require-Property `
    $PostRestartVerification `
    "restart_boundary" `
    "M10 post-restart verification"
$LastBootUpTime = Convert-IsoTimestamp `
    ([string]$RestartBoundary.last_boot_up_time) `
    "M10 post-restart last boot time"
if (-not [bool]$RestartBoundary.query_succeeded -or
    -not [string]::IsNullOrWhiteSpace([string]$RestartBoundary.query_error) -or
    -not [bool]$RestartBoundary.boot_time_known -or
    -not [bool]$RestartBoundary.booted_strictly_after_deployment -or
    -not [bool]$RestartBoundary.proof_complete -or
    $LastBootUpTime -le $DeploymentCompletedAt) {
    throw "M10 post-restart evidence does not mechanically prove a boot after deployment."
}
$InstalledEvidenceBoundary = $VerifierCapturedAt

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
$SeenSessionEvidencePaths = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($HostEvidence in $Hosts) {
    if ([int]$HostEvidence.grip_drags -lt 10 -or
        [int]$HostEvidence.settings_segment_drags -lt 10 -or
        [int]$HostEvidence.total_drags -ne ([int]$HostEvidence.grip_drags + [int]$HostEvidence.settings_segment_drags)) {
        throw "M10 host $($HostEvidence.id) requires at least 10 grip and 10 settings-segment drags with a consistent total."
    }
    $ComputedTotalDrags += [int]$HostEvidence.total_drags
    if ($HostEvidence.id -eq "electron" -and
        ([string]::IsNullOrWhiteSpace([string]$HostEvidence.host_name) -or
         [string]$HostEvidence.host_name -eq "Electron")) {
        throw "M10 Electron evidence must name the tested product."
    }
    if ([int]$HostEvidence.maximum_visible_toolbar_windows -gt 1 -or
        -not [bool]$HostEvidence.all_visible_owners_match_foreground_root -or
        -not [bool]$HostEvidence.sampled_visible_hwnd_stable -or
        -not [bool]$HostEvidence.no_stuck_capture -or
        [bool]$HostEvidence.settings_process_launched_by_drag -or
        -not [bool]$HostEvidence.settings_segment_drag_did_not_activate -or
        -not [bool]$HostEvidence.focus_never_stolen -or
        $HostEvidence.visual_copies_or_afterimages_absent -ne "pass" -or
        -not [bool]$HostEvidence.position_persisted_after_focus_movement -or
        -not [bool]$HostEvidence.position_persisted_after_host_restart) {
        throw "M10 host $($HostEvidence.id) does not satisfy the ownership/drag/visual/persistence gate."
    }
    $SessionPaths = @($HostEvidence.session_evidence)
    if ($SessionPaths.Count -eq 0) {
        throw "M10 host $($HostEvidence.id) has no topology-session evidence."
    }
    $SessionGripDrags = 0
    $SessionSettingsDrags = 0
    $SessionMaximumVisible = 0
    $SessionAllOwnersMatch = $true
    $SessionAllHwndsStable = $true
    $SessionAllReleasedCapture = $true
    $SessionSettingsProcessLaunched = $false
    foreach ($SessionPath in $SessionPaths) {
        $ResolvedSession = Resolve-EvidencePath ([string]$SessionPath) "M10 $($HostEvidence.id) topology session"
        if (-not $SeenSessionEvidencePaths.Add($ResolvedSession)) {
            throw "M10 session_evidence path is duplicated: $SessionPath"
        }
        $Session = Get-Content -Raw -LiteralPath $ResolvedSession | ConvertFrom-Json
        if ($Session.evidence_kind -ne "m10_toolbar_session_final" -or
            $Session.host.id -ne $HostEvidence.id -or
            -not [bool]$Session.operator_report.report_complete -or
            -not [bool]$Session.gate_ready) {
            throw "M10 $($HostEvidence.id) topology session is not a complete passing recorder result."
        }
        $SourceCaptureName = [string]$Session.source_capture.file_name
        if ([string]::IsNullOrWhiteSpace($SourceCaptureName) -or
            [IO.Path]::GetFileName($SourceCaptureName) -ne $SourceCaptureName) {
            throw "M10 $($HostEvidence.id) finalized session has an unsafe source capture name."
        }
        $SourceCapturePath = Join-Path (Split-Path -Parent $ResolvedSession) $SourceCaptureName
        if (-not (Test-Path -LiteralPath $SourceCapturePath -PathType Leaf)) {
            throw "M10 $($HostEvidence.id) finalized session is missing its immutable source capture."
        }
        $SourceCaptureHash = (Get-FileHash -LiteralPath $SourceCapturePath -Algorithm SHA256).Hash
        if ($SourceCaptureHash -ne [string]$Session.source_capture.sha256) {
            throw "M10 $($HostEvidence.id) finalized session source capture hash does not match."
        }
        $SourceReceiptName = [string]$Session.source_capture.receipt_file_name
        if ([string]::IsNullOrWhiteSpace($SourceReceiptName) -or
            [IO.Path]::GetFileName($SourceReceiptName) -ne $SourceReceiptName) {
            throw "M10 $($HostEvidence.id) finalized session has an unsafe capture receipt name."
        }
        $SourceReceiptPath = Join-Path `
            (Split-Path -Parent $ResolvedSession) `
            $SourceReceiptName
        if (-not (Test-Path -LiteralPath $SourceReceiptPath -PathType Leaf)) {
            throw "M10 $($HostEvidence.id) finalized session is missing its capture-time receipt."
        }
        $SourceReceiptHash = (Get-FileHash `
                -LiteralPath $SourceReceiptPath `
                -Algorithm SHA256).Hash
        $SourceReceipt = Get-Content -Raw -LiteralPath $SourceReceiptPath |
            ConvertFrom-Json
        if ($SourceReceiptHash -ne [string]$Session.source_capture.receipt_sha256 -or
            $SourceReceipt.evidence_kind -ne "m10_toolbar_capture_receipt" -or
            $SourceReceipt.capture_file_name -ne $SourceCaptureName -or
            $SourceReceipt.capture_sha256 -ne $SourceCaptureHash -or
            -not [bool]$SourceReceipt.settings_launch_sentinel_coverage_complete -or
            [bool]$SourceReceipt.settings_launch_sentinel_signaled) {
            throw "M10 $($HostEvidence.id) capture-time receipt does not bind the immutable source capture."
        }
        $SourceCapture = Get-Content -Raw -LiteralPath $SourceCapturePath |
            ConvertFrom-Json
        if ($SourceCapture.host.id -ne $HostEvidence.id -or
            $Session.source_capture.captured_at_utc -ne $SourceCapture.captured_at_utc -or
            $Session.source_capture.completed_at_utc -ne $SourceCapture.completed_at_utc -or
            $SourceReceipt.capture_completed_at_utc -ne $SourceCapture.completed_at_utc) {
            throw "M10 $($HostEvidence.id) finalized source metadata disagrees with its source capture."
        }
        $CaptureMetrics = Get-RecomputedToolbarCaptureMetrics `
            -Capture $SourceCapture `
            -EvidenceBoundary $InstalledEvidenceBoundary `
            -Context "M10 $($HostEvidence.id) source capture"
        $ReceiptCreatedAt = Convert-IsoTimestamp `
            ([string]$SourceReceipt.created_at_utc) `
            "M10 $($HostEvidence.id) capture receipt"
        $FinalizedAt = Convert-IsoTimestamp `
            ([string]$Session.finalized_at_utc) `
            "M10 $($HostEvidence.id) finalized session"
        if ($ReceiptCreatedAt -lt $CaptureMetrics.capture_completed_at -or
            $FinalizedAt -lt $ReceiptCreatedAt) {
            throw "M10 $($HostEvidence.id) receipt/finalization chronology is inconsistent."
        }
        foreach ($MetricField in @(
                "samples_with_visible_toolbar",
                "samples_with_toolbar_capture",
                "maximum_visible_toolbar_windows",
                "samples_with_multiple_visible_toolbars",
                "samples_with_foreground_owner_mismatch",
                "samples_with_unexpected_host_process",
                "sampled_visible_hwnd_stable",
                "final_sample_visible_toolbar_count",
                "final_sample_has_toolbar_capture",
                "final_sample_owner_matches_foreground_root",
                "topology_ready"
            )) {
            if ([string]$SourceCapture.machine_observed.$MetricField -ne
                [string]$CaptureMetrics.$MetricField -or
                [string]$Session.machine_observed.$MetricField -ne
                [string]$CaptureMetrics.$MetricField) {
                throw "M10 $($HostEvidence.id) $MetricField is not recomputed consistently from source samples."
            }
        }
        foreach ($MetricArrayField in @(
                "observed_visible_process_names",
                "distinct_visible_hwnds",
                "final_sample_visible_hwnds",
                "settings_process_ids_started_during_capture"
            )) {
            $SourceProjection = @($SourceCapture.machine_observed.$MetricArrayField) -join ','
            $FinalProjection = @($Session.machine_observed.$MetricArrayField) -join ','
            $RecomputedProjection = @($CaptureMetrics.$MetricArrayField) -join ','
            if ($SourceProjection -ne $RecomputedProjection -or
                $FinalProjection -ne $RecomputedProjection) {
                throw "M10 $($HostEvidence.id) $MetricArrayField is not bound to source samples."
            }
        }
        if (-not [bool]$CaptureMetrics.topology_ready) {
            throw "M10 $($HostEvidence.id) source samples do not independently satisfy topology readiness."
        }
        if ([bool]$SourceCapture.machine_observed.settings_launch_sentinel.signaled -ne
                [bool]$CaptureMetrics.settings_launch_sentinel_signaled -or
            [bool]$Session.machine_observed.settings_launch_sentinel.signaled -ne
                [bool]$CaptureMetrics.settings_launch_sentinel_signaled -or
            [bool]$SourceCapture.machine_observed.settings_launch_sentinel.coverage_complete -ne
                [bool]$CaptureMetrics.settings_launch_sentinel_coverage_complete -or
            [bool]$Session.machine_observed.settings_launch_sentinel.coverage_complete -ne
                [bool]$CaptureMetrics.settings_launch_sentinel_coverage_complete) {
            throw "M10 $($HostEvidence.id) settings launch sentinel projection is inconsistent."
        }
        $SessionGripDrags += [int]$Session.operator_report.grip_drags_completed
        $SessionSettingsDrags += [int]$Session.operator_report.settings_segment_drags_completed
        $SessionMaximumVisible = [Math]::Max(
            $SessionMaximumVisible,
            [int]$CaptureMetrics.maximum_visible_toolbar_windows)
        $SessionAllOwnersMatch = [bool](
            $SessionAllOwnersMatch -and
            [int]$CaptureMetrics.samples_with_foreground_owner_mismatch -eq 0)
        $SessionAllHwndsStable = [bool](
            $SessionAllHwndsStable -and
            [bool]$CaptureMetrics.sampled_visible_hwnd_stable)
        $SessionAllReleasedCapture = [bool](
            $SessionAllReleasedCapture -and
            -not [bool]$CaptureMetrics.final_sample_has_toolbar_capture)
        $SessionSettingsProcessLaunched = [bool](
            $SessionSettingsProcessLaunched -or
            [bool]$CaptureMetrics.settings_launch_sentinel_signaled -or
            @($CaptureMetrics.settings_process_ids_started_during_capture).Count -gt 0)
    }
    if ($SessionGripDrags -ne [int]$HostEvidence.grip_drags -or
        $SessionSettingsDrags -ne [int]$HostEvidence.settings_segment_drags -or
        $SessionMaximumVisible -ne [int]$HostEvidence.maximum_visible_toolbar_windows -or
        $SessionAllOwnersMatch -ne [bool]$HostEvidence.all_visible_owners_match_foreground_root -or
        $SessionAllHwndsStable -ne [bool]$HostEvidence.sampled_visible_hwnd_stable -or
        $SessionAllReleasedCapture -ne [bool]$HostEvidence.no_stuck_capture -or
        $SessionSettingsProcessLaunched -ne [bool]$HostEvidence.settings_process_launched_by_drag) {
        throw "M10 host $($HostEvidence.id) summary counts do not match its SHA-pinned finalized session evidence."
    }
    if (-not [bool]$HostEvidence.no_stuck_capture) {
        throw "M10 host $($HostEvidence.id) cannot claim completion without machine-observed released capture in every session."
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
$ToolbarVerdictAt = Convert-IsoTimestamp `
    ([string]$ToolbarGate.operator_visual_verdict.recorded_at_utc) `
    "M10 toolbar user verdict"
if ($ToolbarVerdictAt -le $InstalledEvidenceBoundary) {
    throw "M10 toolbar user verdict must postdate the post-restart verifier."
}

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
$SettingsVerdictAt = Convert-IsoTimestamp `
    ([string]$SettingsGate.operator_visual_verdict.recorded_at_utc) `
    "M10 settings user verdict"
if ($SettingsVerdictAt -le $InstalledEvidenceBoundary) {
    throw "M10 settings user verdict must postdate the post-restart verifier."
}
$GeometryPaths = @($SettingsGate.geometry_evidence)
if ($GeometryPaths.Count -ne 5) {
    throw "M10 completed settings evidence requires initial, minimum, minimum-scrolled, larger, and reopened geometry captures."
}
$ObservedGeometryPhases = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$ObservedGeometryThemes = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$ObservedSettingsOperatorPasses = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$ObservedGeometryDpi = [Collections.Generic.HashSet[int]]::new()
$SeenGeometryPaths = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$GeometryByPhase = @{}
foreach ($GeometryPath in $GeometryPaths) {
    $ResolvedGeometry = Resolve-EvidencePath ([string]$GeometryPath) "M10 settings geometry"
    if (-not $SeenGeometryPaths.Add($ResolvedGeometry)) {
        throw "M10 settings geometry path is duplicated: $GeometryPath"
    }
    $Geometry = Get-Content -Raw -LiteralPath $ResolvedGeometry | ConvertFrom-Json
    if ($Geometry.evidence_kind -ne "m10_settings_geometry" -or
        [int]$Geometry.window_count -ne 1 -or
        @($Geometry.windows).Count -ne 1) {
        throw "M10 settings geometry must contain exactly one settings window: $GeometryPath"
    }
    $GeometryCapturedAt = Convert-IsoTimestamp `
        ([string]$Geometry.captured_at_utc) `
        "M10 settings geometry $GeometryPath"
    if ($GeometryCapturedAt -le $InstalledEvidenceBoundary) {
        throw "M10 settings geometry predates the post-restart verifier: $GeometryPath"
    }
    $Phase = [string]$Geometry.phase
    if ($GeometryByPhase.ContainsKey($Phase)) {
        throw "M10 settings geometry contains duplicate phase: $Phase"
    }
    $Window = @($Geometry.windows)[0]
    if (-not [bool]$Window.visible -or
        $Window.process_name -ne "YuneWindowsSettings" -or
        -not [bool]$Window.client_rect.available -or
        [int]$Window.client_rect.width -le 0 -or
        [int]$Window.client_rect.height -le 0 -or
        [int]$Window.dpi -lt 96 -or
        [int]$Window.dpi -gt 768) {
        throw "M10 settings geometry is not a usable installed settings window: $GeometryPath"
    }
    $GeometryByPhase[$Phase] = [pscustomobject]@{
        geometry = $Geometry
        window = $Window
    }
    [void]$ObservedGeometryDpi.Add([int]$Window.dpi)
    [void]$ObservedGeometryPhases.Add($Phase)
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
$SummaryDpi = @($SettingsGate.exercised_dpi | ForEach-Object { [int]$_ } | Sort-Object -Unique)
$GeometryDpi = @($ObservedGeometryDpi | Sort-Object)
if (($SummaryDpi -join ',') -ne ($GeometryDpi -join ',')) {
    throw "M10 settings exercised_dpi is not derived from the geometry captures."
}
$PhaseToSizeField = @{
    initial = "initial_client_size"
    minimum = "minimum_client_size"
    larger = "larger_client_size"
}
foreach ($Phase in $PhaseToSizeField.Keys) {
    $SizeField = $PhaseToSizeField[$Phase]
    $CapturedClient = $GeometryByPhase[$Phase].window.client_rect
    $SummaryClient = $SettingsGate.$SizeField
    if ([int]$SummaryClient.width -ne [int]$CapturedClient.width -or
        [int]$SummaryClient.height -ne [int]$CapturedClient.height) {
        throw "M10 settings $SizeField is not derived from the $Phase geometry capture."
    }
}
$MinimumScrolledWindow = $GeometryByPhase["minimum_scrolled"].window
foreach ($ScrollAxis in @("horizontal", "vertical")) {
    $Scroll = $MinimumScrolledWindow.scroll.$ScrollAxis
    $ComputedMaximumPosition = [Math]::Max(
        [int]$Scroll.minimum,
        [int]$Scroll.maximum - [int]$Scroll.page + 1)
    $ComputedAtEnd = [bool](
        [bool]$Scroll.available -and
        [bool]$Scroll.can_scroll -and
        [int]$Scroll.page -gt 0 -and
        [int]$Scroll.position -ge $ComputedMaximumPosition)
    if ([int]$Scroll.maximum_position -ne $ComputedMaximumPosition -or
        [bool]$Scroll.at_end -ne $ComputedAtEnd -or
        -not $ComputedAtEnd) {
        throw "M10 minimum_scrolled geometry does not mechanically prove the $ScrollAxis scrollbar reached its end."
    }
    $SummaryScrollField = $ScrollAxis + "_scroll_reaches_canvas_end"
    if (-not [bool]$SettingsGate.$SummaryScrollField) {
        throw "M10 settings $SummaryScrollField is not bound to geometry."
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
