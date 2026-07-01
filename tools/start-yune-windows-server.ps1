param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$PipeName = "\\.\pipe\yune-windows-ime",
    [switch]$WaitForReady,
    [int]$ReadyTimeoutMs = 180000,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

$InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
$Server = Join-Path $InstallRoot "YuneWindowsServer.exe"
$RimeDll = Join-Path $InstallRoot "rime.dll"
$SharedDataDir = Join-Path $InstallRoot "schema"
$UserDataDir = Join-Path $InstallRoot "user-data"
$SourceSchemaDir = $SharedDataDir

if (-not (Test-Path -LiteralPath $Server)) {
    throw "missing installed shared server: $Server"
}
if (-not (Test-Path -LiteralPath $RimeDll)) {
    $RimeDll = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
}
if (-not (Test-Path -LiteralPath $SharedDataDir)) {
    $SourceSchemaDir = Join-Path $YuneRoot "apps\yune-web\public\schema"
    $SharedDataDir = Join-Path $env:TEMP "yune-windows\m01-start-server-schema"
}
if (-not (Test-Path -LiteralPath $RimeDll)) {
    throw "missing Yune runtime: $RimeDll"
}
if (-not (Test-Path -LiteralPath $SharedDataDir)) {
    if (-not (Test-Path -LiteralPath $SourceSchemaDir)) {
        throw "missing Yune schema data: $SourceSchemaDir"
    }
}

function Get-PipeClientName {
    param([string]$Name)
    if ($Name.StartsWith("\\.\pipe\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Name.Substring("\\.\pipe\".Length)
    }
    return $Name
}

function Wait-YuneWindowsServerReady {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [string]$PipeName,
        [int]$TimeoutMs
    )

    $PipeClientName = Get-PipeClientName -Name $PipeName
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $Request = "input=ngohaig`ncommit=0`n.`n"
    $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Request)
    $ExpectedCommitText = -join ([char[]](0x6211, 0x4fc2, 0x500b))

    while ([DateTime]::UtcNow -lt $Deadline) {
        if ($Process.HasExited) {
            throw "Yune Windows server exited before readiness check completed."
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
            $ReadTimeoutMs =
                [int][Math]::Max(1, ($Deadline - [DateTime]::UtcNow).TotalMilliseconds)
            $ReadTask = $Client.ReadAsync($Buffer, 0, $Buffer.Length)
            if (-not $ReadTask.Wait($ReadTimeoutMs)) {
                continue
            }
            $BytesRead = $ReadTask.Result
            if ($BytesRead -gt 0) {
                $Response = [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $BytesRead)
                try {
                    $Json = $Response | ConvertFrom-Json
                    $Candidates = @($Json.candidates)
                    $FirstCandidateText = ""
                    if ($Candidates.Count -gt 0) {
                        $FirstCandidateText = [string]$Candidates[0].text
                    }
                    if ($Json.ready -eq $true -and
                        $Json.schema_id -eq "jyut6ping3" -and
                        [int]$Json.candidate_count -gt 0 -and
                        $FirstCandidateText -eq $ExpectedCommitText) {
                        return
                    }
                }
                catch {
                }
            }
        }
        catch {
            Start-Sleep -Milliseconds 100
        }
        finally {
            if ($Client) {
                $Client.Dispose()
            }
        }
    }

    throw "Timed out waiting for Yune Windows server readiness on $PipeName."
}

& (Join-Path $PSScriptRoot "prepare-yune-product-data.ps1") `
    -SourceSchemaDir $SourceSchemaDir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

New-Item -ItemType Directory -Force (Join-Path $UserDataDir "build") | Out-Null

$Process = Start-Process -FilePath $Server -ArgumentList @(
    "--rime-dll", $RimeDll,
    "--shared-dir", $SharedDataDir,
    "--user-dir", $UserDataDir,
    "--pipe", $PipeName
) -WindowStyle Hidden -PassThru

if ($WaitForReady) {
    try {
        Wait-YuneWindowsServerReady `
            -Process $Process `
            -PipeName $PipeName `
            -TimeoutMs $ReadyTimeoutMs
    }
    catch {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force
        }
        throw
    }
}

if ($PassThru) {
    $Process
} else {
    Write-Host "Started Yune Windows server PID $($Process.Id) on $PipeName"
}
