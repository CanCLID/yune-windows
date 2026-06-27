param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-preinstall-freshness-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

function New-TestEvidenceRoot([string]$Name) {
    $EvidenceRoot = Join-Path $OutputDir "$Name\evidence"
    New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null
    return $EvidenceRoot
}

function Write-EvidenceFile([string]$EvidenceRoot, [string]$RelativePath, [string]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Content | Out-File -LiteralPath $Path -Encoding utf8
}

function Write-InstallActivationEvidence([string]$EvidenceRoot) {
    Write-EvidenceFile $EvidenceRoot "p2-win01-installer\commands.txt" @"
tools\install-yune-windows-ime.ps1 -ApprovedMachineStateChange
tools\run-notepad-smoke.ps1 -ApprovedMachineStateChange
tools\run-chromium-smoke.ps1 -ApprovedMachineStateChange
tools\uninstall-yune-windows-ime.ps1 -ApprovedMachineStateChange
"@
    Write-EvidenceFile $EvidenceRoot "p2-win01-installer\result.md" @"
# Install And Smoke Result

Status: passed

Fresh install: completed.
Notepad smoke: completed.
Chromium smoke: completed.
Diagnostics bundle: synthetic.zip.
"@
    Write-EvidenceFile $EvidenceRoot "p2-win01-installer\post-install-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":false}",
  "server_processes": []
}
"@
    Write-EvidenceFile $EvidenceRoot "p2-win01-tsf-smoke\notepad-post-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": []
}
"@
}

function Get-InstallGateStatus([string]$EvidenceRoot, [string]$Name) {
    $JsonPath = Join-Path $OutputDir "$Name\audit.json"
    $MarkdownPath = Join-Path $OutputDir "$Name\audit.md"
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null

    $Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    $InstallGate = $Audit.gates |
        Where-Object { $_.id -eq "fresh-install-registration-activation" } |
        Select-Object -First 1
    if (-not $InstallGate) {
        throw "audit did not emit fresh-install-registration-activation gate for $Name"
    }
    return $InstallGate.status
}

$MissingPreinstallEvidence = New-TestEvidenceRoot "missing-preinstall"
Write-InstallActivationEvidence $MissingPreinstallEvidence
$MissingStatus = Get-InstallGateStatus $MissingPreinstallEvidence "missing-preinstall"
if ($MissingStatus -ne "invalid") {
    throw "audit should reject fresh install evidence without pre-install state, got $MissingStatus"
}

$DirtyPreinstallEvidence = New-TestEvidenceRoot "dirty-preinstall"
Write-InstallActivationEvidence $DirtyPreinstallEvidence
Write-EvidenceFile $DirtyPreinstallEvidence "p2-win01-installer\pre-install-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": [
    {
      "Id": 4242,
      "ProcessName": "YuneWindowsServer",
      "Path": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme\\YuneWindowsServer.exe"
    }
  ]
}
"@
$DirtyStatus = Get-InstallGateStatus $DirtyPreinstallEvidence "dirty-preinstall"
if ($DirtyStatus -ne "invalid") {
    throw "audit should reject fresh install evidence when pre-install state already has YuneWindows residue, got $DirtyStatus"
}

$UnverifiedPreinstallEvidence = New-TestEvidenceRoot "unverified-preinstall"
Write-InstallActivationEvidence $UnverifiedPreinstallEvidence
Write-EvidenceFile $UnverifiedPreinstallEvidence "p2-win01-installer\pre-install-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": false,
  "profile_state": null,
  "server_processes": []
}
"@
$UnverifiedStatus = Get-InstallGateStatus $UnverifiedPreinstallEvidence "unverified-preinstall"
if ($UnverifiedStatus -ne "invalid") {
    throw "audit should reject fresh install evidence when pre-install profile state was not verified, got $UnverifiedStatus"
}

Write-Host "Closeout audit rejects missing, dirty, or unverified pre-install freshness evidence."
