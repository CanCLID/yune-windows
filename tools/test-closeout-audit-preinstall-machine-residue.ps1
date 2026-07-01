param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-preinstall-machine-residue-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function New-CompleteFixture([string]$Name) {
    $FixtureDir = Join-Path $OutputDir $Name
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $FixtureDir | Out-Null
    return Join-Path $FixtureDir "evidence"
}

function Write-PreinstallState([string]$EvidenceRoot, [string]$Json) {
    $Path = Join-Path $EvidenceRoot "m01\installer\pre-install-state.json"
    $Json | Out-File -LiteralPath $Path -Encoding utf8
}

function Get-InstallGateStatus([string]$EvidenceRoot, [string]$Name) {
    $JsonPath = Join-Path $OutputDir "$Name.json"
    $MarkdownPath = Join-Path $OutputDir "$Name.md"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    $Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    return ($Audit.gates |
        Where-Object { $_.id -eq "fresh-install-registration-activation" } |
        Select-Object -First 1).status
}

$MissingMachineEvidence = New-CompleteFixture "missing-machine-fixture"
Write-PreinstallState $MissingMachineEvidence @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": []
}
"@
$MissingStatus = Get-InstallGateStatus $MissingMachineEvidence "audit-missing-machine"
if ($MissingStatus -ne "invalid") {
    throw "audit should reject fresh-install evidence when pre-install machine-residue state was not checked, got $MissingStatus"
}

$DirtyMachineEvidence = New-CompleteFixture "dirty-machine-fixture"
Write-PreinstallState $DirtyMachineEvidence @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": [],
  "machine_state_checked": true,
  "machine_state_issues": ["COM CLSID registry key remains"],
  "filesystem_leftovers": []
}
"@
$DirtyMachineStatus = Get-InstallGateStatus $DirtyMachineEvidence "audit-dirty-machine"
if ($DirtyMachineStatus -ne "invalid") {
    throw "audit should reject fresh-install evidence when pre-install machine-state residue remains, got $DirtyMachineStatus"
}

$DirtyFilesystemEvidence = New-CompleteFixture "dirty-filesystem-fixture"
Write-PreinstallState $DirtyFilesystemEvidence @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": [],
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": ["C:\\Windows\\System32\\YuneWindows.dll.old.0"]
}
"@
$DirtyFilesystemStatus = Get-InstallGateStatus $DirtyFilesystemEvidence "audit-dirty-filesystem"
if ($DirtyFilesystemStatus -ne "invalid") {
    throw "audit should reject fresh-install evidence when pre-install filesystem leftovers remain, got $DirtyFilesystemStatus"
}

Write-Host "Closeout audit rejects pre-install machine-state and filesystem residue."
