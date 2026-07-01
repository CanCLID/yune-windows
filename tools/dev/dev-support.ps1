$ErrorActionPreference = "Stop"

$script:YuneWindowsDevDefaultPipeName = "\\.\pipe\yune-windows-ime-dev"

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
        -Path (Join-Path $SchemaSourceDir "jyut6ping3_mobile.schema.yaml") `
        -Description "Yune Windows runtime schema source" `
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

function Invoke-YuneWindowsDevServerRequest {
    param(
        [Parameter(Mandatory = $true)][string]$PipeName,
        [Parameter(Mandatory = $true)][string]$InputText,
        [bool]$Commit = $false,
        [System.Diagnostics.Process]$Process = $null,
        [int]$TimeoutMs = 180000
    )

    $PipeClientName = ConvertTo-YuneWindowsDevPipeClientName -PipeName $PipeName
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $CommitFlag = if ($Commit) { "1" } else { "0" }
    $Request = "input=$InputText`ncommit=$CommitFlag`n.`n"
    $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Request)
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
