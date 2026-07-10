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

function Get-SettingsProcessIds {
    return @(
        Get-Process -Name "YuneWindowsSettings" -ErrorAction SilentlyContinue |
            Sort-Object Id |
            ForEach-Object { [int]$_.Id }
    )
}

$SettingsProcessesBefore = @(Get-SettingsProcessIds)
$NewSettingsProcessIdsObserved = [Collections.Generic.HashSet[int]]::new()
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

    if ($SampleIndex + 1 -lt $SampleCount) {
        Start-Sleep -Milliseconds $IntervalMs
    }
}

$SettingsProcessesAfter = @(Get-SettingsProcessIds)
foreach ($SettingsProcessId in $SettingsProcessesAfter) {
    if ($SettingsProcessesBefore -notcontains $SettingsProcessId) {
        [void]$NewSettingsProcessIdsObserved.Add([int]$SettingsProcessId)
    }
}
$SettingsProcessesStarted = @($NewSettingsProcessIdsObserved | Sort-Object)
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
    $SettingsProcessesStarted.Count -eq 0

$Report = [pscustomobject][ordered]@{
    schema_version = 1
    evidence_kind = "m10_toolbar_topology_capture"
    captured_at_utc = $CaptureStartedAt.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    completed_at_utc = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
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
Write-Host "M10 toolbar topology session written to $FullOutputPath"
Write-Host "Samples=$($Samples.Count) visible-max=$MaximumVisibleWindows topology-ready=$MachineTopologyReady operator-verdict=pending"
