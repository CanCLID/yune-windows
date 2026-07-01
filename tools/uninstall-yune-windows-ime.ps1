param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = "",
    [switch]$KeepFiles,
    [string]$ResultPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

$script:YuneWindowsSafeModuleHostsStopped = @()

function Require-Approval {
    if (-not $ApprovedMachineStateChange) {
        throw "Refusing to unregister/uninstall the IME without explicit approval. Rerun with -ApprovedMachineStateChange only after approval in the current session."
    }
}

function Require-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "IME unregistration requires an elevated PowerShell session after approval."
    }
}

function Resolve-SafeInstallDir([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    $allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Yune"))
    if (-not $full.StartsWith($allowedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe install directory outside LocalAppData\Yune: $full"
    }
    return $full
}

function Assert-YuneWindowsProfileUnregistered([string]$ProfileToolPath) {
    if (-not (Test-Path -LiteralPath $ProfileToolPath)) {
        throw "installed profile tool is missing; cannot verify profile unregistration before file removal"
    }

    $ProfileStateText = (Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $ProfileToolPath `
            -Arguments @("--state") `
            -Operation "profile state check").Trim()
    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "profile state check returned invalid JSON: $ProfileStateText"
    }

    try {
        Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $false -Context "profile state check"
        Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false -Context "profile state check"
    }
    catch {
        throw "profile unregistration did not verify after regsvr32 /u: $ProfileStateText ($($_.Exception.Message))"
    }
}

function Assert-YuneWindowsUninstallPreconditions([string]$TsfDllPath, [string]$ProfileToolPath) {
    if ((Test-Path -LiteralPath $ProfileToolPath) -and -not (Test-Path -LiteralPath $TsfDllPath)) {
        throw "YuneWindowsTSF.dll is missing while YuneWindowsProfileTool.exe remains; refusing to remove installed files before TSF profile unregistration can be verified."
    }
}

function Test-YuneWindowsInstalledProfileToolAvailable([string]$ProfileToolPath) {
    return (Test-Path -LiteralPath $ProfileToolPath -PathType Leaf)
}

function Get-YuneWindowsProcessesUsingModule {
    param([Parameter(Mandatory = $true)][string]$ModulePath)

    if (-not (Test-Path -LiteralPath $ModulePath)) {
        return @()
    }

    $ExpectedPath = [System.IO.Path]::GetFullPath($ModulePath)
    $Holders = [System.Collections.Generic.List[object]]::new()
    foreach ($Process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            foreach ($Module in @($Process.Modules)) {
                if ([string]::IsNullOrWhiteSpace([string]$Module.FileName)) {
                    continue
                }
                $ModuleFullPath = [System.IO.Path]::GetFullPath([string]$Module.FileName)
                if ([string]::Equals($ModuleFullPath, $ExpectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $ProcessPath = ""
                    try {
                        $ProcessPath = [string]$Process.Path
                    }
                    catch {
                    }
                    $Holders.Add([pscustomobject]@{
                            process_id = [int]$Process.Id
                            process_name = [string]$Process.ProcessName
                            process_path = $ProcessPath
                        }) | Out-Null
                    break
                }
            }
        }
        catch {
        }
    }

    return @($Holders)
}

function Format-YuneWindowsProcessHolderSummary {
    param([object[]]$Holders)

    if (-not $Holders -or @($Holders).Count -eq 0) {
        return "none"
    }

    return (@($Holders) | ForEach-Object {
            "$($_.process_name)[$($_.process_id)]"
        }) -join ", "
}

function Write-YuneWindowsCleanupResult {
    param(
        [Parameter(Mandatory = $true)][object]$Result,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent)) {
        New-Item -ItemType Directory -Force $Parent | Out-Null
    }
    $Result | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}

function Stop-YuneWindowsTsfModuleHostProcesses {
    param([Parameter(Mandatory = $true)][string]$TsfDllPath)

    $SafeHostProcessNames = @("ctfmon", "TextInputHost")
    $Holders = @(Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDllPath)
    foreach ($Holder in $Holders) {
        if ($SafeHostProcessNames -contains $Holder.process_name) {
            Stop-Process -Id ([int]$Holder.process_id) -Force -ErrorAction SilentlyContinue
            Wait-YuneWindowsProcessExit -ProcessId ([int]$Holder.process_id) -RequireExit
            $script:YuneWindowsSafeModuleHostsStopped += $Holder
        }
    }
}

function Invoke-YuneWindowsProfileDeactivation([string]$ProfileToolPath) {
    if (-not (Test-Path -LiteralPath $ProfileToolPath)) {
        throw "installed profile tool is missing; cannot deactivate active YuneWindows profile before unregister"
    }

    $ProfileStateText = (Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $ProfileToolPath `
            -Arguments @("--deactivate") `
            -Operation "profile deactivation before unregister").Trim()
    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "profile deactivation returned invalid JSON: $ProfileStateText"
    }

    try {
        Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false -Context "profile deactivation"
    }
    catch {
        throw "profile deactivation did not verify before regsvr32 /u: $ProfileStateText ($($_.Exception.Message))"
    }
}

function Remove-YuneWindowsInstallDirectoryWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$LockedModulePath = "",
        [int]$Attempts = 20,
        [int]$DelayMilliseconds = 500
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $LastError = ""
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        if (-not [string]::IsNullOrWhiteSpace($LockedModulePath) -and
            (Test-Path -LiteralPath $LockedModulePath)) {
            try {
                Stop-YuneWindowsTsfModuleHostProcesses -TsfDllPath $LockedModulePath
            }
            catch {
                $LastError = "module host cleanup failed: $($_.Exception.Message)"
            }
        }

        try {
            Remove-Item -LiteralPath $Path -Recurse -Force
            if (-not (Test-Path -LiteralPath $Path)) {
                return
            }
            $LastError = "install directory still exists after Remove-Item"
        }
        catch {
            $LastError = $_.Exception.Message
        }

        if ($Attempt -lt $Attempts) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    $LockingProcessSummary = ""
    if (-not [string]::IsNullOrWhiteSpace($LockedModulePath) -and
        (Test-Path -LiteralPath $LockedModulePath)) {
        $LockingHolders = @(Get-YuneWindowsProcessesUsingModule -ModulePath $LockedModulePath)
        if ($LockingHolders.Count -gt 0) {
            $LockingProcessSummary = " Locking module holders: $(Format-YuneWindowsProcessHolderSummary -Holders $LockingHolders)"
        }
    }

    throw "Failed to remove YuneWindows install directory after $Attempts attempts: $LastError.$LockingProcessSummary"
}

function Test-YuneWindowsPathUnderInstallRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $FullRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
    return [string]::Equals($FullPath, $FullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $FullPath.StartsWith($FullRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Ensure-YuneWindowsMoveFileExType {
    if ("YuneWindows.UninstallNative" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace YuneWindows {
    public static class UninstallNative {
        [DllImport("kernel32.dll", EntryPoint = "MoveFileExW", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool MoveFileEx(string existingFileName, IntPtr newFileName, int flags);
    }
}
"@
}

function Schedule-YuneWindowsDelayedDelete {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    if (-not (Test-Path -LiteralPath $InstallRoot)) {
        return @()
    }

    Ensure-YuneWindowsMoveFileExType
    $MOVEFILE_DELAY_UNTIL_REBOOT = 0x00000004
    $Items = @(Get-ChildItem -LiteralPath $InstallRoot -Force -Recurse -ErrorAction SilentlyContinue)
    $Files = @($Items | Where-Object { -not $_.PSIsContainer } | ForEach-Object { $_.FullName })
    $Directories = @($Items |
        Where-Object { $_.PSIsContainer } |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { $_.FullName })
    $Paths = @($Files + $Directories + @($InstallRoot))
    $Scheduled = [System.Collections.Generic.List[string]]::new()

    foreach ($Path in $Paths) {
        if (-not (Test-YuneWindowsPathUnderInstallRoot -Path $Path -InstallRoot $InstallRoot)) {
            throw "refusing delayed delete outside approved install root: $Path"
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            continue
        }
        $Ok = [YuneWindows.UninstallNative]::MoveFileEx(
            $Path, [IntPtr]::Zero, $MOVEFILE_DELAY_UNTIL_REBOOT)
        if (-not $Ok) {
            $ErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "MoveFileEx delayed delete failed for ${Path}: Win32 error $ErrorCode"
        }
        $Scheduled.Add($Path) | Out-Null
    }

    return @($Scheduled)
}

Require-Approval
Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
Require-Administrator

$InstallRoot = Resolve-SafeInstallDir $InstallDir
$Server = Join-Path $InstallRoot "YuneWindowsServer.exe"
$TsfDll = Join-Path $InstallRoot "YuneWindowsTSF.dll"
$ProfileTool = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"

$CleanupResult = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    install_dir = $InstallRoot
    approval_note_present = -not [string]::IsNullOrWhiteSpace($ApprovalNote)
    profile_deactivated = $false
    machine_registration_absent = $false
    server_processes_stopped = $false
    safe_module_hosts_stopped = @()
    module_holders_before_remove = @()
    module_holders_after_remove = @()
    install_dir_removed = $false
    pending_delete_scheduled = $false
    pending_delete_paths = @()
    requires_reboot = $false
    pass = $false
    error = ""
}

try {
    Assert-YuneWindowsUninstallPreconditions -TsfDllPath $TsfDll -ProfileToolPath $ProfileTool
    $InstalledProfileToolAvailable = Test-YuneWindowsInstalledProfileToolAvailable -ProfileToolPath $ProfileTool

    $ServerProcessStopFailed = $false
    Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -eq $Server) {
                Stop-Process -Id $_.Id -Force
                Wait-YuneWindowsProcessExit -ProcessId ([int]$_.Id) -RequireExit
            }
        }
        catch {
            $ServerProcessStopFailed = $true
        }
    }

    $CleanupResult.server_processes_stopped = -not $ServerProcessStopFailed

    if ($InstalledProfileToolAvailable -and (Test-Path -LiteralPath $TsfDll)) {
        Invoke-YuneWindowsProfileDeactivation -ProfileToolPath $ProfileTool
        $CleanupResult.profile_deactivated = $true

        Invoke-YuneWindowsRegsvr32 `
            -Arguments @("/u", "/s", $TsfDll) `
            -Operation "regsvr32 unregistration" | Out-Null

        Clear-YuneWindowsMachineRegistrationResidue -InstallDir $InstallRoot | Out-Null
        Assert-YuneWindowsMachineRegistrationAbsent -InstallDir $InstallRoot | Out-Null
        $CleanupResult.machine_registration_absent = $true
    }
    elseif (Test-Path -LiteralPath $TsfDll) {
        Assert-YuneWindowsMachineRegistrationAbsent -InstallDir $InstallRoot | Out-Null
        $CleanupResult.machine_registration_absent = $true
    }
    else {
        $CleanupResult.machine_registration_absent = $true
    }

    if (-not $KeepFiles -and (Test-Path -LiteralPath $InstallRoot)) {
        if (Test-Path -LiteralPath $TsfDll) {
            Stop-YuneWindowsTsfModuleHostProcesses -TsfDllPath $TsfDll
        }
        $CleanupResult.module_holders_before_remove =
            @(Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDll)
        if ($CleanupResult.module_holders_before_remove.Count -gt 0) {
            $RemovalError = "install directory contains locked YuneWindowsTSF.dll module holders: $(Format-YuneWindowsProcessHolderSummary -Holders $CleanupResult.module_holders_before_remove)"
            $ScheduledPaths = @(Schedule-YuneWindowsDelayedDelete -InstallRoot $InstallRoot)
            if ($ScheduledPaths.Count -gt 0) {
                $CleanupResult.pending_delete_scheduled = $true
                $CleanupResult.pending_delete_paths = @($ScheduledPaths)
                $CleanupResult.requires_reboot = $true
            }
            throw $RemovalError
        }
        try {
            Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot -LockedModulePath $TsfDll
        }
        catch {
            $RemovalError = $_.Exception.Message
            $CleanupResult.module_holders_after_remove =
                @(Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDll)
            $ScheduledPaths = @(Schedule-YuneWindowsDelayedDelete -InstallRoot $InstallRoot)
            if ($ScheduledPaths.Count -gt 0) {
                $CleanupResult.pending_delete_scheduled = $true
                $CleanupResult.pending_delete_paths = @($ScheduledPaths)
                $CleanupResult.requires_reboot = $true
            }
            throw $RemovalError
        }
    }

    $CleanupResult.safe_module_hosts_stopped =
        @($script:YuneWindowsSafeModuleHostsStopped)
    $CleanupResult.module_holders_after_remove =
        @(Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDll)
    $CleanupResult.install_dir_removed = -not (Test-Path -LiteralPath $InstallRoot)
    $CleanupResult.pass =
        $CleanupResult.machine_registration_absent -and
        ($KeepFiles -or $CleanupResult.install_dir_removed) -and
        (-not $CleanupResult.requires_reboot)

    Write-YuneWindowsCleanupResult -Result $CleanupResult -Path $ResultPath
    Write-Host "Unregistered Yune Windows IME from $InstallRoot"
}
catch {
    $CleanupResult.error = $_.Exception.Message
    $CleanupResult.safe_module_hosts_stopped =
        @($script:YuneWindowsSafeModuleHostsStopped)
    if (Test-Path -LiteralPath $TsfDll) {
        $CleanupResult.module_holders_after_remove =
            @(Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDll)
    }
    $CleanupResult.install_dir_removed = -not (Test-Path -LiteralPath $InstallRoot)
    $CleanupResult.pass = $false
    Write-YuneWindowsCleanupResult -Result $CleanupResult -Path $ResultPath
    throw
}
