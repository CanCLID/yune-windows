param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = "",
    [int]$TimeoutMs = 180000
)

# Pipe-security contract: the shared server's named pipe must admit sandboxed and
# lower-integrity host processes, or the TSF DLL loaded inside Chrome/Telegram/
# Zed/Explorer cannot reach the server and typing produces no output. Assert the
# pipe DACL grants ALL APPLICATION PACKAGES (AC, AppContainer/UWP) and INTERACTIVE
# USERS (IU, any integrity level), and that a normal request still succeeds.

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m06-pipe-security-$ProcessId"
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
$PipeLeaf = "yune-windows-pipe-security-$ProcessId"
$PipeName = "\\.\pipe\$PipeLeaf"

& (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
    -SourceSchemaDir $SourceSchemaDir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

$Process = Start-Process -FilePath $Server -ArgumentList @(
    "--rime-dll", $RimeDll,
    "--shared-dir", $SharedDataDir,
    "--user-dir", $UserDataDir,
    "--pipe", $PipeName
) -WindowStyle Hidden -PassThru

try {
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $Sddl = $null
    $Ready = $false
    while ([DateTime]::UtcNow -lt $Deadline -and -not $Ready) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "server exited before pipe-security check with code $($Process.ExitCode)"
        }
        $Client = $null
        try {
            $Client = [System.IO.Pipes.NamedPipeClientStream]::new(
                ".", $PipeLeaf, [System.IO.Pipes.PipeDirection]::InOut,
                [System.IO.Pipes.PipeOptions]::None)
            $Client.Connect(500)
            $Sddl = $Client.GetAccessControl().GetSecurityDescriptorSddlForm('Access')

            $Request = [System.Text.Encoding]::UTF8.GetBytes("input=ngohaig`ncommit=0`n.`n")
            $Client.Write($Request, 0, $Request.Length)
            $Client.Flush()
            $Buffer = New-Object byte[] 65536
            $ReadTask = $Client.ReadAsync($Buffer, 0, $Buffer.Length)
            if ($ReadTask.Wait(10000) -and $ReadTask.Result -gt 0) {
                $Json = [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $ReadTask.Result) | ConvertFrom-Json
                if ([bool]$Json.ready) { $Ready = $true }
            }
        }
        catch {
            Start-Sleep -Milliseconds 300
        }
        finally {
            if ($Client) { $Client.Dispose() }
        }
    }

    if ($null -eq $Sddl) {
        throw "could not read pipe security descriptor from the scratch server"
    }
    if ($Sddl -notmatch '\;\;\;AC\)') {
        throw "pipe DACL does not grant ALL APPLICATION PACKAGES (AC); sandboxed hosts will be denied. SDDL: $Sddl"
    }
    # Scoped to the current user's own SID, not the broad interactive-users (IU),
    # Everyone (WD), or authenticated-users (AU) aliases, so other machine users
    # cannot reach this user's IME pipe.
    if ($Sddl -match '\;\;\;IU\)' -or $Sddl -match '\;\;\;WD\)' -or $Sddl -match '\;\;\;AU\)') {
        throw "pipe DACL is broader than the current user (grants IU/WD/AU). SDDL: $Sddl"
    }
    if ($Sddl -notmatch '\;\;\;S-1-5-21-') {
        throw "pipe DACL does not grant a specific user SID. SDDL: $Sddl"
    }
    if (-not $Ready) {
        throw "server did not answer a normal request with the hardened pipe descriptor"
    }

    Write-Host "Server pipe admits the current user (SID) and AppContainer (AC) clients only, and still answers. SDDL: $Sddl"
}
finally {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
    }
}
