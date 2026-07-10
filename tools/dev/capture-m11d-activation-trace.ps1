param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [ValidateRange(1, 5000)][int]$MaxEvents = 500
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$TopologyScript = Join-Path $RepoRoot "tools\dev\capture-language-bar-topology.ps1"
$LogPath = Join-Path $InstallDir "logs\tsf-events.log"

$AllowedFields = @(
    "event",
    "sequence",
    "utc_filetime",
    "monotonic_ms",
    "pid",
    "tid",
    "process_nonce",
    "buffer_length",
    "candidate_count",
    "error_code",
    "generation",
    "owner",
    "foreground",
    "foreground_match",
    "state_revision",
    "toggle_token",
    "disposition",
    "outcome",
    "press_count",
    "desired",
    "attempts",
    "reason"
)
$AllowedFieldSet = @{}
foreach ($AllowedField in $AllowedFields) {
    $AllowedFieldSet[$AllowedField] = $true
}

$Events = [Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
    $Lines = @(Get-Content -LiteralPath $LogPath -Tail $MaxEvents)
    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }
        $Record = [ordered]@{}
        foreach ($Token in ($Line -split '\s+')) {
            $Separator = $Token.IndexOf('=')
            if ($Separator -le 0) {
                continue
            }
            $Name = $Token.Substring(0, $Separator)
            if (-not $AllowedFieldSet.ContainsKey($Name)) {
                continue
            }
            $Record[$Name] = $Token.Substring($Separator + 1)
        }
        if ($Record.Contains("event")) {
            $Events.Add([pscustomobject]$Record)
        }
    }
}

$TopologyText = (& $TopologyScript | Out-String).Trim()
$Topology = if ([string]::IsNullOrWhiteSpace($TopologyText)) {
    $null
} else {
    $TopologyText | ConvertFrom-Json
}

[pscustomobject][ordered]@{
    schema_version = 1
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    privacy_note = "Captures allowlisted numeric/reason activation fields and toolbar topology only; no titles, typed text, composition text, or arbitrary key sequences are read."
    source_log_present = [bool](Test-Path -LiteralPath $LogPath -PathType Leaf)
    source_log_path = $LogPath
    event_count = $Events.Count
    events = @($Events)
    topology = $Topology
} | ConvertTo-Json -Depth 10
