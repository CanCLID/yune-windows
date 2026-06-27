param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
if (-not (Test-Path -LiteralPath $SupportPath)) {
    throw "missing live smoke support script: $SupportPath"
}

. $SupportPath

function Test-IsAdministrator {
    return $true
}

$TempDir = Join-Path $env:TEMP "yune-windows\p2-win01-live-preflight-machine-state-checked-test"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Force $TempDir | Out-Null

$YuneRoot = Join-Path $TempDir "yune"
$RimeDll = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
$SchemaDir = Join-Path $YuneRoot "apps\yune-web\public\schema"
New-Item -ItemType Directory -Force (Split-Path -Parent $RimeDll) | Out-Null
New-Item -ItemType File -Force $RimeDll | Out-Null
New-Item -ItemType Directory -Force $SchemaDir | Out-Null

$InstallDir = Join-Path $TempDir "fresh-install-target"

$UncheckedResiduePath = Join-Path $TempDir "unchecked-current-residue.json"
[ordered]@{
    machine_state_checked = $false
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $UncheckedResiduePath -Encoding utf8

$Report = New-P2Win01PreflightReport `
    -YuneRoot $YuneRoot `
    -InstallDir $InstallDir `
    -CurrentResiduePath $UncheckedResiduePath

if ($Report.machine_state_checked -ne $false) {
    throw "preflight report must preserve machine_state_checked=false from supplied residue evidence."
}
if ($Report.ready_for_live_smoke -ne $false) {
    throw "preflight report must not be ready when supplied residue evidence says machine_state_checked=false."
}

$CheckedResiduePath = Join-Path $TempDir "checked-current-residue.json"
[ordered]@{
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $CheckedResiduePath -Encoding utf8

$CheckedReport = New-P2Win01PreflightReport `
    -YuneRoot $YuneRoot `
    -InstallDir $InstallDir `
    -CurrentResiduePath $CheckedResiduePath

if ($CheckedReport.ready_for_live_smoke -ne $true) {
    throw "clean checked residue evidence should allow ready_for_live_smoke=true in the synthetic preflight."
}

Write-Host "Live preflight readiness requires machine_state_checked=true residue evidence."
