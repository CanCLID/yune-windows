param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("notepad", "chromium", "explorer", "electron")]
    [string]$HostId,

    [string]$ElectronHostName = "",

    [Parameter(Mandatory = $true)]
    [string]$ExpectedHostProcessName,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateRange(1, 10000)]
    [int]$SampleCount = 1200,

    [ValidateRange(20, 5000)]
    [int]$IntervalMs = 100
)

$ErrorActionPreference = "Stop"

if ($HostId -eq "electron" -and [string]::IsNullOrWhiteSpace($ElectronHostName)) {
    throw "-ElectronHostName is required when -HostId electron is selected."
}
if ([string]::IsNullOrWhiteSpace($ExpectedHostProcessName)) {
    throw "-ExpectedHostProcessName must identify the process expected to own the sampled toolbar."
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$TopologyScript = Join-Path $RepoRoot "tools\dev\capture-language-bar-topology.ps1"
if (-not (Test-Path -LiteralPath $TopologyScript -PathType Leaf)) {
    throw "missing topology diagnostic: $TopologyScript"
}

$FullOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($FullOutputPath) -ne ".json") {
    throw "-OutputPath must name a .json file."
}
$OutputDirectory = Split-Path -Parent $FullOutputPath
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw "-OutputPath must include a parent directory."
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$ReceiptPath = $FullOutputPath + ".receipt.json"
if ((Test-Path -LiteralPath $FullOutputPath) -or
    (Test-Path -LiteralPath $ReceiptPath)) {
    throw "capture output and receipt are write-once; choose a new -OutputPath."
}

function Get-SettingsProcessIds {
    return @(
        Get-Process -Name "YuneWindowsSettings" -ErrorAction SilentlyContinue |
            Sort-Object Id |
            ForEach-Object { [int]$_.Id }
    )
}

function Receive-SettingsProcessStartEvents {
    param([string]$SourceIdentifier)

    $Received = [Collections.Generic.List[object]]::new()
    try {
        foreach ($QueuedEvent in @(Get-Event `
                -SourceIdentifier $SourceIdentifier `
                -ErrorAction SilentlyContinue)) {
            $StartedAt = ""
            try {
                $TimeCreated = [int64]$QueuedEvent.SourceEventArgs.NewEvent.TIME_CREATED
                if ($TimeCreated -gt 0) {
                    $StartedAt = [DateTimeOffset]::FromFileTime($TimeCreated).
                        ToUniversalTime().ToString(
                            "o",
                            [Globalization.CultureInfo]::InvariantCulture)
                }
            }
            catch {
                $StartedAt = ""
            }
            $Received.Add([pscustomobject][ordered]@{
                    process_id = [int]$QueuedEvent.SourceEventArgs.NewEvent.ProcessID
                    process_name = [string]$QueuedEvent.SourceEventArgs.NewEvent.ProcessName
                    started_at_utc = $StartedAt
                    observed_at_utc = [DateTimeOffset]::UtcNow.ToString(
                        "o",
                        [Globalization.CultureInfo]::InvariantCulture)
                })
            Remove-Event -EventIdentifier $QueuedEvent.EventIdentifier -ErrorAction Stop
        }
        return [pscustomobject]@{
            success = $true
            error = ""
            events = @($Received)
        }
    }
    catch {
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            events = @($Received)
        }
    }
}

$CaptureMutexName = "Local\YuneWindowsM10ToolbarCapture.v1"
$SettingsLaunchSentinelName = "Local\YuneWindowsSettingsLaunchObserved.v1"
$CaptureMutex = $null
$CaptureMutexHeld = $false
$SettingsLaunchSentinel = $null
$SettingsLaunchSentinelCreatedNew = $false
$SettingsLaunchSentinelInitializedUnsignaled = $false
$SettingsLaunchSentinelHeld = $false
$SettingsLaunchSentinelSignaled = $false
$SettingsLaunchSentinelInitializedAt = ""
$SettingsLaunchSentinelCheckedAt = ""
$SettingsLaunchSentinelFailure = ""
try {
    $CaptureMutex = [Threading.Mutex]::new($false, $CaptureMutexName)
    try {
        $CaptureMutexHeld = $CaptureMutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $CaptureMutexHeld = $true
    }
    if (-not $CaptureMutexHeld) {
        throw "another M10 toolbar capture already holds $CaptureMutexName."
    }

    $SettingsLaunchSentinel = [Threading.EventWaitHandle]::new(
        $false,
        [Threading.EventResetMode]::ManualReset,
        $SettingsLaunchSentinelName,
        [ref]$SettingsLaunchSentinelCreatedNew)
    if (-not $SettingsLaunchSentinelCreatedNew) {
        throw "settings launch sentinel already exists; concurrent or stale capture state cannot be reset safely."
    }
    if ($SettingsLaunchSentinel.WaitOne(0)) {
        throw "settings launch sentinel was signaled during atomic initialization."
    }
    $SettingsLaunchSentinelInitializedUnsignaled = $true
    $SettingsLaunchSentinelHeld = $true
    $SettingsLaunchSentinelInitializedAt = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
}
catch {
    $SettingsLaunchSentinelFailure = $_.Exception.Message
    if ($null -ne $SettingsLaunchSentinel) {
        $SettingsLaunchSentinel.Dispose()
    }
    if ($CaptureMutexHeld -and $null -ne $CaptureMutex) {
        $CaptureMutex.ReleaseMutex()
    }
    if ($null -ne $CaptureMutex) {
        $CaptureMutex.Dispose()
    }
    throw
}

# The launch sentinel is initialized before this baseline so every settings
# executable startup during the measured interval can signal it.
$SettingsProcessesBefore = @(Get-SettingsProcessIds)
$SettingsProcessesAfter = @()
$NewSettingsProcessIdsObserved = [Collections.Generic.HashSet[int]]::new()
$SettingsProcessStartEvents = [Collections.Generic.List[object]]::new()
$SettingsWatcher = $null
$SettingsWatcherSourceIdentifier = "YuneWindows.M10.SettingsStart.$PID.$([Guid]::NewGuid().ToString('N'))"
$SettingsWatcherStartedAt = ""
$SettingsWatcherStoppedAt = ""
$SettingsWatcherFailure = ""
$SettingsWatcherPrimaryProviderFailure = ""
$SettingsWatcherProvider = ""
$SettingsWatcherActive = $false
$SettingsWatcherStartedSuccessfully = $false
$SettingsPollingJob = $null
$SettingsPollingIntervalMs = 5
$SettingsPollingCount = 0
$SettingsPollingMaximumGapMs = 0
$SettingsPollingToken = [Guid]::NewGuid().ToString("N")
$SettingsPollingReadyPath = Join-Path `
    $env:TEMP `
    "yune-windows-m10-settings-watch-$SettingsPollingToken.ready"
$SettingsPollingStopPath = Join-Path `
    $env:TEMP `
    "yune-windows-m10-settings-watch-$SettingsPollingToken.stop"
try {
    Add-Type -AssemblyName System.Management -ErrorAction Stop
    $SettingsWatcherQuery = [System.Management.WqlEventQuery]::new(
        "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName = 'YuneWindowsSettings.exe'")
    $SettingsWatcher = [System.Management.ManagementEventWatcher]::new(
        $SettingsWatcherQuery)
    Register-ObjectEvent `
        -InputObject $SettingsWatcher `
        -EventName EventArrived `
        -SourceIdentifier $SettingsWatcherSourceIdentifier | Out-Null
    $SettingsWatcher.Start()
    $SettingsWatcherProvider = "Win32_ProcessStartTrace"
    $SettingsWatcherActive = $true
    $SettingsWatcherStartedSuccessfully = $true
    $SettingsWatcherStartedAt = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
}
catch {
    $SettingsWatcherPrimaryProviderFailure = $_.Exception.Message
    try {
        $SettingsPollingJob = Start-Job -ScriptBlock {
            param(
                [string]$ReadyPath,
                [string]$StopPath,
                [int]$IntervalMs)

            $Observed = [Collections.Generic.Dictionary[int, object]]::new()
            $PollCount = 0
            $MaximumGapMs = 0.0
            $PreviousPollAt = [DateTimeOffset]::UtcNow
            $StartedAt = $PreviousPollAt
            Set-Content `
                -LiteralPath $ReadyPath `
                -Value $StartedAt.ToString("o") `
                -Encoding ascii
            $Failure = ""
            try {
                while (-not (Test-Path -LiteralPath $StopPath)) {
                    $PollAt = [DateTimeOffset]::UtcNow
                    $GapMs = ($PollAt - $PreviousPollAt).TotalMilliseconds
                    if ($GapMs -gt $MaximumGapMs) {
                        $MaximumGapMs = $GapMs
                    }
                    $PreviousPollAt = $PollAt
                    $PollCount += 1
                    foreach ($Process in @(Get-Process `
                            -Name "YuneWindowsSettings" `
                            -ErrorAction SilentlyContinue)) {
                        if (-not $Observed.ContainsKey([int]$Process.Id)) {
                            $ProcessStartedAt = ""
                            try {
                                $ProcessStartedAt = $Process.StartTime.
                                    ToUniversalTime().ToString("o")
                            }
                            catch {
                                $ProcessStartedAt = ""
                            }
                            $Observed[[int]$Process.Id] = [pscustomobject][ordered]@{
                                process_id = [int]$Process.Id
                                process_name = "YuneWindowsSettings.exe"
                                started_at_utc = $ProcessStartedAt
                                observed_at_utc = $PollAt.ToString("o")
                            }
                        }
                    }
                    Start-Sleep -Milliseconds $IntervalMs
                }
            }
            catch {
                $Failure = $_.Exception.Message
            }
            [pscustomobject][ordered]@{
                success = [string]::IsNullOrWhiteSpace($Failure)
                failure = $Failure
                started_at_utc = $StartedAt.ToString("o")
                stopped_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
                requested_interval_ms = $IntervalMs
                poll_count = $PollCount
                maximum_gap_ms = [Math]::Round($MaximumGapMs, 3)
                events = @($Observed.Values | Sort-Object process_id)
            }
        } -ArgumentList @(
            $SettingsPollingReadyPath,
            $SettingsPollingStopPath,
            $SettingsPollingIntervalMs)

        $ReadyDeadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
        while (-not (Test-Path -LiteralPath $SettingsPollingReadyPath) -and
            [DateTimeOffset]::UtcNow -lt $ReadyDeadline -and
            $SettingsPollingJob.State -eq "Running") {
            Start-Sleep -Milliseconds 10
        }
        if (-not (Test-Path -LiteralPath $SettingsPollingReadyPath -PathType Leaf)) {
            throw "continuous settings-process poller did not become ready."
        }
        $SettingsWatcherStartedAt = (
            Get-Content -Raw -LiteralPath $SettingsPollingReadyPath).Trim()
        $SettingsWatcherProvider = "continuous_process_poll"
        $SettingsWatcherActive = $true
    }
    catch {
        $SettingsWatcherFailure = $_.Exception.Message
    }
}
if ($SettingsWatcherProvider -ne "Win32_ProcessStartTrace") {
    Write-Warning (
        "Auxiliary Win32 process-start telemetry is unavailable; the named " +
        "settings-launch sentinel remains authoritative. Poll telemetry does " +
        "not establish coverage. Primary provider failure: " +
        $SettingsWatcherPrimaryProviderFailure)
}
$Samples = [Collections.Generic.List[object]]::new()
$DistinctVisibleHwnds = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$ObservedVisibleProcessNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$MaximumVisibleWindows = 0
$SamplesWithVisibleWindow = 0
$SamplesWithToolbarCapture = 0
$SamplesWithMultipleVisibleWindows = 0
$SamplesWithForegroundOwnerMismatch = 0
$SamplesWithUnexpectedHostProcess = 0
$CaptureStartedAt = [DateTimeOffset]::UtcNow
$FinalSampleVisibleToolbarCount = 0
$FinalSampleHasToolbarCapture = $false
$FinalSampleOwnerMatchesForeground = $false
$FinalSampleVisibleHwnds = @()
$CaptureCompletedAt = ""

try {
    for ($SampleIndex = 0; $SampleIndex -lt $SampleCount; $SampleIndex += 1) {
        $TopologyJson = (& $TopologyScript | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($TopologyJson)) {
            throw "topology diagnostic emitted no JSON at sample $SampleIndex."
        }
        try {
            $Topology = $TopologyJson | ConvertFrom-Json
        }
        catch {
            throw "topology diagnostic emitted invalid JSON at sample $SampleIndex`: $($_.Exception.Message)"
        }

        $VisibleWindows = @($Topology.windows | Where-Object { [bool]$_.visible })
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
                    $ExpectedHostProcessName,
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

        $FinalSampleVisibleToolbarCount = $VisibleWindows.Count
        $FinalSampleHasToolbarCapture = [bool](
            @($VisibleWindows | Where-Object { [bool]$_.capture.is_this_window }).Count -gt 0)
        $FinalSampleOwnerMatchesForeground = [bool](
            $VisibleWindows.Count -eq 1 -and
            [bool]$VisibleWindows[0].foreground.root_owner_matches_foreground_root_owner)
        $FinalSampleVisibleHwnds = @($VisibleWindows | ForEach-Object { [string]$_.hwnd_hex })

        $Samples.Add([pscustomobject][ordered]@{
                sample_index = $SampleIndex
                captured_at_utc = [string]$Topology.captured_at_utc
                foreground = $Topology.foreground
                window_count = [int]$Topology.window_count
                windows = @($Topology.windows)
            })

        foreach ($SettingsProcessId in @(Get-SettingsProcessIds)) {
            if ($SettingsProcessesBefore -notcontains $SettingsProcessId) {
                [void]$NewSettingsProcessIdsObserved.Add([int]$SettingsProcessId)
            }
        }
        if ($SettingsWatcherActive -and
            $SettingsWatcherProvider -eq "Win32_ProcessStartTrace") {
            $WatcherBatch = Receive-SettingsProcessStartEvents `
                -SourceIdentifier $SettingsWatcherSourceIdentifier
            if (-not [bool]$WatcherBatch.success) {
                $SettingsWatcherFailure = [string]$WatcherBatch.error
                $SettingsWatcherActive = $false
            }
            foreach ($StartEvent in @($WatcherBatch.events)) {
                $SettingsProcessStartEvents.Add($StartEvent)
                [void]$NewSettingsProcessIdsObserved.Add([int]$StartEvent.process_id)
            }
        }

        if ($SampleIndex + 1 -lt $SampleCount) {
            Start-Sleep -Milliseconds $IntervalMs
        }
    }
}
finally {
    # Freeze the measured interval before any post-boundary drain/snapshot.
    # Later observations are conservative: they may fail the gate, but cannot
    # move this boundary forward and create an unobserved launch window.
    $CaptureCompletedAt = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    if ($SettingsWatcherProvider -eq "continuous_process_poll" -and
        $null -ne $SettingsPollingJob) {
        Set-Content `
            -LiteralPath $SettingsPollingStopPath `
            -Value "stop" `
            -Encoding ascii
        $CompletedPollingJob = Wait-Job -Job $SettingsPollingJob -Timeout 10
        if ($null -eq $CompletedPollingJob) {
            $SettingsWatcherFailure = "continuous settings-process poller did not stop within 10 seconds."
            Stop-Job -Job $SettingsPollingJob -ErrorAction SilentlyContinue
        }
        else {
            $PollingResult = Receive-Job -Job $SettingsPollingJob -ErrorAction Stop
            if ($null -eq $PollingResult -or -not [bool]$PollingResult.success) {
                $SettingsWatcherFailure = if ($null -eq $PollingResult) {
                    "continuous settings-process poller returned no coverage result."
                }
                else {
                    [string]$PollingResult.failure
                }
            }
            else {
                $SettingsWatcherStoppedAt = [string]$PollingResult.stopped_at_utc
                $SettingsPollingCount = [int]$PollingResult.poll_count
                $SettingsPollingMaximumGapMs = [double]$PollingResult.maximum_gap_ms
                foreach ($StartEvent in @($PollingResult.events)) {
                    $SettingsProcessStartEvents.Add($StartEvent)
                    [void]$NewSettingsProcessIdsObserved.Add([int]$StartEvent.process_id)
                }
            }
        }
        Remove-Job -Job $SettingsPollingJob -Force -ErrorAction SilentlyContinue
    }
    elseif ($SettingsWatcherStartedSuccessfully) {
        try {
            $SettingsWatcher.Stop()
        }
        catch {
            $SettingsWatcherFailure = $_.Exception.Message
        }
        $SettingsWatcherStoppedAt = [DateTimeOffset]::UtcNow.ToString(
            "o",
            [Globalization.CultureInfo]::InvariantCulture)
        $WatcherBatch = Receive-SettingsProcessStartEvents `
            -SourceIdentifier $SettingsWatcherSourceIdentifier
        if (-not [bool]$WatcherBatch.success) {
            $SettingsWatcherFailure = [string]$WatcherBatch.error
        }
        foreach ($StartEvent in @($WatcherBatch.events)) {
            $SettingsProcessStartEvents.Add($StartEvent)
            [void]$NewSettingsProcessIdsObserved.Add([int]$StartEvent.process_id)
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($SettingsWatcherStoppedAt)) {
        $SettingsWatcherStoppedAt = [DateTimeOffset]::UtcNow.ToString(
            "o",
            [Globalization.CultureInfo]::InvariantCulture)
    }
    Unregister-Event `
        -SourceIdentifier $SettingsWatcherSourceIdentifier `
        -ErrorAction SilentlyContinue
    Get-Event `
        -SourceIdentifier $SettingsWatcherSourceIdentifier `
        -ErrorAction SilentlyContinue |
        Remove-Event -ErrorAction SilentlyContinue
    if ($null -ne $SettingsWatcher) {
        $SettingsWatcher.Dispose()
    }
    Remove-Item `
        -LiteralPath $SettingsPollingReadyPath, $SettingsPollingStopPath `
        -Force `
        -ErrorAction SilentlyContinue
    $SettingsProcessesAfter = @(Get-SettingsProcessIds)
    foreach ($SettingsProcessId in $SettingsProcessesAfter) {
        if ($SettingsProcessesBefore -notcontains $SettingsProcessId) {
            [void]$NewSettingsProcessIdsObserved.Add([int]$SettingsProcessId)
        }
    }
    if ($SettingsLaunchSentinelHeld) {
        try {
            $SettingsLaunchSentinelSignaled = $SettingsLaunchSentinel.WaitOne(0)
            $SettingsLaunchSentinelCheckedAt = [DateTimeOffset]::UtcNow.ToString(
                "o",
                [Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            $SettingsLaunchSentinelFailure = $_.Exception.Message
        }
    }
    if ($null -ne $SettingsLaunchSentinel) {
        $SettingsLaunchSentinel.Dispose()
    }
    if ($CaptureMutexHeld -and $null -ne $CaptureMutex) {
        $CaptureMutex.ReleaseMutex()
    }
    if ($null -ne $CaptureMutex) {
        $CaptureMutex.Dispose()
    }
}

$SettingsProcessesStarted = @($NewSettingsProcessIdsObserved | Sort-Object)
$SettingsWatcherCoverageComplete = [bool](
    $SettingsWatcherProvider -eq "Win32_ProcessStartTrace" -and
    -not [string]::IsNullOrWhiteSpace($SettingsWatcherStartedAt) -and
    -not [string]::IsNullOrWhiteSpace($SettingsWatcherStoppedAt) -and
    [string]::IsNullOrWhiteSpace($SettingsWatcherFailure))
$SettingsLaunchSentinelCoverageComplete = [bool](
    $SettingsLaunchSentinelCreatedNew -and
    $SettingsLaunchSentinelInitializedUnsignaled -and
    $SettingsLaunchSentinelHeld -and
    -not [string]::IsNullOrWhiteSpace($SettingsLaunchSentinelInitializedAt) -and
    -not [string]::IsNullOrWhiteSpace($SettingsLaunchSentinelCheckedAt) -and
    [string]::IsNullOrWhiteSpace($SettingsLaunchSentinelFailure))
$MachineTopologyReady =
    $SamplesWithVisibleWindow -gt 0 -and
    $SamplesWithToolbarCapture -gt 0 -and
    $FinalSampleVisibleToolbarCount -eq 1 -and
    -not $FinalSampleHasToolbarCapture -and
    $FinalSampleOwnerMatchesForeground -and
    $MaximumVisibleWindows -le 1 -and
    $SamplesWithMultipleVisibleWindows -eq 0 -and
    $SamplesWithForegroundOwnerMismatch -eq 0 -and
    $SamplesWithUnexpectedHostProcess -eq 0 -and
    $DistinctVisibleHwnds.Count -le 1 -and
    $SettingsLaunchSentinelCoverageComplete -and
    -not $SettingsLaunchSentinelSignaled -and
    $SettingsProcessesStarted.Count -eq 0

$Report = [pscustomobject][ordered]@{
    schema_version = 1
    evidence_kind = "m10_toolbar_topology_capture"
    captured_at_utc = $CaptureStartedAt.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    completed_at_utc = $CaptureCompletedAt
    privacy_note = "Captures toolbar topology, process identity, geometry, ownership, foreground relation, and capture state only. It does not read window titles, typed content, composition content, or keystrokes."
    host = [pscustomobject][ordered]@{
        id = $HostId
        electron_host_name = if ($HostId -eq "electron") { $ElectronHostName } else { "" }
        expected_process_name = $ExpectedHostProcessName
    }
    sampling = [pscustomobject][ordered]@{
        requested_sample_count = $SampleCount
        interval_ms = $IntervalMs
        captured_sample_count = $Samples.Count
    }
    machine_observed = [pscustomobject][ordered]@{
        samples_with_visible_toolbar = $SamplesWithVisibleWindow
        samples_with_toolbar_capture = $SamplesWithToolbarCapture
        maximum_visible_toolbar_windows = $MaximumVisibleWindows
        samples_with_multiple_visible_toolbars = $SamplesWithMultipleVisibleWindows
        samples_with_foreground_owner_mismatch = $SamplesWithForegroundOwnerMismatch
        samples_with_unexpected_host_process = $SamplesWithUnexpectedHostProcess
        observed_visible_process_names = @($ObservedVisibleProcessNames | Sort-Object)
        distinct_visible_hwnds = @($DistinctVisibleHwnds | Sort-Object)
        sampled_visible_hwnd_stable = ($DistinctVisibleHwnds.Count -le 1)
        final_sample_visible_toolbar_count = $FinalSampleVisibleToolbarCount
        final_sample_visible_hwnds = @($FinalSampleVisibleHwnds)
        final_sample_has_toolbar_capture = [bool]$FinalSampleHasToolbarCapture
        final_sample_owner_matches_foreground_root = [bool]$FinalSampleOwnerMatchesForeground
        settings_process_ids_before = @($SettingsProcessesBefore)
        settings_process_ids_after = @($SettingsProcessesAfter)
        settings_process_ids_started_during_capture = @($SettingsProcessesStarted)
        settings_launch_sentinel = [pscustomobject][ordered]@{
            name = $SettingsLaunchSentinelName
            capture_mutex_name = $CaptureMutexName
            capture_mutex_held = $CaptureMutexHeld
            created_new = $SettingsLaunchSentinelCreatedNew
            initialized_unsignaled_before_initial_process_snapshot =
                $SettingsLaunchSentinelInitializedUnsignaled
            held_for_complete_capture = $SettingsLaunchSentinelHeld
            initialized_at_utc = $SettingsLaunchSentinelInitializedAt
            checked_at_utc = $SettingsLaunchSentinelCheckedAt
            signaled = $SettingsLaunchSentinelSignaled
            coverage_complete = $SettingsLaunchSentinelCoverageComplete
            failure = $SettingsLaunchSentinelFailure
        }
        settings_process_start_watcher = [pscustomobject][ordered]@{
            provider = $SettingsWatcherProvider
            primary_provider_failure = $SettingsWatcherPrimaryProviderFailure
            started_at_utc = $SettingsWatcherStartedAt
            stopped_at_utc = $SettingsWatcherStoppedAt
            coverage_complete = $SettingsWatcherCoverageComplete
            failure = $SettingsWatcherFailure
            requested_poll_interval_ms = if (
                $SettingsWatcherProvider -eq "continuous_process_poll") {
                $SettingsPollingIntervalMs
            }
            else { 0 }
            poll_count = $SettingsPollingCount
            maximum_poll_gap_ms = $SettingsPollingMaximumGapMs
            events = @($SettingsProcessStartEvents)
        }
        topology_ready = [bool]$MachineTopologyReady
    }
    operator_report = [pscustomobject][ordered]@{
        provenance = "not collected during capture; attach the after-the-fact user report with finalize-m10-toolbar-session.ps1"
        verdict = "pending"
    }
    gate_ready = $false
    samples = @($Samples)
}

$Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $FullOutputPath -Encoding utf8
$CaptureHash = (Get-FileHash -LiteralPath $FullOutputPath -Algorithm SHA256).Hash
$Receipt = [pscustomobject][ordered]@{
    schema_version = 1
    evidence_kind = "m10_toolbar_capture_receipt"
    created_at_utc = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    capture_file_name = [IO.Path]::GetFileName($FullOutputPath)
    capture_sha256 = $CaptureHash
    capture_completed_at_utc = [string]$Report.completed_at_utc
    settings_launch_sentinel_coverage_complete = $SettingsLaunchSentinelCoverageComplete
    settings_launch_sentinel_signaled = $SettingsLaunchSentinelSignaled
    settings_process_start_watcher_coverage_complete = $SettingsWatcherCoverageComplete
}
$Receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8
Write-Host "M10 toolbar topology session written to $FullOutputPath"
Write-Host "Capture receipt written to $ReceiptPath (SHA256=$CaptureHash)"
Write-Host "Settings-launch sentinel complete=$SettingsLaunchSentinelCoverageComplete signaled=$SettingsLaunchSentinelSignaled"
Write-Host "Settings-start coverage provider=$SettingsWatcherProvider complete=$SettingsWatcherCoverageComplete failure=$SettingsWatcherFailure primary-failure=$SettingsWatcherPrimaryProviderFailure"
Write-Host "Samples=$($Samples.Count) visible-max=$MaximumVisibleWindows topology-ready=$MachineTopologyReady operator-verdict=pending"
