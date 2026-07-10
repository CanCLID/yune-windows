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
$StateFile = Join-Path $OutputDir "state\ime-state.json"
$StateTempFile = "$StateFile.tmp"
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

function Start-IsolatedServer {
    return Start-Process -FilePath $Server -ArgumentList @(
        "--rime-dll", $RimeDll,
        "--shared-dir", $SharedDataDir,
        "--user-dir", $UserDataDir,
        "--pipe", $PipeName
    ) -WindowStyle Hidden -PassThru
}

function Send-RequestWithoutReading([string]$Payload) {
    $Client = [IO.Pipes.NamedPipeClientStream]::new(
        ".", $PipeLeaf, [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::None)
    try {
        $Client.Connect($TimeoutMs)
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Payload)
        $Client.Write($Bytes, 0, $Bytes.Length)
        $Client.Flush()
    }
    finally {
        $Client.Dispose()
    }
}

$ServerProcess = Start-IsolatedServer
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

    # One hundred paced, end-to-end CAS toggles must produce exactly one
    # committed revision per physical action.
    $Current = $Final
    $PacedStartRevision = [long]$Current.state.revision
    for ($Action = 1; $Action -le 100; $Action++) {
        $Desired = -not [bool]$Current.state.ascii_mode
        $Value = if ($Desired) { 1 } else { 0 }
        $ExpectedRevision = [long]$Current.state.revision
        $Payload = "op=set-option`nname=ascii_mode`nvalue=$Value`nexpect_boot_id=$BootId`nexpect_revision=$ExpectedRevision`n.`n"
        $ResponseText = & $RequestScript $PipeLeaf $Payload $TimeoutMs
        $Current = $ResponseText | ConvertFrom-Json
        if ($Current.ready -ne $true -or $Current.applied -ne $true -or
            $Current.outcome -ne "applied" -or
            [bool]$Current.state.ascii_mode -ne $Desired -or
            [long]$Current.state.revision -ne $ExpectedRevision + 1) {
            throw "paced CAS action $Action did not commit exactly once"
        }
        Start-Sleep -Milliseconds 2
    }
    if ([long]$Current.state.revision -ne $PacedStartRevision + 100) {
        throw "100 paced CAS actions did not produce 100 revisions"
    }

    # Simulate a client timing out after the server received the mutation but
    # before the client consumed its response. Reconciliation must observe one
    # commit, and a stale replay must conflict instead of toggling twice.
    $UnknownStartRevision = [long]$Current.state.revision
    $UnknownDesired = -not [bool]$Current.state.ascii_mode
    $UnknownValue = if ($UnknownDesired) { 1 } else { 0 }
    $UnknownPayload = "op=set-option`nname=ascii_mode`nvalue=$UnknownValue`nexpect_boot_id=$BootId`nexpect_revision=$UnknownStartRevision`n.`n"
    Send-RequestWithoutReading $UnknownPayload
    $UnknownDeadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $UnknownStateText = & $RequestScript $PipeLeaf "op=get-state`n.`n" $TimeoutMs
        $UnknownState = $UnknownStateText | ConvertFrom-Json
        if ([bool]$UnknownState.state.ascii_mode -eq $UnknownDesired -and
            [long]$UnknownState.state.revision -eq $UnknownStartRevision + 1) {
            break
        }
        Start-Sleep -Milliseconds 20
    } while ([DateTime]::UtcNow -lt $UnknownDeadline)
    if ([bool]$UnknownState.state.ascii_mode -ne $UnknownDesired -or
        [long]$UnknownState.state.revision -ne $UnknownStartRevision + 1) {
        throw "outcome-unknown mutation could not be reconciled"
    }
    $ReplayText = & $RequestScript $PipeLeaf $UnknownPayload $TimeoutMs
    $Replay = $ReplayText | ConvertFrom-Json
    if ($Replay.applied -ne $false -or
        $Replay.reason -ne "revision_conflict" -or
        [long]$Replay.state.revision -ne $UnknownStartRevision + 1) {
        throw "outcome-unknown stale replay was not rejected"
    }

    # Block the atomic temporary file to force persistence failure. The failed
    # mutation must leave both the in-memory value and revision unchanged; the
    # same CAS request must then succeed once after storage recovers.
    New-Item -ItemType Directory -Path $StateTempFile -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $StateTempFile "blocker") `
        -Value "test-only persistence blocker" -Encoding ASCII
    $PersistStartRevision = [long]$Replay.state.revision
    $PersistDesired = -not [bool]$Replay.state.ascii_mode
    $PersistValue = if ($PersistDesired) { 1 } else { 0 }
    $PersistPayload = "op=set-option`nname=ascii_mode`nvalue=$PersistValue`nexpect_boot_id=$BootId`nexpect_revision=$PersistStartRevision`n.`n"
    $PersistFailureText = & $RequestScript $PipeLeaf $PersistPayload $TimeoutMs
    $PersistFailure = $PersistFailureText | ConvertFrom-Json
    if ($PersistFailure.ready -ne $false -or
        $PersistFailure.outcome -ne "persist_failed" -or
        $PersistFailure.applied -ne $false -or
        [bool]$PersistFailure.state.ascii_mode -eq $PersistDesired -or
        [long]$PersistFailure.state.revision -ne $PersistStartRevision) {
        throw "persistence failure was not atomic or explicit"
    }
    Remove-Item -LiteralPath $StateTempFile -Recurse -Force
    $PersistRetryText = & $RequestScript $PipeLeaf $PersistPayload $TimeoutMs
    $PersistRetry = $PersistRetryText | ConvertFrom-Json
    if ($PersistRetry.ready -ne $true -or
        $PersistRetry.applied -ne $true -or
        $PersistRetry.outcome -ne "applied" -or
        [bool]$PersistRetry.state.ascii_mode -ne $PersistDesired -or
        [long]$PersistRetry.state.revision -ne $PersistStartRevision + 1) {
        throw "persistence recovery did not commit the pending action once"
    }
    $Persisted = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    if ([bool]$Persisted.ascii_mode -ne $PersistDesired -or
        [long]$Persisted.revision -ne $PersistStartRevision + 1) {
        throw "persisted state does not match recovered server state"
    }

    # Restart creates a new epoch without changing the persisted revision.
    $PreRestartBootId = [string]$PersistRetry.state.boot_id
    $PreRestartRevision = [long]$PersistRetry.state.revision
    Stop-Process -Id $ServerProcess.Id -Force
    $ServerProcess.WaitForExit(10000) | Out-Null
    $ServerProcess = Start-IsolatedServer
    $RestartText = & $RequestScript $PipeLeaf "op=get-state`n.`n" $TimeoutMs
    $Restart = $RestartText | ConvertFrom-Json
    if ([string]$Restart.state.boot_id -eq $PreRestartBootId -or
        [long]$Restart.state.revision -ne $PreRestartRevision) {
        throw "server restart did not rotate only the boot epoch"
    }
    $StaleEpochPayload = "op=set-option`nname=ascii_mode`nvalue=$UnknownValue`nexpect_boot_id=$PreRestartBootId`nexpect_revision=$PreRestartRevision`n.`n"
    $StaleEpochText = & $RequestScript $PipeLeaf $StaleEpochPayload $TimeoutMs
    $StaleEpoch = $StaleEpochText | ConvertFrom-Json
    if ($StaleEpoch.applied -ne $false -or
        $StaleEpoch.reason -ne "epoch_conflict" -or
        [long]$StaleEpoch.state.revision -ne $PreRestartRevision) {
        throw "pre-restart epoch was not rejected without mutation"
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

Write-Host "M11D paced, conflict, timeout-reconciliation, persistence, restart, and process-local reliability smoke passed."
