param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1"
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

if ($SupportSource -notmatch 'function\s+Assert-YuneWindowsCleanPreInstallSnapshot') {
    throw "live-smoke-support.ps1 is missing Assert-YuneWindowsCleanPreInstallSnapshot."
}

function Require-OrderedText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Needle,
        [Parameter(Mandatory = $true)]
        [string]$Reason,
        [Parameter(Mandatory = $true)]
        [ref]$PreviousIndex
    )

    $Index = $OrchestratorSource.IndexOf($Needle, $PreviousIndex.Value + 1)
    if ($Index -lt 0) {
        throw "tools\run-m01-live-smoke.ps1 is missing $Reason."
    }
    $PreviousIndex.Value = $Index
}

$PreviousIndex = [ref](-1)
Require-OrderedText '$CurrentStage = "pre-install-state"' "pre-install state stage" $PreviousIndex
Require-OrderedText 'pre-install-state.json' "pre-install snapshot path" $PreviousIndex
Require-OrderedText 'Write-YuneWindowsStateSnapshot' "pre-install state snapshot write" $PreviousIndex
Require-OrderedText 'Assert-YuneWindowsCleanPreInstallSnapshot' "clean pre-install state assertion" $PreviousIndex
Require-OrderedText '$InstallCommand = "tools\install-yune-windows-ime.ps1' "install command construction" $PreviousIndex
Require-OrderedText 'Record-Command $InstallCommand' "install command transcript" $PreviousIndex

. $SupportPath

$TempRoot = Join-Path $env:TEMP "yune-windows\m01-preinstall-clean-state-contract"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $TempRoot | Out-Null

function Write-Snapshot {
    param(
        [string]$Name,
        [bool]$InstallDirExists,
        [bool]$ProfileToolExists,
        [bool]$ProfileStateVerified,
        [bool]$Registered,
        [bool]$Active,
        [bool]$HasServerProcess,
        [bool]$IncludeMachineResidue = $false,
        [string[]]$MachineStateIssues = @(),
        [string[]]$FilesystemLeftovers = @()
    )

    $Path = Join-Path $TempRoot $Name
    $ServerProcesses = if ($HasServerProcess) {
        @(@{ Id = 1234; ProcessName = "YuneWindowsServer"; Path = "C:\Temp\YuneWindowsServer.exe" })
    } else {
        @()
    }
    $Snapshot = [ordered]@{
        captured_at = "2026-06-26T18:40:00.0000000-07:00"
        install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
        install_dir_exists = $InstallDirExists
        profile_tool_exists = $ProfileToolExists
        profile_state_verified = $ProfileStateVerified
        profile_state = (@{ registered = $Registered; active = $Active } | ConvertTo-Json -Compress)
        server_processes = $ServerProcesses
    }
    if ($IncludeMachineResidue) {
        $Snapshot.machine_state_checked = $true
        $Snapshot.machine_state_issues = $MachineStateIssues
        $Snapshot.filesystem_leftovers = $FilesystemLeftovers
    }
    $Snapshot | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
    return $Path
}

function Expect-PreinstallFailure {
    param(
        [string]$Path,
        [string]$Reason
    )

    $Failed = $false
    try {
        Assert-YuneWindowsCleanPreInstallSnapshot -Path $Path -Context $Reason
    }
    catch {
        $Failed = $true
    }
    if (-not $Failed) {
        throw "Assert-YuneWindowsCleanPreInstallSnapshot accepted dirty pre-install state: $Reason"
    }
}

$Clean = Write-Snapshot `
    -Name "clean.json" `
    -InstallDirExists $false `
    -ProfileToolExists $false `
    -ProfileStateVerified $true `
    -Registered $false `
    -Active $false `
    -HasServerProcess $false `
    -IncludeMachineResidue $true
Assert-YuneWindowsCleanPreInstallSnapshot -Path $Clean -Context "clean pre-install"

$DirtyInstall = Write-Snapshot "dirty-install.json" $true $false $true $false $false $false
Expect-PreinstallFailure -Path $DirtyInstall -Reason "dirty install directory"

$DirtyProfile = Write-Snapshot "dirty-profile.json" $false $false $true $true $false $false
Expect-PreinstallFailure -Path $DirtyProfile -Reason "registered profile residue"

$UnverifiedProfile = Write-Snapshot "unverified-profile.json" $false $false $false $false $false $false
Expect-PreinstallFailure -Path $UnverifiedProfile -Reason "unverified profile state"

$DirtyServer = Write-Snapshot "dirty-server.json" $false $false $true $false $false $true
Expect-PreinstallFailure -Path $DirtyServer -Reason "server residue"

$MissingMachineResidueCheck = Write-Snapshot "missing-machine-residue-check.json" $false $false $true $false $false $false
Expect-PreinstallFailure -Path $MissingMachineResidueCheck -Reason "missing machine-residue check"

$DirtyMachineResidue = Write-Snapshot `
    -Name "dirty-machine-residue.json" `
    -InstallDirExists $false `
    -ProfileToolExists $false `
    -ProfileStateVerified $true `
    -Registered $false `
    -Active $false `
    -HasServerProcess $false `
    -IncludeMachineResidue $true `
    -MachineStateIssues @("COM CLSID registry key remains")
Expect-PreinstallFailure -Path $DirtyMachineResidue -Reason "machine-state residue"

$DirtyFilesystemResidue = Write-Snapshot `
    -Name "dirty-filesystem-residue.json" `
    -InstallDirExists $false `
    -ProfileToolExists $false `
    -ProfileStateVerified $true `
    -Registered $false `
    -Active $false `
    -HasServerProcess $false `
    -IncludeMachineResidue $true `
    -FilesystemLeftovers @("C:\Windows\System32\YuneWindows.dll.old.0")
Expect-PreinstallFailure -Path $DirtyFilesystemResidue -Reason "filesystem residue"

$StringTypedSnapshot = Join-Path $TempRoot "string-typed-booleans.json"
@"
{
  "captured_at": "2026-06-26T18:40:00.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": "false",
  "profile_tool_exists": "false",
  "profile_state_verified": "true",
  "profile_state": "{\"registered\":\"false\",\"active\":\"false\"}",
  "server_processes": [],
  "machine_state_checked": "true",
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
"@ | Out-File -LiteralPath $StringTypedSnapshot -Encoding utf8
Expect-PreinstallFailure -Path $StringTypedSnapshot -Reason "string-typed pre-install state booleans"

Write-Host "Live smoke validates clean pre-install state before install."
