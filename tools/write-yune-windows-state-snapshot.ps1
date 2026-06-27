param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$ProfileToolPath = "",
    [string]$ApprovalNote = "",
    [switch]$IncludeMachineResidue,
    [switch]$IncludeMachineRegistration,
    [switch]$AssertActiveInstalled,
    [switch]$AssertRegisteredInstalled
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote

Write-YuneWindowsStateSnapshot `
    -Path $Path `
    -InstallDir $InstallDir `
    -ProfileToolPath $ProfileToolPath `
    -ApprovalNote $ApprovalNote `
    -IncludeMachineResidue:$($IncludeMachineResidue.IsPresent) `
    -IncludeMachineRegistration:$($IncludeMachineRegistration.IsPresent)

if ($AssertActiveInstalled) {
    Assert-YuneWindowsActiveInstalledSnapshot `
        -Path $Path `
        -Context "Interactive state snapshot"
}

if ($AssertRegisteredInstalled) {
    Assert-YuneWindowsRegisteredInstalledSnapshot `
        -Path $Path `
        -Context "Interactive state snapshot"
}

Write-Output $Path
