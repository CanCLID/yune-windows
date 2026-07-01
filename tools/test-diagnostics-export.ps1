param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-diagnostics-test"
}

if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$InstallDir = Join-Path $OutputDir "install"
$LogDir = Join-Path $InstallDir "logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null
@(
    "event=key_down sequence=1 buffer_length=1 candidate_count=0",
    "event=candidate_update sequence=2 buffer_length=7 candidate_count=5",
    "event=commit_text sequence=3 buffer_length=7 candidate_count=5"
) | Out-File -LiteralPath (Join-Path $LogDir "tsf-events.log") -Encoding utf8

$ExportScript = Join-Path $RepoRoot "tools\export-yune-windows-diagnostics.ps1"
if (-not (Test-Path -LiteralPath $ExportScript)) {
    throw "missing diagnostics export script: $ExportScript"
}

$Bundle = & $ExportScript -OutputDir $OutputDir -InstallDir $InstallDir
$BundlePath = ($Bundle | Select-Object -Last 1).ToString().Trim()
if (-not (Test-Path -LiteralPath $BundlePath)) {
    throw "diagnostics bundle was not created: $BundlePath"
}
if ($BundlePath -notlike "*.zip") {
    throw "diagnostics bundle is not a zip archive: $BundlePath"
}

$InspectDir = Join-Path $OutputDir "inspect"
Expand-Archive -LiteralPath $BundlePath -DestinationPath $InspectDir -Force
$ManifestPath = Join-Path $InspectDir "manifest.json"
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "diagnostics bundle is missing manifest.json"
}

$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($Manifest.product -ne "Yune Windows") {
    throw "unexpected diagnostics product: $($Manifest.product)"
}
if ($Manifest.sensitive_context.typed_content_logs -ne $false) {
    throw "diagnostics manifest must state typed-content logs are disabled"
}
if ($Manifest.sensitive_context.ai_staging -ne $false) {
    throw "diagnostics manifest must state AI staging is disabled"
}
if ($Manifest.machine_state.registry_collected -ne $false) {
    throw "non-elevated diagnostics export must not collect registry state"
}
if ($Manifest.diagnostics_logs.included -ne $true) {
    throw "diagnostics manifest must state structural logs were included"
}
if ($Manifest.diagnostics_logs.typed_content_logs -ne $false) {
    throw "diagnostics log manifest must state typed-content logs are disabled"
}

$ExportedLog = Join-Path $InspectDir "logs\tsf-events.log"
if (-not (Test-Path -LiteralPath $ExportedLog)) {
    throw "diagnostics bundle did not include structural TSF log"
}
$LogText = Get-Content -Raw -LiteralPath $ExportedLog
if ($LogText -notmatch "event=key_down" -or $LogText -notmatch "candidate_count=5") {
    throw "diagnostics structural log is missing event names or counts"
}
if ($LogText -match "ngohaig|æˆ‘ä¿‚å€‹") {
    throw "diagnostics structural log must not include typed content"
}

$ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))
if (($LogText -match "ngohaig") -or
    ($LogText -match [regex]::Escape($ExpectedCommit))) {
    throw "diagnostics structural log must not include typed content"
}

Write-Host "Diagnostics export smoke passed: $BundlePath"
