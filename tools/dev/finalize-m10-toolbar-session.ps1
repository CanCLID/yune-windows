param(
    [Parameter(Mandatory = $true)]
    [string]$CapturePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 1000)]
    [int]$GripDragsCompleted,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 1000)]
    [int]$SettingsSegmentDragsCompleted,

    [Parameter(Mandatory = $true)]
    [ValidateSet("pass", "fail")]
    [string]$VisualCopiesOrAfterimagesAbsent,

    [Parameter(Mandatory = $true)]
    [ValidateSet("pass", "fail")]
    [string]$FocusNeverStolen,

    [Parameter(Mandatory = $true)]
    [ValidateSet("pass", "fail")]
    [string]$SettingsDragDidNotActivate,

    [Parameter(Mandatory = $true)]
    [ValidateSet("pass", "fail")]
    [string]$CantoneseOnly,

    [Parameter(Mandatory = $true)]
    [ValidateSet("pass", "fail")]
    [string]$PositionPersistedAfterFocus,

    [Parameter(Mandatory = $true)]
    [ValidateSet("pass", "fail")]
    [string]$PositionPersistedAfterHostRestart,

    [string]$OperatorNote = ""
)

$ErrorActionPreference = "Stop"

$FullCapturePath = [IO.Path]::GetFullPath($CapturePath)
$FullOutputPath = [IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $FullCapturePath -PathType Leaf)) {
    throw "capture file does not exist: $FullCapturePath"
}
$FullReceiptPath = $FullCapturePath + ".receipt.json"
if (-not (Test-Path -LiteralPath $FullReceiptPath -PathType Leaf)) {
    throw "capture receipt does not exist: $FullReceiptPath"
}
if ([IO.Path]::GetExtension($FullOutputPath) -ne ".json") {
    throw "-OutputPath must name a .json file."
}
if ([string]::Equals(
        $FullCapturePath,
        $FullOutputPath,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "-OutputPath must not overwrite the immutable capture file."
}
$CaptureDirectory = Split-Path -Parent $FullCapturePath
$OutputDirectory = Split-Path -Parent $FullOutputPath
if (-not [string]::Equals(
        $CaptureDirectory,
        $OutputDirectory,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "capture and finalized session must be sibling files so the SHA-pinned source remains auditable."
}

try {
    $Capture = Get-Content -Raw -LiteralPath $FullCapturePath | ConvertFrom-Json
}
catch {
    throw "capture file is not valid JSON: $($_.Exception.Message)"
}
if ([int]$Capture.schema_version -ne 1 -or
    $Capture.evidence_kind -ne "m10_toolbar_topology_capture" -or
    $Capture.operator_report.verdict -ne "pending" -or
    [bool]$Capture.gate_ready) {
    throw "capture file is not an immutable pending M10 topology capture."
}

$CaptureHash = (Get-FileHash -LiteralPath $FullCapturePath -Algorithm SHA256).Hash
try {
    $CaptureReceipt = Get-Content -Raw -LiteralPath $FullReceiptPath |
        ConvertFrom-Json
}
catch {
    throw "capture receipt is not valid JSON: $($_.Exception.Message)"
}
if ([int]$CaptureReceipt.schema_version -ne 1 -or
    $CaptureReceipt.evidence_kind -ne "m10_toolbar_capture_receipt" -or
    $CaptureReceipt.capture_file_name -ne [IO.Path]::GetFileName($FullCapturePath) -or
    $CaptureReceipt.capture_sha256 -ne $CaptureHash -or
    $CaptureReceipt.capture_completed_at_utc -ne [string]$Capture.completed_at_utc -or
    [bool]$CaptureReceipt.settings_launch_sentinel_coverage_complete -ne
        [bool]$Capture.machine_observed.settings_launch_sentinel.coverage_complete -or
    [bool]$CaptureReceipt.settings_launch_sentinel_signaled -ne
        [bool]$Capture.machine_observed.settings_launch_sentinel.signaled) {
    throw "capture receipt does not bind the exact completed capture file."
}
$ReceiptHash = (Get-FileHash -LiteralPath $FullReceiptPath -Algorithm SHA256).Hash
$TotalReportedDrags = $GripDragsCompleted + $SettingsSegmentDragsCompleted
$OperatorReportComplete =
    $GripDragsCompleted -ge 10 -and
    $SettingsSegmentDragsCompleted -ge 10 -and
    $VisualCopiesOrAfterimagesAbsent -eq "pass" -and
    $FocusNeverStolen -eq "pass" -and
    $SettingsDragDidNotActivate -eq "pass" -and
    $CantoneseOnly -eq "pass" -and
    $PositionPersistedAfterFocus -eq "pass" -and
    $PositionPersistedAfterHostRestart -eq "pass"
$NoSettingsProcessStarted =
    @($Capture.machine_observed.settings_process_ids_started_during_capture).Count -eq 0
$SettingsLaunchSentinelReady = [bool](
    $Capture.machine_observed.settings_launch_sentinel.coverage_complete -and
    -not $Capture.machine_observed.settings_launch_sentinel.signaled -and
    $CaptureReceipt.settings_launch_sentinel_coverage_complete -and
    -not $CaptureReceipt.settings_launch_sentinel_signaled)

$Report = [pscustomobject][ordered]@{
    schema_version = 1
    evidence_kind = "m10_toolbar_session_final"
    finalized_at_utc = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    privacy_note = "Attaches manually reported drag and visual verdicts to the SHA-256-pinned read-only topology capture. It does not resample windows or read titles, typed content, composition content, or keystrokes."
    source_capture = [pscustomobject][ordered]@{
        file_name = [IO.Path]::GetFileName($FullCapturePath)
        sha256 = $CaptureHash
        receipt_file_name = [IO.Path]::GetFileName($FullReceiptPath)
        receipt_sha256 = $ReceiptHash
        captured_at_utc = [string]$Capture.captured_at_utc
        completed_at_utc = [string]$Capture.completed_at_utc
    }
    host = $Capture.host
    sampling = $Capture.sampling
    machine_observed = $Capture.machine_observed
    operator_report = [pscustomobject][ordered]@{
        provenance = "manually reported after capture; not inferred from topology"
        grip_drags_completed = $GripDragsCompleted
        settings_segment_drags_completed = $SettingsSegmentDragsCompleted
        total_drags_completed = $TotalReportedDrags
        visual_copies_or_afterimages_absent = $VisualCopiesOrAfterimagesAbsent
        focus_never_stolen = $FocusNeverStolen
        settings_segment_drag_did_not_activate = $SettingsDragDidNotActivate
        cantonese_only_states_exercised = $CantoneseOnly
        position_persisted_after_focus_movement = $PositionPersistedAfterFocus
        position_persisted_after_host_restart = $PositionPersistedAfterHostRestart
        note = $OperatorNote
        report_complete = [bool]$OperatorReportComplete
    }
    gate_ready = [bool](
        [bool]$Capture.machine_observed.topology_ready -and
        $SettingsLaunchSentinelReady -and
        $NoSettingsProcessStarted -and
        $OperatorReportComplete)
}

$Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $FullOutputPath -Encoding utf8
Write-Host "M10 finalized toolbar session written to $FullOutputPath"
Write-Host "Capture-SHA256=$CaptureHash reported-drags=$TotalReportedDrags gate-ready=$($Report.gate_ready)"
