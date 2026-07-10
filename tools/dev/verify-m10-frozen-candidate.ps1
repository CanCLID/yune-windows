param(
    [Parameter(Mandatory = $true)][string]$CandidateManifest,
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [switch]$AllowNoHolders
)

$ErrorActionPreference = "Stop"

function Resolve-M10VerifyFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-M10VerifyFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedHash
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            name = $Name
            path = $Path
            exists = $false
            length = 0
            expected_sha256 = $ExpectedHash
            actual_sha256 = ""
            matches_candidate = $false
        }
    }
    $Item = Get-Item -LiteralPath $Path
    $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Item.FullName).Hash
    return [pscustomobject][ordered]@{
        name = $Name
        path = $Item.FullName
        exists = $true
        length = [long]$Item.Length
        expected_sha256 = $ExpectedHash
        actual_sha256 = $ActualHash
        matches_candidate = [string]::Equals(
            $ActualHash,
            $ExpectedHash,
            [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Get-M10VerifyPeSizeOfImage {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 0
    }
    $Stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    $Reader = [System.IO.BinaryReader]::new($Stream)
    try {
        if ($Stream.Length -lt 256 -or $Reader.ReadUInt16() -ne 0x5a4d) {
            return 0
        }
        $Stream.Position = 0x3c
        $PeOffset = $Reader.ReadInt32()
        if ($PeOffset -lt 0 -or ($PeOffset + 24 + 60) -gt $Stream.Length) {
            return 0
        }
        $Stream.Position = $PeOffset
        if ($Reader.ReadUInt32() -ne 0x00004550) {
            return 0
        }
        $OptionalHeader = $PeOffset + 24
        $Stream.Position = $OptionalHeader
        $Magic = $Reader.ReadUInt16()
        if ($Magic -ne 0x010b -and $Magic -ne 0x020b) {
            return 0
        }
        $Stream.Position = $OptionalHeader + 56
        return [long]$Reader.ReadUInt32()
    }
    finally {
        $Reader.Dispose()
        $Stream.Dispose()
    }
}

function Test-M10VerifyPathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $FullPath = (Resolve-M10VerifyFullPath $Path).TrimEnd("\")
    $FullRoot = (Resolve-M10VerifyFullPath $Root).TrimEnd("\")
    return [string]::Equals(
        $FullPath,
        $FullRoot,
        [System.StringComparison]::OrdinalIgnoreCase) -or
        $FullPath.StartsWith(
            $FullRoot + "\",
            [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-M10VerifyStartState {
    param(
        [string]$StartedAt,
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$DeploymentCompletedAt
    )

    $Parsed = [DateTimeOffset]::MinValue
    $Known = -not [string]::IsNullOrWhiteSpace($StartedAt) -and
        [DateTimeOffset]::TryParse(
            $StartedAt,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$Parsed)
    return [pscustomobject][ordered]@{
        process_started_at = $StartedAt
        start_time_known = $Known
        started_strictly_after_deployment =
            $Known -and $Parsed -gt $DeploymentCompletedAt
    }
}

function Test-M10VerifyProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return $null -ne $Object.PSObject.Properties[$Name]
}

function Test-M10VerifyExactBoolean {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Expected
    )

    if (-not (Test-M10VerifyProperty -Object $Object -Name $Name)) {
        return $false
    }
    $Value = $Object.PSObject.Properties[$Name].Value
    return $Value -is [bool] -and $Value -eq $Expected
}

function Assert-M10VerifyManifestAdmission {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][bool]$DeploymentCompletedAtValid
    )

    $RequiredDeploymentFields = @(
        "performed",
        "error",
        "rollback_attempted",
        "rollback_complete",
        "completed_at"
    )
    $HasRequiredDeploymentFields = $null -ne $Manifest.deployment
    if ($HasRequiredDeploymentFields) {
        foreach ($Field in $RequiredDeploymentFields) {
            $HasRequiredDeploymentFields = $HasRequiredDeploymentFields -and
                (Test-M10VerifyProperty -Object $Manifest.deployment -Name $Field)
        }
    }

    $ManifestSourceCommit = [string]$Manifest.source.actual_commit
    if ([int]$Manifest.schema_version -ne 1 -or
        [string]$Manifest.operation -ne "m10_frozen_candidate" -or
        [string]$Manifest.status -ne "deployed_restart_required" -or
        -not $HasRequiredDeploymentFields -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.build -Name "performed" -Expected $true) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.deployment -Name "performed" -Expected $true) -or
        [string]$Manifest.deployment.error -ne "" -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.deployment `
            -Name "rollback_attempted" `
            -Expected $false) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.deployment `
            -Name "rollback_complete" `
            -Expected $false) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.source -Name "clean" -Expected $true) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.source `
            -Name "post_build_verified" `
            -Expected $true) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.package `
            -Name "post_build_verified" `
            -Expected $true) -or
        -not $DeploymentCompletedAtValid -or
        $ManifestSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or
        [string]$Manifest.source.actual_commit -ne
            [string]$Manifest.source.expected_commit) {
        throw "candidate manifest is not an unrolled-back, completed, clean, pinned M10 deployment awaiting restart proof"
    }
}

function Assert-M10VerifyDurableManifestPath {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ManifestPath
    )

    if ($null -eq $Manifest.manifest -or
        -not (Test-M10VerifyProperty -Object $Manifest.manifest -Name "durable_path") -or
        -not (Test-M10VerifyProperty `
            -Object $Manifest.manifest `
            -Name "durable_outside_os_temp") -or
        -not (Test-M10VerifyProperty -Object $Manifest.manifest -Name "atomic_refresh")) {
        throw "candidate manifest lacks durable provenance metadata"
    }
    $DeclaredPath = Resolve-M10VerifyFullPath ([string]$Manifest.manifest.durable_path)
    $OsTempRoot = Resolve-M10VerifyFullPath ([System.IO.Path]::GetTempPath())
    if (-not [string]::Equals(
            $DeclaredPath,
            $ManifestPath,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.manifest `
            -Name "durable_outside_os_temp" `
            -Expected $true) -or
        -not (Test-M10VerifyExactBoolean `
            -Object $Manifest.manifest `
            -Name "atomic_refresh" `
            -Expected $true) -or
        (Test-M10VerifyPathUnderRoot -Path $ManifestPath -Root $OsTempRoot)) {
        throw "post-restart verification requires the declared durable manifest outside the OS temp tree"
    }
}

function Get-M10VerifyBootBoundaryState {
    param(
        [string]$LastBootUpTime,
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$DeploymentCompletedAt
    )

    $Parsed = [DateTimeOffset]::MinValue
    $Known = -not [string]::IsNullOrWhiteSpace($LastBootUpTime) -and
        [DateTimeOffset]::TryParse(
            $LastBootUpTime,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$Parsed)
    return [pscustomobject][ordered]@{
        last_boot_up_time = $LastBootUpTime
        boot_time_known = $Known
        booted_strictly_after_deployment =
            $Known -and $Parsed -gt $DeploymentCompletedAt
    }
}

function Get-M10VerifyOperatingSystemBootBoundary {
    param(
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$DeploymentCompletedAt
    )

    $LastBootUpTime = ""
    $QueryError = ""
    try {
        $OperatingSystem = Get-CimInstance `
            -ClassName Win32_OperatingSystem `
            -ErrorAction Stop
        if ($null -eq $OperatingSystem -or
            $null -eq $OperatingSystem.LastBootUpTime) {
            throw "Win32_OperatingSystem did not return LastBootUpTime"
        }
        $LastBootUpTime = ([DateTimeOffset](
                $OperatingSystem.LastBootUpTime)).ToString("o")
    }
    catch {
        $QueryError = $_.Exception.Message
    }
    $State = Get-M10VerifyBootBoundaryState `
        -LastBootUpTime $LastBootUpTime `
        -DeploymentCompletedAt $DeploymentCompletedAt
    return [pscustomobject][ordered]@{
        query_method = "Win32_OperatingSystem.LastBootUpTime"
        query_succeeded = [string]::IsNullOrWhiteSpace($QueryError)
        query_error = $QueryError
        last_boot_up_time = $State.last_boot_up_time
        boot_time_known = $State.boot_time_known
        booted_strictly_after_deployment =
            $State.booted_strictly_after_deployment
        proof_complete =
            [string]::IsNullOrWhiteSpace($QueryError) -and
            $State.boot_time_known -and
            $State.booted_strictly_after_deployment
    }
}

function Test-M10VerifyManagedModuleSnapshotComplete {
    param([Parameter(Mandatory = $true)][int]$ModuleCount)

    # A live Windows process necessarily maps more than its executable image.
    # System.Diagnostics can silently return only that image when module access
    # is denied, so a zero/one-module result is never accepted as complete.
    return $ModuleCount -gt 1
}

function Initialize-M10VerifyNativeModuleInspector {
    if ("YuneWindows.M10NativeModuleInspector" -as [type]) {
        return
    }

    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace YuneWindows
{
    public sealed class M10NativeModuleRecord
    {
        public string FileName { get; set; }
        public long ModuleMemorySize { get; set; }
    }

    public sealed class M10NativeModuleSnapshot
    {
        public bool Success { get; set; }
        public int ErrorCode { get; set; }
        public string ErrorStage { get; set; }
        public string ErrorMessage { get; set; }
        public M10NativeModuleRecord[] Modules { get; set; }
    }

    public static class M10NativeModuleInspector
    {
        private const uint ProcessQueryInformation = 0x0400;
        private const uint ProcessVmRead = 0x0010;
        private const uint ListModulesAll = 0x03;

        [StructLayout(LayoutKind.Sequential)]
        private struct ModuleInfo
        {
            public IntPtr BaseAddress;
            public uint SizeOfImage;
            public IntPtr EntryPoint;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(
            uint desiredAccess,
            bool inheritHandle,
            int processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("psapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumProcessModulesEx(
            IntPtr process,
            [Out] IntPtr[] modules,
            int byteCount,
            out int bytesNeeded,
            uint filterFlag);

        [DllImport("psapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetModuleFileNameEx(
            IntPtr process,
            IntPtr module,
            StringBuilder fileName,
            int size);

        [DllImport("psapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetModuleInformation(
            IntPtr process,
            IntPtr module,
            out ModuleInfo moduleInfo,
            int byteCount);

        private static M10NativeModuleSnapshot Failure(
            string stage,
            int errorCode)
        {
            return new M10NativeModuleSnapshot
            {
                Success = false,
                ErrorCode = errorCode,
                ErrorStage = stage,
                ErrorMessage = new Win32Exception(errorCode).Message,
                Modules = new M10NativeModuleRecord[0]
            };
        }

        public static M10NativeModuleSnapshot Inspect(int processId)
        {
            IntPtr process = OpenProcess(
                ProcessQueryInformation | ProcessVmRead,
                false,
                processId);
            if (process == IntPtr.Zero)
            {
                return Failure("OpenProcess", Marshal.GetLastWin32Error());
            }

            try
            {
                IntPtr[] handles = new IntPtr[256];
                int bytesNeeded;
                for (int attempt = 0; attempt < 4; ++attempt)
                {
                    if (!EnumProcessModulesEx(
                        process,
                        handles,
                        handles.Length * IntPtr.Size,
                        out bytesNeeded,
                        ListModulesAll))
                    {
                        return Failure(
                            "EnumProcessModulesEx",
                            Marshal.GetLastWin32Error());
                    }
                    int required =
                        (bytesNeeded + IntPtr.Size - 1) / IntPtr.Size;
                    if (required <= handles.Length)
                    {
                        var modules = new List<M10NativeModuleRecord>(required);
                        for (int index = 0; index < required; ++index)
                        {
                            var fileName = new StringBuilder(32768);
                            if (GetModuleFileNameEx(
                                process,
                                handles[index],
                                fileName,
                                fileName.Capacity) == 0)
                            {
                                return Failure(
                                    "GetModuleFileNameEx",
                                    Marshal.GetLastWin32Error());
                            }
                            ModuleInfo moduleInfo;
                            if (!GetModuleInformation(
                                process,
                                handles[index],
                                out moduleInfo,
                                Marshal.SizeOf(typeof(ModuleInfo))))
                            {
                                return Failure(
                                    "GetModuleInformation",
                                    Marshal.GetLastWin32Error());
                            }
                            modules.Add(new M10NativeModuleRecord
                            {
                                FileName = fileName.ToString(),
                                ModuleMemorySize = moduleInfo.SizeOfImage
                            });
                        }
                        return new M10NativeModuleSnapshot
                        {
                            Success = true,
                            ErrorCode = 0,
                            ErrorStage = "",
                            ErrorMessage = "",
                            Modules = modules.ToArray()
                        };
                    }
                    handles = new IntPtr[required + 64];
                }
                return Failure("module_list_changed_repeatedly", 24);
            }
            finally
            {
                CloseHandle(process);
            }
        }
    }
}
'@
}

function Get-M10VerifyNativeModuleSnapshot {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    try {
        Initialize-M10VerifyNativeModuleInspector
        $Snapshot = [YuneWindows.M10NativeModuleInspector]::Inspect($ProcessId)
        $Modules = @($Snapshot.Modules | ForEach-Object {
                [pscustomobject][ordered]@{
                    file_name = [string]$_.FileName
                    module_memory_size = [long]$_.ModuleMemorySize
                }
            })
        return [pscustomobject][ordered]@{
            method = "native_psapi_fallback"
            succeeded = [bool]$Snapshot.Success -and $Modules.Count -gt 0
            module_count = $Modules.Count
            modules = $Modules
            error_stage = [string]$Snapshot.ErrorStage
            error_code = [int]$Snapshot.ErrorCode
            error_message = [string]$Snapshot.ErrorMessage
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            method = "native_psapi_fallback"
            succeeded = $false
            module_count = 0
            modules = @()
            error_stage = "native_inspector_initialization"
            error_code = 0
            error_message = $_.Exception.Message
        }
    }
}

function Get-M10VerifyTargetedTsfProcesses {
    $TasklistPath = Join-Path $env:SystemRoot "System32\tasklist.exe"
    $Records = [System.Collections.Generic.List[object]]::new()
    $InformationalOutput = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $TasklistPath -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            method = "targeted_tasklist_module_filter"
            query_succeeded = $false
            query_error = "tasklist.exe is missing"
            process_count = 0
            processes = @()
            informational_output = @()
        }
    }
    try {
        $Output = @(& $TasklistPath `
                /m "YuneWindowsTSF*" `
                /fo csv `
                /nh 2>&1)
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw "tasklist.exe exited with $ExitCode"
        }
        foreach ($LineValue in $Output) {
            $Line = ([string]$LineValue).Trim()
            if ([string]::IsNullOrWhiteSpace($Line)) {
                continue
            }
            if (-not $Line.StartsWith('"')) {
                $InformationalOutput.Add($Line) | Out-Null
                continue
            }
            $Row = $Line | ConvertFrom-Csv -Header ImageName, ProcessId, Modules
            $ParsedProcessId = 0
            if (-not [int]::TryParse(
                    [string]$Row.ProcessId,
                    [ref]$ParsedProcessId) -or
                $ParsedProcessId -le 0 -or
                [string]$Row.Modules -notmatch '(?i)YuneWindowsTSF') {
                throw "tasklist.exe returned an invalid targeted module row"
            }
            if (@($Records | Where-Object {
                        $_.process_id -eq $ParsedProcessId
                    }).Count -eq 0) {
                $Records.Add([pscustomobject][ordered]@{
                        process_id = $ParsedProcessId
                        process_name = [System.IO.Path]::GetFileNameWithoutExtension(
                            [string]$Row.ImageName)
                        reported_modules = [string]$Row.Modules
                    }) | Out-Null
            }
        }
        return [pscustomobject][ordered]@{
            method = "targeted_tasklist_module_filter"
            query_succeeded = $true
            query_error = ""
            process_count = $Records.Count
            processes = @($Records)
            informational_output = @($InformationalOutput)
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            method = "targeted_tasklist_module_filter"
            query_succeeded = $false
            query_error = $_.Exception.Message
            process_count = 0
            processes = @()
            informational_output = @($InformationalOutput)
        }
    }
}

function Get-M10VerifyToolProvenance {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    $ResolvedScriptPath = Resolve-M10VerifyFullPath $ScriptPath
    $RepoRoot = Resolve-M10VerifyFullPath (
        Join-Path (Split-Path -Parent $ResolvedScriptPath) "..\..")
    $RepositoryDetected = Test-Path -LiteralPath (
        Join-Path $RepoRoot ".git")
    $ToolingCommit = ""
    $GitQueryError = ""
    $WorkingTreeClean = $false
    $VerifierMatchesToolingCommit = $false
    $RelativeScriptPath = $ResolvedScriptPath.Substring(
        $RepoRoot.TrimEnd("\").Length).TrimStart("\").Replace("\", "/")
    if ($RepositoryDetected) {
        try {
            $ToolingCommit = (& git -C $RepoRoot rev-parse HEAD 2>&1 |
                    Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or
                $ToolingCommit -notmatch '^[A-Fa-f0-9]{40}$') {
                throw "git rev-parse HEAD did not return a full commit"
            }
            $Status = (& git -C $RepoRoot status --porcelain `
                    --untracked-files=all 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) {
                throw "git status failed"
            }
            $WorkingTreeClean = [string]::IsNullOrWhiteSpace($Status)
            $TrackedPath = (& git -C $RepoRoot ls-files `
                    --error-unmatch `
                    -- $RelativeScriptPath 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and
                -not [string]::IsNullOrWhiteSpace($TrackedPath)) {
                & git -C $RepoRoot diff --quiet `
                    HEAD `
                    -- $RelativeScriptPath
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
                    throw "git diff --quiet failed"
                }
                $VerifierMatchesToolingCommit = $LASTEXITCODE -eq 0
            }
        }
        catch {
            $GitQueryError = $_.Exception.Message
            $ToolingCommit = ""
        }
    }
    return [pscustomobject][ordered]@{
        verifier_script_path = $ResolvedScriptPath
        verifier_repo_relative_path = $RelativeScriptPath
        verifier_script_sha256 = (Get-FileHash `
                -Algorithm SHA256 `
                -LiteralPath $ResolvedScriptPath).Hash
        repository_root = $RepoRoot
        repository_detected = $RepositoryDetected
        tooling_source_commit = $ToolingCommit
        tooling_source_commit_known =
            $ToolingCommit -match '^[A-Fa-f0-9]{40}$'
        verifier_matches_tooling_commit = $VerifierMatchesToolingCommit
        working_tree_clean = $WorkingTreeClean
        git_query_error = $GitQueryError
    }
}

function Get-M10VerifyTsfHolders {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$TsfPath,
        [Parameter(Mandatory = $true)][long]$ExpectedImageSize,
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$DeploymentCompletedAt
    )

    $ExpectedPath = Resolve-M10VerifyFullPath $TsfPath
    $Holders = [System.Collections.Generic.List[object]]::new()
    $EnumerationFailures = [System.Collections.Generic.List[object]]::new()
    $ExitedBeforeEnumeration = [System.Collections.Generic.List[object]]::new()
    $FallbackAttempts = [System.Collections.Generic.List[object]]::new()
    $TargetedUnresolved = [System.Collections.Generic.List[object]]::new()
    $TargetedScan = Get-M10VerifyTargetedTsfProcesses
    $TargetedByPid = @{}
    foreach ($Record in @($TargetedScan.processes)) {
        $TargetedByPid[[int]$Record.process_id] = $Record
    }

    $CurrentSessionId = [int](Get-Process -Id $PID -ErrorAction Stop).SessionId
    $ProcessByPid = @{}
    foreach ($InitialProcess in @(Get-Process -ErrorAction Stop | Where-Object {
                [int]$_.SessionId -eq $CurrentSessionId -and [int]$_.Id -ne 0
            })) {
        $ProcessByPid[[int]$InitialProcess.Id] = $InitialProcess
    }
    # A targeted scan is system-wide. Add any reported holder outside the
    # current session so its mapped path and image size are still checked.
    foreach ($TargetedProcessId in @($TargetedByPid.Keys)) {
        if (-not $ProcessByPid.ContainsKey([int]$TargetedProcessId)) {
            $TargetedProcess = Get-Process `
                -Id ([int]$TargetedProcessId) `
                -ErrorAction SilentlyContinue
            if ($null -ne $TargetedProcess) {
                $ProcessByPid[[int]$TargetedProcessId] = $TargetedProcess
            }
        }
    }
    $Processes = @($ProcessByPid.Values)
    $EnumerationSucceeded = 0
    $ManagedAccepted = 0
    $NativeFallbackSucceeded = 0
    $SuspiciousManagedCount = 0

    foreach ($InitialProcess in $Processes) {
        $ProcessId = [int]$InitialProcess.Id
        $ProcessName = [string]$InitialProcess.ProcessName
        $IsTargeted = $TargetedByPid.ContainsKey($ProcessId)
        $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -eq $Process) {
            $ExitedBeforeEnumeration.Add([pscustomobject][ordered]@{
                    process_id = $ProcessId
                    process_name = $ProcessName
                    targeted_by_tasklist = $IsTargeted
                    category = "process_exited"
                }) | Out-Null
            continue
        }

        $ManagedError = ""
        $ManagedModules = @()
        try {
            $ManagedModules = @($Process.Modules)
        }
        catch {
            $ManagedError = $_.Exception.Message
        }
        $ManagedCount = $ManagedModules.Count
        $EnumerationMethod = "managed_process_modules"
        $ModuleRecords = @()
        if ([string]::IsNullOrWhiteSpace($ManagedError) -and
            (Test-M10VerifyManagedModuleSnapshotComplete `
                -ModuleCount $ManagedCount)) {
            $ManagedAccepted += 1
            $ModuleRecords = @($ManagedModules | ForEach-Object {
                    [pscustomobject][ordered]@{
                        file_name = [string]$_.FileName
                        module_memory_size = [long]$_.ModuleMemorySize
                    }
                })
        }
        else {
            $Trigger = if ([string]::IsNullOrWhiteSpace($ManagedError)) {
                $SuspiciousManagedCount += 1
                "suspicious_managed_module_count"
            }
            else {
                "managed_module_exception"
            }
            $NativeSnapshot = Get-M10VerifyNativeModuleSnapshot `
                -ProcessId $ProcessId
            $FallbackAttempts.Add([pscustomobject][ordered]@{
                    process_id = $ProcessId
                    process_name = $ProcessName
                    targeted_by_tasklist = $IsTargeted
                    trigger = $Trigger
                    managed_module_count = $ManagedCount
                    managed_error = $ManagedError
                    fallback_method = $NativeSnapshot.method
                    fallback_succeeded = $NativeSnapshot.succeeded
                    fallback_module_count = $NativeSnapshot.module_count
                    fallback_error_stage = $NativeSnapshot.error_stage
                    fallback_error_code = $NativeSnapshot.error_code
                    fallback_error_message = $NativeSnapshot.error_message
                }) | Out-Null
            if ($NativeSnapshot.succeeded) {
                $EnumerationMethod = $NativeSnapshot.method
                $NativeFallbackSucceeded += 1
                $ModuleRecords = @($NativeSnapshot.modules)
            }
            else {
                $StillExists = $null -ne (Get-Process `
                        -Id $ProcessId `
                        -ErrorAction SilentlyContinue)
                if (-not $StillExists) {
                    $ExitedBeforeEnumeration.Add([pscustomobject][ordered]@{
                            process_id = $ProcessId
                            process_name = $ProcessName
                            targeted_by_tasklist = $IsTargeted
                            category = "process_exited"
                        }) | Out-Null
                    continue
                }
                $Failure = [pscustomobject][ordered]@{
                    process_id = $ProcessId
                    process_name = $ProcessName
                    targeted_by_tasklist = $IsTargeted
                    category = if ($Trigger -eq
                        "suspicious_managed_module_count") {
                        "suspicious_partial_enumeration_native_fallback_failed"
                    }
                    else {
                        "managed_and_native_enumeration_failed"
                    }
                    managed_module_count = $ManagedCount
                    managed_error = $ManagedError
                    fallback_method = $NativeSnapshot.method
                    fallback_error_stage = $NativeSnapshot.error_stage
                    fallback_error_code = $NativeSnapshot.error_code
                    fallback_error_message = $NativeSnapshot.error_message
                }
                $EnumerationFailures.Add($Failure) | Out-Null
                if ($IsTargeted) {
                    $TargetedUnresolved.Add($Failure) | Out-Null
                }
                continue
            }
        }

        $EnumerationSucceeded += 1
        $FoundTsfModule = $false
        foreach ($Module in $ModuleRecords) {
            if ([string]::IsNullOrWhiteSpace([string]$Module.file_name)) {
                continue
            }
            $ModulePath = Resolve-M10VerifyFullPath ([string]$Module.file_name)
            $IsCurrentPath = [string]::Equals(
                $ModulePath,
                $ExpectedPath,
                [System.StringComparison]::OrdinalIgnoreCase)
            $IsUnderInstallRoot = Test-M10VerifyPathUnderRoot `
                -Path $ModulePath `
                -Root $InstallRoot
            $ModuleLeaf = [System.IO.Path]::GetFileName($ModulePath)
            $IsTsfImage = $ModuleLeaf.StartsWith(
                "YuneWindowsTSF.dll",
                [System.StringComparison]::OrdinalIgnoreCase)
            $IsInstallRootTsfImage = $IsUnderInstallRoot -and $IsTsfImage
            if (-not $IsTsfImage) {
                continue
            }
            $FoundTsfModule = $true
            $ProcessPath = ""
            $StartedAt = ""
            try { $ProcessPath = [string]$Process.Path } catch {}
            try { $StartedAt = $Process.StartTime.ToString("o") } catch {}
            $StartState = Get-M10VerifyStartState `
                -StartedAt $StartedAt `
                -DeploymentCompletedAt $DeploymentCompletedAt
            $ModuleSize = [long]$Module.module_memory_size
            $Holders.Add([pscustomobject][ordered]@{
                    process_id = [int]$Process.Id
                    process_name = [string]$Process.ProcessName
                    process_path = $ProcessPath
                    process_started_at = $StartState.process_started_at
                    start_time_known = $StartState.start_time_known
                    started_strictly_after_deployment =
                        $StartState.started_strictly_after_deployment
                    enumeration_method = $EnumerationMethod
                    targeted_by_tasklist = $IsTargeted
                    module_path = $ModulePath
                    module_path_kind = if ($IsCurrentPath) {
                        "current_installed_path"
                    }
                    elseif ($IsInstallRootTsfImage) {
                        "install_root_old_or_aside_path"
                    }
                    else {
                        "other_path"
                    }
                    is_current_installed_path = $IsCurrentPath
                    is_install_root_old_or_aside_path =
                        -not $IsCurrentPath -and $IsInstallRootTsfImage
                    is_other_path =
                        -not $IsCurrentPath -and -not $IsInstallRootTsfImage
                    module_memory_size = $ModuleSize
                    matches_candidate_image_size =
                        $ModuleSize -eq $ExpectedImageSize
                }) | Out-Null
            break
        }
        # A complete detail scan that no longer sees the tasklist-reported
        # module is an unload race, not an unresolved partial enumeration.
        if ($IsTargeted -and -not $FoundTsfModule) {
            $ExitedBeforeEnumeration.Add([pscustomobject][ordered]@{
                    process_id = $ProcessId
                    process_name = $ProcessName
                    targeted_by_tasklist = $true
                    category = "target_module_unloaded_before_detail_scan"
                }) | Out-Null
        }
    }

    $TargetedCoverageComplete = $TargetedScan.query_succeeded -and
        $TargetedUnresolved.Count -eq 0
    return [pscustomobject][ordered]@{
        holders = @($Holders)
        coverage = [pscustomobject][ordered]@{
            scope =
                "targeted_yune_tsf_modules_plus_current_session_inventory"
            session_id = $CurrentSessionId
            methods = @(
                "managed_process_modules",
                "native_psapi_fallback",
                "targeted_tasklist_module_filter")
            targeted_scan = $TargetedScan
            targeted_coverage_complete = $TargetedCoverageComplete
            targeted_unresolved_count = $TargetedUnresolved.Count
            targeted_unresolved = @($TargetedUnresolved)
            total_processes_considered = $Processes.Count
            module_enumeration_succeeded = $EnumerationSucceeded
            managed_enumeration_accepted = $ManagedAccepted
            suspicious_managed_module_count = $SuspiciousManagedCount
            native_fallback_attempted = $FallbackAttempts.Count
            native_fallback_succeeded = $NativeFallbackSucceeded
            exited_before_enumeration_count = $ExitedBeforeEnumeration.Count
            module_enumeration_failure_count = $EnumerationFailures.Count
            current_session_inventory_complete =
                $EnumerationFailures.Count -eq 0
            coverage_incomplete = -not $TargetedCoverageComplete
            exited_before_enumeration = @($ExitedBeforeEnumeration)
            fallback_attempts = @($FallbackAttempts)
            enumeration_failures = @($EnumerationFailures)
        }
    }
}

function Get-M10VerifyNamedProcesses {
    param(
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [Parameter(Mandatory = $true)][string]$ExpectedPath,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$InstalledLeafPrefix,
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$DeploymentCompletedAt
    )

    $ExpectedPath = Resolve-M10VerifyFullPath $ExpectedPath
    $Records = [System.Collections.Generic.List[object]]::new()
    foreach ($Process in @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {
        $ProcessPath = ""
        $StartedAt = ""
        try { $ProcessPath = [string]$Process.Path } catch {}
        try { $StartedAt = $Process.StartTime.ToString("o") } catch {}
        $PathKnown = -not [string]::IsNullOrWhiteSpace($ProcessPath)
        $IsCurrentPath = $false
        $IsInstallRootOldOrAsidePath = $false
        $PathKind = "unknown"
        if ($PathKnown) {
            $ProcessPath = Resolve-M10VerifyFullPath $ProcessPath
            $IsCurrentPath = [string]::Equals(
                $ProcessPath,
                $ExpectedPath,
                [System.StringComparison]::OrdinalIgnoreCase)
            $IsUnderInstallRoot = Test-M10VerifyPathUnderRoot `
                -Path $ProcessPath `
                -Root $InstallRoot
            $Leaf = [System.IO.Path]::GetFileName($ProcessPath)
            $IsInstallRootOldOrAsidePath = -not $IsCurrentPath -and
                $IsUnderInstallRoot -and
                $Leaf.StartsWith(
                    $InstalledLeafPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase)
            $PathKind = if ($IsCurrentPath) {
                "current_installed_path"
            }
            elseif ($IsInstallRootOldOrAsidePath) {
                "install_root_old_or_aside_path"
            }
            else {
                "other_path"
            }
        }
        $StartState = Get-M10VerifyStartState `
            -StartedAt $StartedAt `
            -DeploymentCompletedAt $DeploymentCompletedAt
        $Records.Add([pscustomobject][ordered]@{
                process_id = [int]$Process.Id
                process_name = [string]$Process.ProcessName
                process_path = $ProcessPath
                path_known = $PathKnown
                path_kind = $PathKind
                is_current_installed_path = $IsCurrentPath
                is_install_root_old_or_aside_path =
                    $IsInstallRootOldOrAsidePath
                process_started_at = $StartState.process_started_at
                start_time_known = $StartState.start_time_known
                started_strictly_after_deployment =
                    $StartState.started_strictly_after_deployment
            }) | Out-Null
    }
    return @($Records)
}

function Get-M10VerifyPendingDeleteState {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $Matches = [System.Collections.Generic.List[string]]::new()
    $ReadError = ""
    try {
        $SessionManager =
            "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager"
        $Value = (Get-ItemProperty `
                -LiteralPath $SessionManager `
                -Name PendingFileRenameOperations `
                -ErrorAction SilentlyContinue).PendingFileRenameOperations
        foreach ($Entry in @($Value)) {
            $Text = [string]$Entry
            $Comparable = $Text -replace '^\\\?\?\\', ''
            if ($Comparable.StartsWith(
                    $InstallRoot,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                $Matches.Add($Text) | Out-Null
            }
        }
    }
    catch {
        $ReadError = $_.Exception.Message
    }
    return [pscustomobject][ordered]@{
        read_succeeded = [string]::IsNullOrWhiteSpace($ReadError)
        read_error = $ReadError
        install_root_entry_count = $Matches.Count
        install_root_entries = @($Matches)
    }
}

function Get-M10VerifyProfileState {
    param([Parameter(Mandatory = $true)][string]$ProfileTool)

    $Record = [ordered]@{
        available = Test-Path -LiteralPath $ProfileTool -PathType Leaf
        query_succeeded = $false
        registered = $false
        active = $false
        langid = 0
        profile_guid = ""
        clsid = ""
        error = ""
    }
    if (-not $Record.available) {
        $Record.error = "installed profile tool is missing"
        return [pscustomobject]$Record
    }
    try {
        $Text = (& $ProfileTool --state 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "profile state command exited with $LASTEXITCODE"
        }
        $State = $Text | ConvertFrom-Json
        $Record.query_succeeded = $true
        $Record.registered = [bool]$State.registered
        $Record.active = [bool]$State.active
        $Record.langid = [int]$State.langid
        $Record.profile_guid = [string]$State.profile_guid
        $Record.clsid = [string]$State.clsid
    }
    catch {
        $Record.error = $_.Exception.Message
    }
    return [pscustomobject]$Record
}

function Get-M10VerifyComState {
    param([Parameter(Mandatory = $true)][string]$ExpectedTsfPath)

    $KeyPath =
        "Registry::HKEY_CLASSES_ROOT\CLSID\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\InprocServer32"
    $Record = [ordered]@{
        key_path = $KeyPath
        key_exists = Test-Path -LiteralPath $KeyPath
        registered_path = ""
        expected_path = $ExpectedTsfPath
        path_matches = $false
        threading_model = ""
        error = ""
    }
    if (-not $Record.key_exists) {
        $Record.error = "COM InprocServer32 key is missing"
        return [pscustomobject]$Record
    }
    try {
        $Key = Get-Item -LiteralPath $KeyPath
        $Record.registered_path = [string]$Key.GetValue("")
        $Record.threading_model = [string]$Key.GetValue("ThreadingModel")
        $Record.path_matches = [string]::Equals(
            (Resolve-M10VerifyFullPath $Record.registered_path),
            (Resolve-M10VerifyFullPath $ExpectedTsfPath),
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        $Record.error = $_.Exception.Message
    }
    return [pscustomobject]$Record
}

$ManifestPath = Resolve-M10VerifyFullPath $CandidateManifest
$InstallRoot = Resolve-M10VerifyFullPath $InstallDir
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "candidate manifest is missing: $ManifestPath"
}
$ManifestBytes = [System.IO.File]::ReadAllBytes($ManifestPath)
$Hasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $ManifestSha256 = [System.BitConverter]::ToString(
        $Hasher.ComputeHash($ManifestBytes)).Replace("-", "")
}
finally {
    $Hasher.Dispose()
}
$ManifestStream = [System.IO.MemoryStream]::new($ManifestBytes, $false)
$ManifestReader = [System.IO.StreamReader]::new(
    $ManifestStream,
    [System.Text.Encoding]::UTF8,
    $true)
try {
    $ManifestText = $ManifestReader.ReadToEnd()
}
finally {
    $ManifestReader.Dispose()
    $ManifestStream.Dispose()
}
$Manifest = $ManifestText | ConvertFrom-Json
$null = Assert-M10VerifyDurableManifestPath `
    -Manifest $Manifest `
    -ManifestPath $ManifestPath
$ManifestSourceCommit = [string]$Manifest.source.actual_commit
$DeploymentCompletedAtText = [string]$Manifest.deployment.completed_at
$DeploymentCompletedAt = [DateTimeOffset]::MinValue
$DeploymentCompletedAtValid =
    -not [string]::IsNullOrWhiteSpace($DeploymentCompletedAtText) -and
    [DateTimeOffset]::TryParse(
        $DeploymentCompletedAtText,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$DeploymentCompletedAt)
Assert-M10VerifyManifestAdmission `
    -Manifest $Manifest `
    -DeploymentCompletedAtValid $DeploymentCompletedAtValid
$RestartBoundary = Get-M10VerifyOperatingSystemBootBoundary `
    -DeploymentCompletedAt $DeploymentCompletedAt
$ToolProvenance = Get-M10VerifyToolProvenance -ScriptPath $PSCommandPath

$ArtifactByName = @{}
foreach ($Artifact in @($Manifest.build.artifacts)) {
    $Name = [string]$Artifact.name
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        if ($ArtifactByName.ContainsKey($Name)) {
            throw "candidate manifest contains duplicate artifact: $Name"
        }
        $ArtifactByName[$Name] = $Artifact
    }
}
foreach ($RequiredName in @("server", "tsf", "settings", "profile", "default_skin")) {
    if (-not $ArtifactByName.ContainsKey($RequiredName) -or
        [string]$ArtifactByName[$RequiredName].sha256 -notmatch
            '^[A-Fa-f0-9]{64}$') {
        throw "candidate manifest is missing artifact hash: $RequiredName"
    }
}
if ([string]$Manifest.package.rime.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "candidate manifest is missing packaged rime.dll provenance"
}

$InstalledPaths = [ordered]@{
    server = Join-Path $InstallRoot "YuneWindowsServer.exe"
    tsf = Join-Path $InstallRoot "YuneWindowsTSF.dll"
    settings = Join-Path $InstallRoot "YuneWindowsSettings.exe"
    profile = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"
    default_skin = Join-Path $InstallRoot "skins\default\theme.json"
    rime = Join-Path $InstallRoot "rime.dll"
}
$InstalledArtifacts = @(
    Get-M10VerifyFileRecord -Name "server" -Path $InstalledPaths.server -ExpectedHash ([string]$ArtifactByName.server.sha256)
    Get-M10VerifyFileRecord -Name "tsf" -Path $InstalledPaths.tsf -ExpectedHash ([string]$ArtifactByName.tsf.sha256)
    Get-M10VerifyFileRecord -Name "settings" -Path $InstalledPaths.settings -ExpectedHash ([string]$ArtifactByName.settings.sha256)
    Get-M10VerifyFileRecord -Name "profile" -Path $InstalledPaths.profile -ExpectedHash ([string]$ArtifactByName.profile.sha256)
    Get-M10VerifyFileRecord -Name "default_skin" -Path $InstalledPaths.default_skin -ExpectedHash ([string]$ArtifactByName.default_skin.sha256)
    Get-M10VerifyFileRecord -Name "rime" -Path $InstalledPaths.rime -ExpectedHash ([string]$Manifest.package.rime.sha256)
)

$ExpectedImageSize = [long]$Manifest.build.tsf_pe_size_of_image
$InstalledImageSize = Get-M10VerifyPeSizeOfImage -Path $InstalledPaths.tsf
$TsfScan = Get-M10VerifyTsfHolders `
        -InstallRoot $InstallRoot `
        -TsfPath $InstalledPaths.tsf `
        -ExpectedImageSize $ExpectedImageSize `
        -DeploymentCompletedAt $DeploymentCompletedAt
$Holders = @($TsfScan.holders)
$HolderCoverage = $TsfScan.coverage
$ServerProcesses = @(Get-M10VerifyNamedProcesses `
        -ProcessName "YuneWindowsServer" `
        -ExpectedPath $InstalledPaths.server `
        -InstallRoot $InstallRoot `
        -InstalledLeafPrefix "YuneWindowsServer.exe" `
        -DeploymentCompletedAt $DeploymentCompletedAt)
$SettingsProcesses = @(Get-M10VerifyNamedProcesses `
        -ProcessName "YuneWindowsSettings" `
        -ExpectedPath $InstalledPaths.settings `
        -InstallRoot $InstallRoot `
        -InstalledLeafPrefix "YuneWindowsSettings.exe" `
        -DeploymentCompletedAt $DeploymentCompletedAt)
$InstalledServerProcesses = @($ServerProcesses | Where-Object {
        $_.is_current_installed_path
    })
$OldOrAsideServerProcesses = @($ServerProcesses | Where-Object {
        $_.is_install_root_old_or_aside_path
    })
$UnknownServerProcesses = @($ServerProcesses | Where-Object {
        -not $_.path_known
    })
$InstalledSettingsProcesses = @($SettingsProcesses | Where-Object {
        $_.is_current_installed_path
    })
$OldOrAsideSettingsProcesses = @($SettingsProcesses | Where-Object {
        $_.is_install_root_old_or_aside_path
    })
$UnknownSettingsProcesses = @($SettingsProcesses | Where-Object {
        -not $_.path_known
    })
$PendingDelete = Get-M10VerifyPendingDeleteState -InstallRoot $InstallRoot
$ProfileState = Get-M10VerifyProfileState -ProfileTool $InstalledPaths.profile
$ComState = Get-M10VerifyComState -ExpectedTsfPath $InstalledPaths.tsf
$AsideEntries = @(Get-ChildItem `
        -LiteralPath $InstallRoot `
        -Filter "*.m10-*" `
        -Force `
        -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject][ordered]@{
                name = $_.Name
                is_directory = [bool]$_.PSIsContainer
                length = if ($_.PSIsContainer) { 0 } else { [long]$_.Length }
            }
        })

$Failures = [System.Collections.Generic.List[string]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()
if (-not $RestartBoundary.proof_complete) {
    $Failures.Add(
        "operating-system boot time is not known to be strictly after candidate deployment completion") | Out-Null
}
if (-not $ToolProvenance.repository_detected -or
    -not $ToolProvenance.tooling_source_commit_known -or
    -not $ToolProvenance.verifier_matches_tooling_commit -or
    -not $ToolProvenance.working_tree_clean) {
    $Failures.Add(
        "verifier script is not pinned to a clean recorded tooling source commit") | Out-Null
}
foreach ($Artifact in $InstalledArtifacts) {
    if (-not $Artifact.matches_candidate) {
        $Failures.Add("installed artifact mismatch: $($Artifact.name)") | Out-Null
    }
}
if ($ExpectedImageSize -le 0 -or $InstalledImageSize -ne $ExpectedImageSize) {
    $Failures.Add("installed TSF PE SizeOfImage does not match candidate") | Out-Null
}
if (-not $PendingDelete.read_succeeded -or
    $PendingDelete.install_root_entry_count -gt 0) {
    $Failures.Add("install root has unverifiable or pending delete state") | Out-Null
}
if (-not $ProfileState.query_succeeded -or
    -not $ProfileState.registered -or
    -not $ProfileState.active) {
    $Failures.Add("Yune Windows profile is not registered and active") | Out-Null
}
if (-not $ComState.path_matches) {
    $Failures.Add("COM InprocServer32 path does not match installed TSF") | Out-Null
}
if ($HolderCoverage.coverage_incomplete) {
    $Failures.Add(
        "targeted TSF holder scan is incomplete; tasklist-reported holders must have complete module details") | Out-Null
}
if (-not $HolderCoverage.current_session_inventory_complete) {
    if ($RestartBoundary.proof_complete -and
        $HolderCoverage.targeted_coverage_complete) {
        $Warnings.Add(
            "current-session module inventory contains explicitly recorded access limitations; strict OS boot proof plus complete targeted holder details supply stale-process exclusion") | Out-Null
    }
    else {
        $Failures.Add(
            "current-session module inventory is incomplete without both strict OS boot proof and complete targeted holder details") | Out-Null
    }
}
if ($Holders.Count -eq 0 -and -not $AllowNoHolders) {
    $Failures.Add("no mapped installed TSF holder was available for post-restart proof") | Out-Null
}
foreach ($Holder in $Holders) {
    if (-not $Holder.matches_candidate_image_size) {
        $Failures.Add(
            "mapped TSF holder has a different PE image size: $($Holder.process_name)[$($Holder.process_id)]") | Out-Null
    }
    if (-not $Holder.is_current_installed_path) {
        $Failures.Add(
            "mapped TSF holder uses a non-current path: $($Holder.process_name)[$($Holder.process_id)]") | Out-Null
    }
    if (-not $Holder.start_time_known) {
        $Failures.Add(
            "mapped TSF holder has an unknown process start time: $($Holder.process_name)[$($Holder.process_id)]") | Out-Null
    }
    elseif (-not $Holder.started_strictly_after_deployment) {
        $Failures.Add(
            "mapped TSF holder predates candidate deployment completion: $($Holder.process_name)[$($Holder.process_id)]") | Out-Null
    }
}
if ($InstalledServerProcesses.Count -ne 1) {
    $Failures.Add(
        "post-restart proof requires exactly one running installed-path YuneWindowsServer; found $($InstalledServerProcesses.Count)") | Out-Null
}
if ($OldOrAsideServerProcesses.Count -gt 0) {
    $Failures.Add("old/aside install-root YuneWindowsServer process remains") | Out-Null
}
if ($UnknownServerProcesses.Count -gt 0) {
    $Failures.Add("YuneWindowsServer process path could not be verified") | Out-Null
}
foreach ($Process in $InstalledServerProcesses) {
    if (-not $Process.start_time_known) {
        $Failures.Add("installed YuneWindowsServer start time is unknown") | Out-Null
    }
    elseif (-not $Process.started_strictly_after_deployment) {
        $Failures.Add("installed YuneWindowsServer predates deployment completion") | Out-Null
    }
}
if ($OldOrAsideSettingsProcesses.Count -gt 0) {
    $Failures.Add("old/aside install-root YuneWindowsSettings process remains") | Out-Null
}
if ($UnknownSettingsProcesses.Count -gt 0) {
    $Failures.Add("YuneWindowsSettings process path could not be verified") | Out-Null
}
foreach ($Process in $InstalledSettingsProcesses) {
    if (-not $Process.start_time_known) {
        $Failures.Add("installed YuneWindowsSettings start time is unknown") | Out-Null
    }
    elseif (-not $Process.started_strictly_after_deployment) {
        $Failures.Add("installed YuneWindowsSettings predates deployment completion") | Out-Null
    }
}

$Result = [ordered]@{
    schema_version = 1
    operation = "m10_frozen_candidate_post_restart_verify"
    captured_at = [DateTimeOffset]::Now.ToString("o")
    privacy_note = "Records artifact hashes, boot time, verifier provenance, registration state, process identity/path/start time, and module sizes only; no window titles, typed text, composition text, or arbitrary keystrokes are read."
    tooling = $ToolProvenance
    restart_boundary = $RestartBoundary
    candidate = [ordered]@{
        manifest_path = $ManifestPath
        manifest_sha256 = $ManifestSha256
        deployment_status = [string]$Manifest.status
        deployment_error = [string]$Manifest.deployment.error
        deployment_performed = [bool]$Manifest.deployment.performed
        rollback_attempted = [bool]$Manifest.deployment.rollback_attempted
        rollback_complete = [bool]$Manifest.deployment.rollback_complete
        source_expected_commit = [string]$Manifest.source.expected_commit
        source_actual_commit = $ManifestSourceCommit
        source_clean = [bool]$Manifest.source.clean
        source_post_build_verified = [bool]$Manifest.source.post_build_verified
        package_post_build_verified = [bool]$Manifest.package.post_build_verified
        build_output_dir = [string]$Manifest.build.output_dir
        tsf_pe_size_of_image = $ExpectedImageSize
        deployment_started_at = [string]$Manifest.deployment.started_at
        deployment_completed_at = $DeploymentCompletedAtText
        deployment_completed_at_valid = $DeploymentCompletedAtValid
    }
    installed = [ordered]@{
        install_dir = $InstallRoot
        artifacts = $InstalledArtifacts
        tsf_pe_size_of_image = $InstalledImageSize
        pending_delete = $PendingDelete
        profile = $ProfileState
        com_registration = $ComState
        aside_entry_count = $AsideEntries.Count
        aside_entries = $AsideEntries
    }
    holders = [ordered]@{
        allow_no_holders = [bool]$AllowNoHolders
        coverage_complete =
            [bool]$HolderCoverage.targeted_coverage_complete
        current_session_inventory_complete =
            [bool]$HolderCoverage.current_session_inventory_complete
        coverage = $HolderCoverage
        count = $Holders.Count
        current_installed_path_count = @($Holders | Where-Object {
                $_.is_current_installed_path
            }).Count
        old_or_aside_install_root_path_count = @($Holders | Where-Object {
                $_.is_install_root_old_or_aside_path
            }).Count
        other_path_count = @($Holders | Where-Object {
                $_.is_other_path
            }).Count
        expected_module_memory_size = $ExpectedImageSize
        all_match_candidate_image_size =
            @($Holders | Where-Object {
                    -not $_.matches_candidate_image_size
                }).Count -eq 0
        all_use_current_installed_path =
            @($Holders | Where-Object {
                    -not $_.is_current_installed_path
                }).Count -eq 0
        all_start_times_known =
            @($Holders | Where-Object {
                    -not $_.start_time_known
                }).Count -eq 0
        all_started_strictly_after_deployment =
            @($Holders | Where-Object {
                    -not $_.started_strictly_after_deployment
                }).Count -eq 0
        entries = @($Holders)
    }
    installed_processes = [ordered]@{
        server = [ordered]@{
            expected_path = $InstalledPaths.server
            current_installed_path_count = $InstalledServerProcesses.Count
            old_or_aside_install_root_path_count =
                $OldOrAsideServerProcesses.Count
            unknown_path_count = $UnknownServerProcesses.Count
            exactly_one_running_installed_server =
                $InstalledServerProcesses.Count -eq 1
            no_old_or_aside_processes =
                $OldOrAsideServerProcesses.Count -eq 0
            all_installed_start_times_known =
                @($InstalledServerProcesses | Where-Object {
                        -not $_.start_time_known
                    }).Count -eq 0
            all_installed_started_strictly_after_deployment =
                @($InstalledServerProcesses | Where-Object {
                        -not $_.started_strictly_after_deployment
                    }).Count -eq 0
            entries = @($ServerProcesses)
        }
        settings = [ordered]@{
            expected_path = $InstalledPaths.settings
            current_installed_path_count = $InstalledSettingsProcesses.Count
            old_or_aside_install_root_path_count =
                $OldOrAsideSettingsProcesses.Count
            unknown_path_count = $UnknownSettingsProcesses.Count
            optional = $true
            no_old_or_aside_processes =
                $OldOrAsideSettingsProcesses.Count -eq 0
            all_installed_start_times_known =
                @($InstalledSettingsProcesses | Where-Object {
                        -not $_.start_time_known
                    }).Count -eq 0
            all_installed_started_strictly_after_deployment =
                @($InstalledSettingsProcesses | Where-Object {
                        -not $_.started_strictly_after_deployment
                    }).Count -eq 0
            entries = @($SettingsProcesses)
        }
    }
    warnings = @($Warnings)
    failures = @($Failures)
    pass = $Failures.Count -eq 0
}

$Json = $Result | ConvertTo-Json -Depth 12
Write-Output $Json
if (-not $Result.pass) {
    throw "M10 frozen candidate post-restart verification failed: $($Failures -join '; ')"
}
