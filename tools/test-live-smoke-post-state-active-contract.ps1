param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

if (-not (Get-Command Assert-YuneWindowsActiveInstalledSnapshot -ErrorAction SilentlyContinue)) {
    throw "live smoke support must expose Assert-YuneWindowsActiveInstalledSnapshot"
}

$OutputDir = Join-Path $env:TEMP "yune-windows\m01-post-state-active-contract-test"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$ActiveSnapshotPath = Join-Path $OutputDir "active-post-state.json"
@"
{
  "captured_at": "2026-06-26T18:40:00.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": []
}
"@ | Out-File -LiteralPath $ActiveSnapshotPath -Encoding utf8

Assert-YuneWindowsActiveInstalledSnapshot `
    -Path $ActiveSnapshotPath `
    -Context "active synthetic post-state"

$InactiveSnapshotPath = Join-Path $OutputDir "inactive-post-state.json"
@"
{
  "captured_at": "2026-06-26T18:40:00.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":false}",
  "server_processes": []
}
"@ | Out-File -LiteralPath $InactiveSnapshotPath -Encoding utf8

$RejectedInactiveSnapshot = $false
try {
    Assert-YuneWindowsActiveInstalledSnapshot `
        -Path $InactiveSnapshotPath `
        -Context "inactive synthetic post-state"
}
catch {
    $RejectedInactiveSnapshot = $true
}
if (-not $RejectedInactiveSnapshot) {
    throw "post-state validator should reject inactive YuneWindows profile snapshots"
}

$StringTypedSnapshotPath = Join-Path $OutputDir "string-typed-post-state.json"
@"
{
  "captured_at": "2026-06-26T18:40:00.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": "true",
  "profile_tool_exists": "true",
  "profile_state_verified": "true",
  "profile_state": "{\"registered\":\"true\",\"active\":\"true\"}",
  "server_processes": []
}
"@ | Out-File -LiteralPath $StringTypedSnapshotPath -Encoding utf8

$RejectedStringTypedSnapshot = $false
try {
    Assert-YuneWindowsActiveInstalledSnapshot `
        -Path $StringTypedSnapshotPath `
        -Context "string-typed synthetic post-state"
}
catch {
    $RejectedStringTypedSnapshot = $true
}
if (-not $RejectedStringTypedSnapshot) {
    throw "post-state validator should reject string-typed YuneWindows state booleans"
}

foreach ($RelativePath in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    $Path = Join-Path $RepoRoot $RelativePath
    $Source = Get-Content -Raw -LiteralPath $Path
    $Name = Split-Path -Leaf $Path
    $HelperPattern = 'function\s+Write-PostSmokeStateSnapshot(?s:.*?)' +
        'Write-YuneWindowsStateSnapshot(?s:.*?)' +
        'Assert-YuneWindowsActiveInstalledSnapshot(?s:.*?)' +
        '\$script:PostStateSnapshotWritten\s*=\s*\$true'
    if ($Source -notmatch $HelperPattern) {
        throw "$Name must validate the app-specific post-smoke state snapshot before marking it written."
    }

    $SuccessPattern = '\$CurrentStage\s*=\s+"post-state"(?s:.*?)' +
        'Write-PostSmokeStateSnapshot(?s:.*?)' +
        'Write-TextSmokeResult(?s:.*?)-Status\s+"passed"'
    if ($Source -notmatch $SuccessPattern) {
        throw "$Name must write and validate the active installed post-smoke state snapshot before writing a passed result."
    }
}

Write-Host "Live app smokes validate active installed post-smoke state before reporting a passing result."
