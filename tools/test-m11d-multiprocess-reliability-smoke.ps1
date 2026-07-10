param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = "",
    [int]$TimeoutMs = 180000
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m11d-multiprocess-$PID"
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") `
    -OutputDir $OutputDir `
    -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) {
    throw "TSF shell build failed with exit code $LASTEXITCODE"
}

$Server = Join-Path $OutputDir "YuneWindowsServer.exe"
$ReliabilitySmoke = Join-Path $OutputDir "YuneWindowsReliabilitySmoke.exe"
$RimeDll = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
$SourceSchemaDir = Join-Path $YuneRoot "apps\yune-web\public\schema"
$SharedDataDir = Join-Path $OutputDir "schema"
$UserDataDir = Join-Path $OutputDir "user-data"
$PipeLeaf = "yune-windows-m11d-multiprocess-$PID"
$PipeName = "\\.\pipe\$PipeLeaf"

& (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
    -SourceSchemaDir $SourceSchemaDir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

$RequestScript = {
    param([string]$PipeLeaf, [string]$Payload, [int]$TimeoutMs)
    $Client = [IO.Pipes.NamedPipeClientStream]::new(
        ".", $PipeLeaf, [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::None)
    try {
        $Client.Connect($TimeoutMs)
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Payload)
        $Client.Write($Bytes, 0, $Bytes.Length)
        $Client.Flush()
        $Buffer = New-Object byte[] 65536
        $ReadTask = $Client.ReadAsync($Buffer, 0, $Buffer.Length)
        if (-not $ReadTask.Wait($TimeoutMs)) {
            throw "timed out reading isolated server response"
        }
        [Text.Encoding]::UTF8.GetString(
            $Buffer, 0, $ReadTask.Result)
    }
    finally {
        $Client.Dispose()
    }
}

$ServerProcess = Start-Process -FilePath $Server -ArgumentList @(
    "--rime-dll", $RimeDll,
    "--shared-dir", $SharedDataDir,
    "--user-dir", $UserDataDir,
    "--pipe", $PipeName
) -WindowStyle Hidden -PassThru
$Jobs = @()
$SmokeProcesses = @()
try {
    $InitialText = & $RequestScript $PipeLeaf "op=get-state`n.`n" $TimeoutMs
    $Initial = $InitialText | ConvertFrom-Json
    $BootId = [string]$Initial.state.boot_id
    $Revision = [long]$Initial.state.revision
    if ([string]::IsNullOrWhiteSpace($BootId)) {
        throw "isolated server did not return a boot id"
    }

    $CasPayload = "op=set-option`nname=ascii_mode`nvalue=1`nexpect_boot_id=$BootId`nexpect_revision=$Revision`n.`n"
    $Jobs = @(
        Start-Job -ScriptBlock $RequestScript -ArgumentList $PipeLeaf, $CasPayload, $TimeoutMs
        Start-Job -ScriptBlock $RequestScript -ArgumentList $PipeLeaf, $CasPayload, $TimeoutMs
    )
    (Wait-Job -Job $Jobs -Timeout ([Math]::Ceiling($TimeoutMs / 1000))) |
        Out-Null
    if (@($Jobs | Where-Object State -ne "Completed").Count -ne 0) {
        throw "multiprocess CAS clients did not complete"
    }
    $Responses = @($Jobs | Receive-Job | ForEach-Object { $_ | ConvertFrom-Json })
    $Applied = @($Responses | Where-Object { $_.applied -eq $true })
    $Conflicted = @($Responses | Where-Object {
            $_.applied -eq $false -and $_.reason -eq "revision_conflict"
        })
    if ($Applied.Count -ne 1 -or $Conflicted.Count -ne 1) {
        throw "two-process CAS arbitration expected one apply and one conflict"
    }
    $FinalText = & $RequestScript $PipeLeaf "op=get-state`n.`n" $TimeoutMs
    $Final = $FinalText | ConvertFrom-Json
    if ($Final.state.ascii_mode -ne $true -or
        [long]$Final.state.revision -ne $Revision + 1) {
        throw "multiprocess CAS changed state or revision more than once"
    }

    $SmokeProcesses = @(
        Start-Process -FilePath $ReliabilitySmoke -WindowStyle Hidden -PassThru
        Start-Process -FilePath $ReliabilitySmoke -WindowStyle Hidden -PassThru
    )
    foreach ($SmokeProcess in $SmokeProcesses) {
        if (-not $SmokeProcess.WaitForExit(10000) -or
            $SmokeProcess.ExitCode -ne 0) {
            throw "process-local token/parity helper failed"
        }
    }
}
finally {
    if ($Jobs.Count -gt 0) {
        $Jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    }
    foreach ($SmokeProcess in $SmokeProcesses) {
        if ($SmokeProcess -and -not $SmokeProcess.HasExited) {
            Stop-Process -Id $SmokeProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }
    if ($ServerProcess -and -not $ServerProcess.HasExited) {
        Stop-Process -Id $ServerProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "M11D multiprocess CAS and process-local token/parity smoke passed."
