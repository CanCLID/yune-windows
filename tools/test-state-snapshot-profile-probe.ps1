param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

$TempRoot = Join-Path $env:TEMP "yune-windows\profile-probe-test"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $TempRoot | Out-Null

$InstallDir = Join-Path $TempRoot "deleted-install-dir"
$Probe = Join-Path $TempRoot "YuneWindowsProfileTool.cmd"
@"
@echo {"registered":false,"active":false}
"@ | Out-File -LiteralPath $Probe -Encoding ascii

$Snapshot = Get-YuneWindowsStateSnapshot `
    -InstallDir $InstallDir `
    -ProfileToolPath $Probe

if ($Snapshot.install_dir_exists -ne $false) {
    throw "synthetic deleted install dir should not exist"
}
if ($Snapshot.profile_state_verified -ne $true) {
    throw "snapshot must mark external profile probe output as verified"
}
if ($Snapshot.profile_state_source -ne [System.IO.Path]::GetFullPath($Probe)) {
    throw "snapshot did not record the external profile probe source"
}
if ($Snapshot.profile_state -notmatch '"registered":false') {
    throw "snapshot did not capture fake profile probe output"
}

$Snapshot["server_processes"] = @()
$Validation = Test-YuneWindowsCleanupState -Snapshot $Snapshot -RequireProfileState
if ($Validation.pass -ne $true) {
    throw "cleanup validation should pass with verified inactive profile state"
}

$FailingProbe = Join-Path $TempRoot "FailingYuneWindowsProfileTool.cmd"
@"
@echo failed to query profile state
@exit /b 7
"@ | Out-File -LiteralPath $FailingProbe -Encoding ascii

$FailedProbeSnapshot = Get-YuneWindowsStateSnapshot `
    -InstallDir $InstallDir `
    -ProfileToolPath $FailingProbe

if ($FailedProbeSnapshot.profile_state_verified -ne $false) {
    throw "snapshot must not mark failed profile probe output as verified"
}
if ($FailedProbeSnapshot.profile_state_error -notmatch "exit code 7") {
    throw "snapshot must record the failed profile probe exit code"
}

$FailedProbeValidation = Test-YuneWindowsCleanupState -Snapshot $FailedProbeSnapshot -RequireProfileState
if ($FailedProbeValidation.pass -ne $false -or
    ($FailedProbeValidation.issues -notcontains "YuneWindows TSF profile state was not verified")) {
    throw "cleanup validation must fail when a profile probe exits nonzero"
}

$InvalidJsonProbe = Join-Path $TempRoot "InvalidJsonYuneWindowsProfileTool.cmd"
@"
@echo not json
"@ | Out-File -LiteralPath $InvalidJsonProbe -Encoding ascii

$InvalidJsonSnapshot = Get-YuneWindowsStateSnapshot `
    -InstallDir $InstallDir `
    -ProfileToolPath $InvalidJsonProbe

if ($InvalidJsonSnapshot.profile_state_verified -ne $false) {
    throw "snapshot must not mark invalid profile probe JSON as verified"
}
if ($InvalidJsonSnapshot.profile_state_error -notmatch "invalid JSON") {
    throw "snapshot must record invalid profile probe JSON as the verification error"
}

$InvalidJsonValidation = Test-YuneWindowsCleanupState -Snapshot $InvalidJsonSnapshot -RequireProfileState
if ($InvalidJsonValidation.pass -ne $false -or
    ($InvalidJsonValidation.issues -notcontains "YuneWindows TSF profile state was not verified") -or
    ($InvalidJsonValidation.issues -notcontains "YuneWindows TSF profile state could not be parsed")) {
    throw "cleanup validation must fail when profile state JSON is invalid"
}

$Unverified = [pscustomobject]@{
    install_dir = $InstallDir
    install_dir_exists = $false
    profile_state = $null
    profile_state_verified = $false
    server_processes = @()
}
$UnverifiedResult = Test-YuneWindowsCleanupState -Snapshot $Unverified -RequireProfileState
if ($UnverifiedResult.pass -ne $false -or
    ($UnverifiedResult.issues -notcontains "YuneWindows TSF profile state was not verified")) {
    throw "cleanup validation must fail when profile state was not verified"
}

Write-Host "State snapshot supports external profile probe for post-cleanup verification."
