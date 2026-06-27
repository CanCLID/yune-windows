param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$LiveSmokePath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$InstallPath = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"
$BriefPath = Join-Path $RepoRoot "tools\write-p2-win01-approval-brief.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportPath
$LiveSmokeSource = Get-Content -Raw -LiteralPath $LiveSmokePath
$InstallSource = Get-Content -Raw -LiteralPath $InstallPath
$BriefSource = Get-Content -Raw -LiteralPath $BriefPath

foreach ($Required in @(
        '[string]$CurrentResiduePath = ""',
        '[switch]$RefreshCurrentResidue',
        '[string]$ApprovalNote = ""',
        'Preflight machine-state inspection requires -CurrentResiduePath or -RefreshCurrentResidue.',
        'elseif ($RefreshCurrentResidue.IsPresent)',
        'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote',
        'machine_residue_source = $MachineResidueSource'
    )) {
    if (-not $SupportSource.Contains($Required)) {
        throw "preflight support is missing residue-source guard pattern: $Required"
    }
}

foreach ($Script in @(
        @{ Name = "run-p2-win01-live-smoke.ps1"; Source = $LiveSmokeSource },
        @{ Name = "install-yune-windows-ime.ps1"; Source = $InstallSource }
    )) {
    foreach ($Required in @(
            '[string]$CurrentResiduePath = ""',
            '[switch]$RefreshCurrentResidue',
            '[string]$ApprovalNote = ""',
            '-CurrentResiduePath $CurrentResiduePath',
            '-ApprovalNote $ApprovalNote',
            '-RefreshCurrentResidue:$($RefreshCurrentResidue.IsPresent)'
        )) {
        if (-not $Script.Source.Contains($Required)) {
            throw "$($Script.Name) is missing explicit preflight residue-source pattern: $Required"
        }
    }
}

foreach ($Required in @(
        '-RefreshCurrentResidue',
        '-ApprovalNote ''<current-session approval note>'''
    )) {
    if (-not $BriefSource.Contains($Required)) {
        throw "approval brief command is missing explicit preflight residue-source pattern: $Required"
    }
}

$CurrentResiduePathIndex = $SupportSource.IndexOf('if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath))')
$RefreshIndex = $SupportSource.IndexOf('elseif ($RefreshCurrentResidue.IsPresent)')
$ApprovalNoteIndex = $SupportSource.IndexOf(
    'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote',
    $RefreshIndex)
$DetectorIndex = $SupportSource.IndexOf(
    'Get-YuneWindowsMachineResidue -InstallDir $InstallRoot',
    $RefreshIndex)
if ($CurrentResiduePathIndex -lt 0 -or $RefreshIndex -lt 0 -or $ApprovalNoteIndex -lt 0 -or $DetectorIndex -lt 0) {
    throw "preflight support is missing residue-source branch anchors."
}
if ($ApprovalNoteIndex -lt $RefreshIndex -or $ApprovalNoteIndex -gt $DetectorIndex) {
    throw "preflight support must require an approval note before explicit machine-residue refresh."
}
if ($DetectorIndex -lt $RefreshIndex) {
    throw "preflight support must not call Get-YuneWindowsMachineResidue before the explicit refresh branch."
}

. $SupportPath

$TempDir = Join-Path $env:TEMP "yune-windows\p2-win01-live-preflight-residue-source-guard-test"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$ResiduePath = Join-Path $TempDir "current-residue.json"
$Residue = [ordered]@{
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6
$Residue | Out-File -LiteralPath $ResiduePath -Encoding utf8

$Report = New-P2Win01PreflightReport `
    -YuneRoot (Join-Path $TempDir "missing-yune") `
    -InstallDir (Join-Path $TempDir "install-target") `
    -CurrentResiduePath $ResiduePath

if ($Report.machine_residue_source -ne [System.IO.Path]::GetFullPath($ResiduePath)) {
    throw "preflight report did not record supplied residue source."
}
if ($Report.machine_state_checked -ne $true) {
    throw "preflight report did not preserve machine_state_checked=true from supplied residue evidence."
}
if (@($Report.machine_state_issues).Count -ne 0 -or @($Report.filesystem_leftovers).Count -ne 0) {
    throw "preflight report did not use supplied empty residue arrays."
}

$StringTypedResiduePath = Join-Path $TempDir "string-typed-current-residue.json"
[ordered]@{
    machine_state_checked = "true"
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $StringTypedResiduePath -Encoding utf8

$StringTypedResidueThrew = $false
try {
    New-P2Win01PreflightReport `
        -YuneRoot (Join-Path $TempDir "missing-yune") `
        -InstallDir (Join-Path $TempDir "install-target") `
        -CurrentResiduePath $StringTypedResiduePath | Out-Null
}
catch {
    $StringTypedResidueThrew = $_.Exception.Message -match "machine_state_checked must be a JSON boolean"
}
if (-not $StringTypedResidueThrew) {
    throw "preflight report accepted string-typed machine_state_checked residue evidence."
}

$MissingCheckedResiduePath = Join-Path $TempDir "missing-checked-current-residue.json"
[ordered]@{
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $MissingCheckedResiduePath -Encoding utf8

$MissingCheckedResidueThrew = $false
try {
    New-P2Win01PreflightReport `
        -YuneRoot (Join-Path $TempDir "missing-yune") `
        -InstallDir (Join-Path $TempDir "install-target") `
        -CurrentResiduePath $MissingCheckedResiduePath | Out-Null
}
catch {
    $MissingCheckedResidueThrew = $_.Exception.Message -match "machine_state_checked must be a JSON boolean"
}
if (-not $MissingCheckedResidueThrew) {
    throw "preflight report accepted supplied residue evidence without machine_state_checked."
}

$GuardFailed = $false
try {
    New-P2Win01PreflightReport `
        -YuneRoot (Join-Path $TempDir "missing-yune") `
        -InstallDir (Join-Path $TempDir "install-target") | Out-Null
}
catch {
    $GuardFailed = $_.Exception.Message -match "Preflight machine-state inspection requires"
}
if (-not $GuardFailed) {
    throw "preflight report must reject implicit machine-residue inspection."
}

$RefreshWithoutNoteFailed = $false
try {
    New-P2Win01PreflightReport `
        -YuneRoot (Join-Path $TempDir "missing-yune") `
        -InstallDir (Join-Path $TempDir "install-target") `
        -RefreshCurrentResidue | Out-Null
}
catch {
    $RefreshWithoutNoteFailed = $_.Exception.Message -match "Approved live smoke requires -ApprovalNote"
}
if (-not $RefreshWithoutNoteFailed) {
    throw "preflight report must reject explicit machine-residue refresh without an approval note."
}

$script:RefreshDetectorCalled = $false
function Get-YuneWindowsMachineResidue {
    param([string]$InstallDir)

    $script:RefreshDetectorCalled = $true
    return [pscustomobject]@{
        machine_state_issues = @()
        filesystem_leftovers = @()
    }
}

$RefreshReport = New-P2Win01PreflightReport `
    -YuneRoot (Join-Path $TempDir "missing-yune") `
    -InstallDir (Join-Path $TempDir "install-target") `
    -RefreshCurrentResidue `
    -ApprovalNote "Current session explicitly approved non-mutating test refresh."

if (-not $script:RefreshDetectorCalled) {
    throw "preflight report did not call the explicit refresh residue detector."
}
if ($RefreshReport.machine_residue_source -ne "Get-YuneWindowsMachineResidue") {
    throw "preflight report did not record explicit refresh residue source."
}
if ($RefreshReport.machine_state_checked -ne $true) {
    throw "preflight report did not stamp machine_state_checked=true for explicit refresh evidence."
}
if (@($RefreshReport.machine_state_issues).Count -ne 0 -or @($RefreshReport.filesystem_leftovers).Count -ne 0) {
    throw "preflight report did not use refreshed empty residue arrays."
}

$SelfReferentialPreflightPath = Join-Path $TempDir "self-referential-live-preflight.json"
[ordered]@{
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $SelfReferentialPreflightPath -Encoding utf8

$SelfReferentialPreflightFailed = $false
try {
    Write-P2Win01PreflightReport `
        -Path $SelfReferentialPreflightPath `
        -YuneRoot (Join-Path $TempDir "missing-yune") `
        -InstallDir (Join-Path $TempDir "install-target") `
        -CurrentResiduePath $SelfReferentialPreflightPath | Out-Null
}
catch {
    $SelfReferentialPreflightFailed = $_.Exception.Message -match "Preflight output path must not also be the current-residue input"
}
if (-not $SelfReferentialPreflightFailed) {
    throw "preflight writer accepted the output file as its own current-residue evidence."
}

Write-Host "Live/install preflight require explicit machine-residue source evidence."
