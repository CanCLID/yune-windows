param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

$CleanState = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = $null
    server_processes = @()
}

$CleanResult = Test-YuneWindowsCleanupState -Snapshot $CleanState
if ($CleanResult.pass -ne $true) {
    throw "expected clean synthetic state to pass cleanup validation"
}
try {
    [void][System.DateTimeOffset]::Parse(
        [string]$CleanResult.generated_at,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind)
}
catch {
    throw "cleanup validation result must record parseable generated_at"
}

$DirtyProfile = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = '{"registered":true,"active":true}'
    server_processes = @()
}
$DirtyProfileResult = Test-YuneWindowsCleanupState -Snapshot $DirtyProfile
if ($DirtyProfileResult.pass -ne $false -or
    ($DirtyProfileResult.issues -notcontains "YuneWindows TSF profile is still registered")) {
    throw "expected registered profile residue to fail cleanup validation"
}

$DirtyProfileTool = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $true
    profile_state = $null
    server_processes = @()
}
$DirtyProfileToolResult = Test-YuneWindowsCleanupState -Snapshot $DirtyProfileTool
if ($DirtyProfileToolResult.pass -ne $false -or
    ($DirtyProfileToolResult.issues -notcontains "Installed YuneWindowsProfileTool.exe still exists")) {
    throw "expected installed profile tool residue to fail cleanup validation"
}

$DirtyProcess = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = $null
    server_processes = @([pscustomobject]@{
        Id = 1234
        Path = "C:\Users\example\AppData\Local\Yune\WindowsIme\YuneWindowsServer.exe"
    })
}
$DirtyProcessResult = Test-YuneWindowsCleanupState -Snapshot $DirtyProcess
if ($DirtyProcessResult.pass -ne $false -or
    ($DirtyProcessResult.issues -notcontains "YuneWindowsServer.exe is still running from the install path")) {
    throw "expected server process residue to fail cleanup validation"
}

$DirtyProcessUnknownPath = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = $null
    server_processes = @([pscustomobject]@{
        Id = 5678
        Path = $null
    })
}
$DirtyProcessUnknownPathResult = Test-YuneWindowsCleanupState -Snapshot $DirtyProcessUnknownPath
if ($DirtyProcessUnknownPathResult.pass -ne $false -or
    ($DirtyProcessUnknownPathResult.issues -notcontains "YuneWindowsServer.exe is still running")) {
    throw "expected server process residue with unknown path to fail cleanup validation"
}

Write-Host "Cleanup validator catches profile/profile-tool/process/install-dir residue."
