param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-tsf-$ProcessId"
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
$UserDataDir = Join-Path $OutputDir "ipc-user"
$PipeLeaf = "yune-windows-ime-$ProcessId"
$PipeName = "\\.\pipe\$PipeLeaf"

& (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
    -SourceSchemaDir $SourceSchemaDir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

$Process = Start-Process -FilePath $Server -ArgumentList @(
    "--rime-dll", $RimeDll,
    "--shared-dir", $SharedDataDir,
    "--user-dir", $UserDataDir,
    "--pipe", $PipeName,
    "--once"
) -WindowStyle Hidden -PassThru

try {
    $Client = [System.IO.Pipes.NamedPipeClientStream]::new(
        ".",
        $PipeLeaf,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None
    )
    $Client.Connect(90000)
    $Encoding = [System.Text.UTF8Encoding]::new($false)
    $RequestBytes = $Encoding.GetBytes("input=ngohaig`ncommit=1`n.`n")
    $Client.Write($RequestBytes, 0, $RequestBytes.Length)
    $Client.Flush()
    $Buffer = New-Object byte[] 65536
    $ReadTask = $Client.ReadAsync($Buffer, 0, $Buffer.Length)
    if (-not $ReadTask.Wait(90000)) {
        throw "timed out waiting for server response"
    }
    $BytesRead = $ReadTask.Result
    if ($BytesRead -le 0) {
        throw "expected non-empty server response"
    }
    $ResponseText = $Encoding.GetString($Buffer, 0, $BytesRead)
    $Client.Dispose()

    $Result = $ResponseText | ConvertFrom-Json
    if ($Result.ready -ne $true) {
        throw "server did not report ready"
    }
    if ($Result.schema_id -ne "jyut6ping3") {
        throw "expected schema_id=jyut6ping3, got '$($Result.schema_id)'"
    }
    if ([int]$Result.candidate_count -le 0) {
        throw "expected candidate_count > 0"
    }
    if ([string]::IsNullOrWhiteSpace($Result.commit_text)) {
        throw "expected non-empty commit_text"
    }
    if ($Result.commit_text -eq "ngohaig") {
        throw "server returned raw echo commit_text"
    }

    $Process.Refresh()
    if (-not $Process.HasExited) {
        Wait-Process -Id $Process.Id -Timeout 15
        $Process.Refresh()
    }
    if ($Process.ExitCode -ne 0) {
        throw "server exited with code $($Process.ExitCode)"
    }
    Write-Host "Yune server IPC smoke passed: schema=$($Result.schema_id), candidates=$($Result.candidate_count), commit=$($Result.commit_text)"
}
finally {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
    }
}
