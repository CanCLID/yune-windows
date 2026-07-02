param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = "",
    [int]$TimeoutMs = 180000
)

# F2a contract: a per-request failure (a client that disconnects mid-exchange,
# e.g. after hitting its own query timeout) must NOT take down the shared
# YuneWindowsServer. The server must stay alive and keep answering subsequent
# requests. Regression guard for the En->Cn toggle freeze (F2).

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m06-request-resilience-$ProcessId"
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][object]$Actual,
        [Parameter(Mandatory = $true)][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Invoke-RawYuneWindowsServerRequest {
    param(
        [Parameter(Mandatory = $true)][string]$PipeLeaf,
        [Parameter(Mandatory = $true)][string]$Payload,
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [int]$TimeoutMs = 180000
    )

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $LastError = ""

    while ([DateTime]::UtcNow -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "server exited before request completed with code $($Process.ExitCode)"
        }

        $Client = $null
        try {
            $Client = [System.IO.Pipes.NamedPipeClientStream]::new(
                ".",
                $PipeLeaf,
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

            $ResponseText = [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $BytesRead)
            return ($ResponseText | ConvertFrom-Json)
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

    throw "timed out waiting for server response on $PipeLeaf. Last error: $LastError"
}

function Invoke-AbortedYuneWindowsServerRequest {
    param(
        [Parameter(Mandatory = $true)][string]$PipeLeaf,
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][bool]$WriteFirst,
        [string]$Payload = "op=get-state`n.`n",
        [int]$TimeoutMs = 30000
    )

    # Connect and then close the pipe WITHOUT reading the response. With
    # $WriteFirst = $false the server's ReadFile fails (nothing to read); with
    # $WriteFirst = $true it reads + processes, then its WriteFile/flush fails
    # against the closed client -- the faithful F2 mid-response disconnect.
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $LastError = ""
    $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)

    while ([DateTime]::UtcNow -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "server exited before the aborted-request test with code $($Process.ExitCode)"
        }

        $Client = $null
        try {
            $Client = [System.IO.Pipes.NamedPipeClientStream]::new(
                ".",
                $PipeLeaf,
                [System.IO.Pipes.PipeDirection]::InOut,
                [System.IO.Pipes.PipeOptions]::None)
            $Client.Connect(250)
            if ($WriteFirst) {
                $Client.Write($RequestBytes, 0, $RequestBytes.Length)
                $Client.Flush()
            }
            return
        }
        catch {
            $LastError = $_.Exception.Message
            Start-Sleep -Milliseconds 100
        }
        finally {
            if ($Client) {
                # Dispose closes the client end without reading the response.
                $Client.Dispose()
            }
        }
    }

    throw "could not connect to run the aborted-request test on $PipeLeaf. Last error: $LastError"
}

function Assert-ServerAlive {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $Process.Refresh()
    if ($Process.HasExited) {
        throw "$Context killed the server with exit code $($Process.ExitCode)"
    }
}

$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
& $BuildScript -OutputDir $OutputDir -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$Server = Join-Path $OutputDir "YuneWindowsServer.exe"
$RimeDll = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
$SourceSchemaDir = Join-Path $YuneRoot "apps\yune-web\public\schema"
$SharedDataDir = Join-Path $OutputDir "schema"
$UserDataDir = Join-Path $OutputDir "user-data"
$PipeLeaf = "yune-windows-request-resilience-$ProcessId"
$PipeName = "\\.\pipe\$PipeLeaf"

& (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
    -SourceSchemaDir $SourceSchemaDir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

function Start-TestServer {
    return Start-Process -FilePath $Server -ArgumentList @(
        "--rime-dll", $RimeDll,
        "--shared-dir", $SharedDataDir,
        "--user-dir", $UserDataDir,
        "--pipe", $PipeName
    ) -WindowStyle Hidden -PassThru
}

$Process = Start-TestServer

try {
    # Warm up: the first request also proves the server is answering.
    $Initial = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=get-state`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-Equal ([bool]$Initial.ready) $true "warm-up get-state readiness mismatch."

    for ($Round = 1; $Round -le 3; $Round++) {
        # 1) Connect and abandon without writing -> server ReadFile fails.
        Invoke-AbortedYuneWindowsServerRequest `
            -PipeLeaf $PipeLeaf `
            -Process $Process `
            -WriteFirst $false
        Assert-ServerAlive $Process "aborted request (connect, no write) round $Round"

        $AfterNoWrite = Invoke-RawYuneWindowsServerRequest `
            -PipeLeaf $PipeLeaf `
            -Payload "op=get-state`n.`n" `
            -Process $Process `
            -TimeoutMs $TimeoutMs
        Assert-Equal ([bool]$AfterNoWrite.ready) $true `
            "server did not answer after a no-write disconnect (round $Round)."

        # 2) Write a real request, then close before reading -> server
        #    WriteFile/flush fails against the closed client (the F2 scenario).
        Invoke-AbortedYuneWindowsServerRequest `
            -PipeLeaf $PipeLeaf `
            -Process $Process `
            -WriteFirst $true `
            -Payload "input=ngohaig`ncommit=0`n.`n"
        Assert-ServerAlive $Process "aborted request (write then disconnect) round $Round"

        $AfterWrite = Invoke-RawYuneWindowsServerRequest `
            -PipeLeaf $PipeLeaf `
            -Payload "input=ngohaig`ncommit=0`n.`n" `
            -Process $Process `
            -TimeoutMs $TimeoutMs
        Assert-Equal ([bool]$AfterWrite.ready) $true `
            "server did not answer after a mid-response disconnect (round $Round)."
    }

    Write-Host "Shared server survives client disconnects mid-request and keeps answering."
}
finally {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
    }
}
