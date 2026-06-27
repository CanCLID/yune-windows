param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

if ($SupportSource -notmatch 'function\s+Assert-YuneWindowsRegisteredInstalledSnapshot') {
    throw "live-smoke-support.ps1 is missing Assert-YuneWindowsRegisteredInstalledSnapshot."
}
foreach ($Required in @(
        'machine_registration_checked',
        'machine_registration_verified',
        'machine_registration_registered',
        'machine_registration_missing_keys',
        'machine_registration_dll_path_matches'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live-smoke-support.ps1 is missing post-install machine-registration field: $Required"
    }
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
        throw "tools\run-p2-win01-live-smoke.ps1 is missing $Reason."
    }
    $PreviousIndex.Value = $Index
}

$PreviousIndex = [ref](-1)
Require-OrderedText '$InstallCommand = "tools\install-yune-windows-ime.ps1' "install command construction" $PreviousIndex
Require-OrderedText 'Record-Command $InstallCommand' "install command transcript" $PreviousIndex
Require-OrderedText 'Record-CommandSuccess $InstallCommand' "install command completion transcript" $PreviousIndex
Require-OrderedText '$CurrentStage = "post-install-state"' "post-install state stage" $PreviousIndex
Require-OrderedText 'post-install-state.json' "post-install snapshot path" $PreviousIndex
Require-OrderedText 'Write-YuneWindowsStateSnapshot' "post-install state snapshot write" $PreviousIndex
Require-OrderedText '-IncludeMachineRegistration' "post-install machine-registration snapshot flag" $PreviousIndex
Require-OrderedText 'Assert-YuneWindowsRegisteredInstalledSnapshot' "registered installed state assertion" $PreviousIndex
Require-OrderedText '$NotepadCommand = "tools\run-notepad-smoke.ps1' "Notepad command construction" $PreviousIndex
Require-OrderedText 'Record-Command $NotepadCommand' "Notepad command transcript" $PreviousIndex

. $SupportPath

$TempRoot = Join-Path $env:TEMP "yune-windows\p2-win01-postinstall-registered-state-contract"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $TempRoot | Out-Null

function Write-Snapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$InstallDirExists,
        [Parameter(Mandatory = $true)]
        [bool]$ProfileToolExists,
        [Parameter(Mandatory = $true)]
        [bool]$MachineRegistrationChecked,
        [Parameter(Mandatory = $true)]
        [bool]$MachineRegistrationVerified,
        [Parameter(Mandatory = $true)]
        [bool]$MachineRegistrationRegistered,
        [Parameter(Mandatory = $true)]
        [bool]$MachineRegistrationDllPathMatches
    )

    $Path = Join-Path $TempRoot $Name
    [ordered]@{
        captured_at = "2026-06-26T18:40:00.0000000-07:00"
        install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
        install_dir_exists = $InstallDirExists
        profile_tool_exists = $ProfileToolExists
        machine_registration_checked = $MachineRegistrationChecked
        machine_registration_verified = $MachineRegistrationVerified
        machine_registration_registered = $MachineRegistrationRegistered
        machine_registration_dll_path_matches = $MachineRegistrationDllPathMatches
        machine_registration_missing_keys = @()
        machine_registration_registry_check_errors = @()
        machine_registration_dll_path = "C:\Users\example\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll"
        server_processes = @()
    } | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
    return $Path
}

function Expect-PostinstallFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $Failed = $false
    try {
        Assert-YuneWindowsRegisteredInstalledSnapshot -Path $Path -Context $Reason
    }
    catch {
        $Failed = $true
    }
    if (-not $Failed) {
        throw "Assert-YuneWindowsRegisteredInstalledSnapshot accepted weak post-install state: $Reason"
    }
}

$Registered = Write-Snapshot `
    -Name "registered.json" `
    -InstallDirExists $true `
    -ProfileToolExists $true `
    -MachineRegistrationChecked $true `
    -MachineRegistrationVerified $true `
    -MachineRegistrationRegistered $true `
    -MachineRegistrationDllPathMatches $true
Assert-YuneWindowsRegisteredInstalledSnapshot -Path $Registered -Context "registered post-install"

$MissingInstall = Write-Snapshot `
    -Name "missing-install.json" `
    -InstallDirExists $false `
    -ProfileToolExists $true `
    -MachineRegistrationChecked $true `
    -MachineRegistrationVerified $true `
    -MachineRegistrationRegistered $true `
    -MachineRegistrationDllPathMatches $true
Expect-PostinstallFailure -Path $MissingInstall -Reason "missing install directory"

$MissingProfileTool = Write-Snapshot `
    -Name "missing-profile-tool.json" `
    -InstallDirExists $true `
    -ProfileToolExists $false `
    -MachineRegistrationChecked $true `
    -MachineRegistrationVerified $true `
    -MachineRegistrationRegistered $true `
    -MachineRegistrationDllPathMatches $true
Expect-PostinstallFailure -Path $MissingProfileTool -Reason "missing profile tool"

$UncheckedRegistration = Write-Snapshot `
    -Name "unchecked-registration.json" `
    -InstallDirExists $true `
    -ProfileToolExists $true `
    -MachineRegistrationChecked $false `
    -MachineRegistrationVerified $true `
    -MachineRegistrationRegistered $true `
    -MachineRegistrationDllPathMatches $true
Expect-PostinstallFailure -Path $UncheckedRegistration -Reason "unchecked machine registration"

$UnverifiedRegistration = Write-Snapshot `
    -Name "unverified-registration.json" `
    -InstallDirExists $true `
    -ProfileToolExists $true `
    -MachineRegistrationChecked $true `
    -MachineRegistrationVerified $false `
    -MachineRegistrationRegistered $true `
    -MachineRegistrationDllPathMatches $true
Expect-PostinstallFailure -Path $UnverifiedRegistration -Reason "unverified machine registration"

$UnregisteredMachine = Write-Snapshot `
    -Name "unregistered-machine.json" `
    -InstallDirExists $true `
    -ProfileToolExists $true `
    -MachineRegistrationChecked $true `
    -MachineRegistrationVerified $true `
    -MachineRegistrationRegistered $false `
    -MachineRegistrationDllPathMatches $true
Expect-PostinstallFailure -Path $UnregisteredMachine -Reason "unregistered machine state"

$WrongDllPath = Write-Snapshot `
    -Name "wrong-dll-path.json" `
    -InstallDirExists $true `
    -ProfileToolExists $true `
    -MachineRegistrationChecked $true `
    -MachineRegistrationVerified $true `
    -MachineRegistrationRegistered $true `
    -MachineRegistrationDllPathMatches $false
Expect-PostinstallFailure -Path $WrongDllPath -Reason "wrong registered DLL path"

$StringTypedSnapshot = Join-Path $TempRoot "string-typed-booleans.json"
@"
{
  "captured_at": "2026-06-26T18:40:00.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": "true",
  "profile_tool_exists": "true",
  "machine_registration_checked": "true",
  "machine_registration_verified": "true",
  "machine_registration_registered": "true",
  "machine_registration_dll_path_matches": "true",
  "machine_registration_missing_keys": [],
  "machine_registration_registry_check_errors": [],
  "server_processes": []
}
"@ | Out-File -LiteralPath $StringTypedSnapshot -Encoding utf8
Expect-PostinstallFailure -Path $StringTypedSnapshot -Reason "string-typed post-install state booleans"

Write-Host "Live smoke validates machine registration before app automation."
