$ErrorActionPreference = "Stop"

$script:YuneWindowsDevDefaultPipeName = "\\.\pipe\yune-windows-ime-dev"
$script:YuneWindowsDevDefaultInstallDir = Join-Path $env:LOCALAPPDATA "Yune\WindowsIme"
$script:YuneWindowsDevDefaultStateRoot = Join-Path $env:TEMP "yune-windows"
$script:YuneWindowsDevDefaultTestWindowStatePath = Join-Path $script:YuneWindowsDevDefaultStateRoot "dev-test-window.json"

function Resolve-YuneWindowsDevFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function ConvertTo-YuneWindowsDevPipeClientName {
    param([Parameter(Mandatory = $true)][string]$PipeName)

    if ($PipeName.StartsWith("\\.\pipe\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $PipeName.Substring("\\.\pipe\".Length)
    }
    return $PipeName
}

function Test-YuneWindowsDevPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [ValidateSet("Leaf", "Container")][string]$PathType
    )

    if (-not (Test-Path -LiteralPath $Path -PathType $PathType)) {
        throw "missing ${Description}: $Path"
    }
}

function New-YuneWindowsDevTimestamp {
    return (Get-Date).ToString("yyyyMMdd-HHmmss")
}

function New-YuneWindowsDevScratchRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Purpose,
        [string]$ScratchRoot = ""
    )

    if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
        $ScratchRoot = Join-Path $script:YuneWindowsDevDefaultStateRoot (
            "{0}-{1}-{2}" -f $Purpose, $PID, [Guid]::NewGuid().ToString("N").Substring(0, 8))
    }
    $ScratchRoot = Resolve-YuneWindowsDevFullPath $ScratchRoot
    New-Item -Path $ScratchRoot -ItemType Directory -Force | Out-Null
    return $ScratchRoot
}

function Backup-YuneWindowsDevPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Timestamp = (New-YuneWindowsDevTimestamp)
    )

    $FullPath = Resolve-YuneWindowsDevFullPath $Path
    $Parent = Split-Path -Parent $FullPath
    $Leaf = Split-Path -Leaf $FullPath
    $BackupPath = Join-Path $Parent ("{0}.dev-backup-{1}-{2}" -f $Leaf, $Label, $Timestamp)

    if (-not (Test-Path -LiteralPath $FullPath)) {
        return [pscustomobject]@{
            path = $FullPath
            backup_path = $BackupPath
            existed = $false
            label = $Label
        }
    }

    if (Test-Path -LiteralPath $FullPath -PathType Container) {
        if (Test-Path -LiteralPath $BackupPath) {
            Remove-Item -LiteralPath $BackupPath -Recurse -Force
        }
        Copy-Item -LiteralPath $FullPath -Destination $BackupPath -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $FullPath -Destination $BackupPath -Force
    }

    return [pscustomobject]@{
        path = $FullPath
        backup_path = $BackupPath
        existed = $true
        label = $Label
    }
}

function Restore-YuneWindowsDevPathBackup {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $FullPath = Resolve-YuneWindowsDevFullPath $Path
    $BackupPath = Resolve-YuneWindowsDevFullPath $BackupPath
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        return
    }

    if (Test-Path -LiteralPath $FullPath) {
        if (Test-Path -LiteralPath $FullPath -PathType Container) {
            Remove-Item -LiteralPath $FullPath -Recurse -Force
        }
        else {
            Remove-Item -LiteralPath $FullPath -Force
        }
    }

    if (Test-Path -LiteralPath $BackupPath -PathType Container) {
        Copy-Item -LiteralPath $BackupPath -Destination $FullPath -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $BackupPath -Destination $FullPath -Force
    }
}

function Remove-YuneWindowsDevOldBackups {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Filter,
        [int]$RetainCount = 3
    )

    if ($RetainCount -lt 0) {
        throw "-RetainCount must not be negative"
    }
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }

    $Backups = @(Get-ChildItem -LiteralPath $Directory -Filter $Filter -Force |
        Sort-Object LastWriteTimeUtc -Descending)
    $Removed = [System.Collections.Generic.List[object]]::new()
    foreach ($Backup in @($Backups | Select-Object -Skip $RetainCount)) {
        Remove-Item -LiteralPath $Backup.FullName -Recurse -Force
        $Removed.Add($Backup.FullName) | Out-Null
    }
    return @($Removed)
}

function Get-YuneWindowsDevInstallPaths {
    param([string]$InstallDir = $script:YuneWindowsDevDefaultInstallDir)

    $InstallRoot = Resolve-YuneWindowsDevFullPath $InstallDir
    return [pscustomobject]@{
        install_dir = $InstallRoot
        server_exe = Join-Path $InstallRoot "YuneWindowsServer.exe"
        tsf_dll = Join-Path $InstallRoot "YuneWindowsTSF.dll"
        rime_dll = Join-Path $InstallRoot "rime.dll"
        schema_dir = Join-Path $InstallRoot "schema"
        user_data_dir = Join-Path $InstallRoot "user-data"
    }
}

function Get-YuneWindowsDevPackage {
    param([string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune")

    $YuneRoot = Resolve-YuneWindowsDevFullPath $YuneRoot
    Test-YuneWindowsDevPath -Path $YuneRoot -Description "Yune root" -PathType Container

    $PackageDir = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist"
    $IncludeDir = Join-Path $PackageDir "include"
    $LibDir = Join-Path $PackageDir "lib"
    $ProfileHeader = Join-Path $IncludeDir "rime_yune_windows_profile_api.h"
    $RimeDll = Join-Path $LibDir "rime.dll"
    $SchemaSourceDir = Join-Path $YuneRoot "apps\yune-web\public\schema"

    Test-YuneWindowsDevPath -Path $PackageDir -Description "packaged Yune Windows dist" -PathType Container
    Test-YuneWindowsDevPath -Path $IncludeDir -Description "packaged Yune headers" -PathType Container
    Test-YuneWindowsDevPath -Path $ProfileHeader -Description "Yune Windows profile API header" -PathType Leaf
    Test-YuneWindowsDevPath -Path $RimeDll -Description "packaged rime.dll" -PathType Leaf
    Test-YuneWindowsDevPath -Path $SchemaSourceDir -Description "Yune schema source" -PathType Container
    Test-YuneWindowsDevPath `
        -Path (Join-Path $SchemaSourceDir "jyut6ping3.schema.yaml") `
        -Description "Yune Windows runtime schema entrypoint source" `
        -PathType Leaf
    Test-YuneWindowsDevPath `
        -Path (Join-Path $SchemaSourceDir "jyut6ping3_mobile.schema.yaml") `
        -Description "Yune Windows runtime schema template source" `
        -PathType Leaf
    Test-YuneWindowsDevPath `
        -Path (Join-Path $SchemaSourceDir "build\jyut6ping3_mobile.schema.yaml") `
        -Description "prebuilt Yune Windows runtime schema template source" `
        -PathType Leaf

    return [pscustomobject]@{
        yune_root = $YuneRoot
        package_dir = $PackageDir
        include_dir = $IncludeDir
        profile_header = $ProfileHeader
        rime_dll = $RimeDll
        schema_source_dir = $SchemaSourceDir
    }
}

function Start-YuneWindowsDevScratchServer {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [Parameter(Mandatory = $true)][string]$RimeDll,
        [Parameter(Mandatory = $true)][string]$SharedDir,
        [Parameter(Mandatory = $true)][string]$UserDir,
        [string]$PipeName = $script:YuneWindowsDevDefaultPipeName
    )

    $ServerPath = Resolve-YuneWindowsDevFullPath $ServerPath
    $RimeDll = Resolve-YuneWindowsDevFullPath $RimeDll
    $SharedDir = Resolve-YuneWindowsDevFullPath $SharedDir
    $UserDir = Resolve-YuneWindowsDevFullPath $UserDir

    Test-YuneWindowsDevPath -Path $ServerPath -Description "scratch YuneWindowsServer.exe" -PathType Leaf
    Test-YuneWindowsDevPath -Path $RimeDll -Description "packaged rime.dll" -PathType Leaf
    Test-YuneWindowsDevPath -Path $SharedDir -Description "scratch shared schema directory" -PathType Container
    New-Item -Path $UserDir -ItemType Directory -Force | Out-Null

    return Start-Process -FilePath $ServerPath -ArgumentList @(
        "--rime-dll", $RimeDll,
        "--shared-dir", $SharedDir,
        "--user-dir", $UserDir,
        "--pipe", $PipeName
    ) -WindowStyle Hidden -PassThru
}

function Invoke-YuneWindowsDevServerRawRequest {
    param(
        [Parameter(Mandatory = $true)][string]$PipeName,
        [Parameter(Mandatory = $true)][string]$Payload,
        [System.Diagnostics.Process]$Process = $null,
        [int]$TimeoutMs = 180000
    )

    $PipeClientName = ConvertTo-YuneWindowsDevPipeClientName -PipeName $PipeName
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $LastError = ""

    while ([DateTime]::UtcNow -lt $Deadline) {
        if ($Process -and $Process.HasExited) {
            throw "dev server exited before request completed with exit code $($Process.ExitCode)"
        }

        $Client = $null
        try {
            $Client = [System.IO.Pipes.NamedPipeClientStream]::new(
                ".",
                $PipeClientName,
                [System.IO.Pipes.PipeDirection]::InOut,
                [System.IO.Pipes.PipeOptions]::None)
            $Client.Connect(250)
            $Client.Write($RequestBytes, 0, $RequestBytes.Length)
            $Client.Flush()

            $Buffer = New-Object byte[] 65536
            $RemainingMs = [int][Math]::Max(1, ($Deadline - [DateTime]::UtcNow).TotalMilliseconds)
            $ReadTask = $Client.ReadAsync($Buffer, 0, $Buffer.Length)
            if (-not $ReadTask.Wait($RemainingMs)) {
                $LastError = "timed out reading response"
                continue
            }

            $BytesRead = $ReadTask.Result
            if ($BytesRead -le 0) {
                $LastError = "empty response"
                continue
            }

            $Response = [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $BytesRead)
            return ($Response | ConvertFrom-Json)
        }
        catch {
            $LastError = $_.Exception.Message
            Start-Sleep -Milliseconds 100
        }
        finally {
            if ($Client) {
                $Client.Dispose()
            }
        }
    }

    throw "timed out waiting for dev server response on $PipeName. Last error: $LastError"
}

function Invoke-YuneWindowsDevServerRequest {
    param(
        [Parameter(Mandatory = $true)][string]$PipeName,
        [Parameter(Mandatory = $true)][string]$InputText,
        [bool]$Commit = $false,
        [System.Diagnostics.Process]$Process = $null,
        [int]$TimeoutMs = 180000
    )

    $CommitFlag = if ($Commit) { "1" } else { "0" }
    return Invoke-YuneWindowsDevServerRawRequest `
        -PipeName $PipeName `
        -Payload "input=$InputText`ncommit=$CommitFlag`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
}

function Test-YuneWindowsDevServerReady {
    param(
        [string]$PipeName = "\\.\pipe\yune-windows-ime",
        [System.Diagnostics.Process]$Process = $null,
        [int]$TimeoutMs = 180000
    )

    try {
        $Response = Invoke-YuneWindowsDevServerRequest `
            -PipeName $PipeName `
            -InputText "ngohaig" `
            -Commit $false `
            -Process $Process `
            -TimeoutMs $TimeoutMs
        return ($Response.ready -eq $true -and
            -not [string]::IsNullOrWhiteSpace([string]$Response.schema_id) -and
            $null -ne $Response.state -and
            -not [string]::IsNullOrWhiteSpace([string]$Response.state.schema_id))
    }
    catch {
        return $false
    }
}

function Get-YuneWindowsDevProcessesUsingModule {
    param([Parameter(Mandatory = $true)][string]$ModulePath)

    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
        return @()
    }

    $ExpectedPath = Resolve-YuneWindowsDevFullPath $ModulePath
    $Holders = [System.Collections.Generic.List[object]]::new()
    foreach ($Process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            foreach ($Module in @($Process.Modules)) {
                if ([string]::IsNullOrWhiteSpace([string]$Module.FileName)) {
                    continue
                }
                $ModuleFullPath = Resolve-YuneWindowsDevFullPath ([string]$Module.FileName)
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

function Get-YuneWindowsDevProcessesByPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ProcessName = ""
    )

    $ExpectedPath = Resolve-YuneWindowsDevFullPath $Path
    $Candidates = if ([string]::IsNullOrWhiteSpace($ProcessName)) {
        @(Get-Process -ErrorAction SilentlyContinue)
    }
    else {
        @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    }

    $Matches = [System.Collections.Generic.List[object]]::new()
    foreach ($Process in $Candidates) {
        try {
            $ProcessPath = [string]$Process.Path
            if ([string]::IsNullOrWhiteSpace($ProcessPath)) {
                continue
            }
            $ProcessPath = Resolve-YuneWindowsDevFullPath $ProcessPath
            if ([string]::Equals($ProcessPath, $ExpectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $StartedAt = $null
                try {
                    $StartedAt = $Process.StartTime
                }
                catch {
                }
                $Matches.Add([pscustomobject]@{
                        process_id = [int]$Process.Id
                        process_name = [string]$Process.ProcessName
                        process_path = $ProcessPath
                        started_at = $StartedAt
                    }) | Out-Null
            }
        }
        catch {
        }
    }

    return @($Matches)
}

function Wait-YuneWindowsDevProcessExit {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [int]$TimeoutMs = 10000,
        [switch]$RequireExit
    )

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $Deadline) {
        $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $Process) {
            return $true
        }
        Start-Sleep -Milliseconds 100
    }

    if ($RequireExit) {
        throw "process $ProcessId did not exit within $TimeoutMs ms"
    }
    return $false
}

function Stop-YuneWindowsDevProcessesByPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ProcessName = "",
        [int]$TimeoutMs = 10000
    )

    $Processes = @(Get-YuneWindowsDevProcessesByPath -Path $Path -ProcessName $ProcessName)
    foreach ($Process in $Processes) {
        Stop-Process -Id ([int]$Process.process_id) -Force -ErrorAction SilentlyContinue
        Wait-YuneWindowsDevProcessExit -ProcessId ([int]$Process.process_id) -TimeoutMs $TimeoutMs -RequireExit | Out-Null
    }
    return @($Processes)
}

function Format-YuneWindowsDevProcessSummary {
    param([object[]]$Processes)

    if (-not $Processes -or @($Processes).Count -eq 0) {
        return "none"
    }

    return (@($Processes) | ForEach-Object {
            $Path = [string]$_.process_path
            if ([string]::IsNullOrWhiteSpace($Path)) {
                "$($_.process_name)[$($_.process_id)]"
            }
            else {
                "$($_.process_name)[$($_.process_id)] $Path"
            }
        }) -join "; "
}

function Read-YuneWindowsDevJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
    }
    catch {
        throw "failed to parse dev state file: $Path"
    }
}

function Write-YuneWindowsDevJsonFile {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent)) {
        New-Item -Path $Parent -ItemType Directory -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}

function Stop-YuneWindowsDevStartedProcess {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process) {
        return
    }
    try {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            $Process.WaitForExit(10000) | Out-Null
        }
    }
    catch {
    }
}
