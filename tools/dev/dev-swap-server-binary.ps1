param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme"
)

# Minimal, race-proof swap of the installed YuneWindowsServer.exe. Unlike
# dev-reload-server it does no readiness/restart dance. It holds the server launch
# mutex (so no loaded TSF DLL can warm-relaunch the server mid-swap), renames the
# running exe aside if needed (allowed for a running image), drops the new binary
# in, stops the old server so the single-instance mutex frees, starts one fresh
# server, then verifies the hardened pipe security is live. Reboot-free; no DLL
# reload. Must be run from the user's normal session.

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# Same name the TSF DLL uses in RequestSharedServerLaunch; holding it makes the
# DLL's launch attempt time out (no relaunch) for as long as we hold it.
$LaunchMutexName = 'Local\YuneWindowsServerLaunch_1788DBA7_CC9A_49E2_9C4C_E9DBF0BE2567'

function Stop-AllServers {
    $stopped = 0
    Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill(); $stopped++ } catch {}
    }
    return $stopped
}

Write-Host "=== building server ==="
$BuildDir = Join-Path $env:TEMP ("yune-windows\swap-server-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $BuildDir -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) { throw "build failed with exit code $LASTEXITCODE" }
$NewServer = Join-Path $BuildDir "YuneWindowsServer.exe"

$Dest = Join-Path $InstallDir "YuneWindowsServer.exe"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$Mutex = [System.Threading.Mutex]::new($false, $LaunchMutexName)
$Held = $false
try { $Held = $Mutex.WaitOne(3000) }
catch [System.Threading.AbandonedMutexException] { $Held = $true }

if ($Held) { Write-Host "=== holding launch mutex (blocks relaunch during swap) ===" }
else { Write-Host "=== WARNING: could not acquire launch mutex; relying on rename-aside ===" }

try {
    Write-Host "=== stopping old server(s) ==="
    Write-Host ("  stopped " + (Stop-AllServers) + " process(es)")
    Start-Sleep -Milliseconds 400

    Write-Host "=== installing new binary ==="
    if (Test-Path -LiteralPath $Dest -PathType Leaf) {
        try {
            Copy-Item -LiteralPath $NewServer -Destination $Dest -Force
        }
        catch {
            # Still mapped by an exiting/relaunched process: rename the running exe
            # aside (allowed for a running image) and drop the new binary in.
            $Aside = "$Dest.swap-$Timestamp"
            Move-Item -LiteralPath $Dest -Destination $Aside -Force
            Copy-Item -LiteralPath $NewServer -Destination $Dest -Force
            Write-Host "  (renamed the locked running exe aside)"
        }
    }
    else {
        Copy-Item -LiteralPath $NewServer -Destination $Dest -Force
    }
    Write-Host "  installed new server binary: $Dest"

    # Kill anything that came up from the old binary, so our fresh start owns the
    # single-instance mutex and serves the new binary.
    Stop-AllServers | Out-Null
    Start-Sleep -Milliseconds 400

    Write-Host "=== starting fresh server ==="
    Start-Process -FilePath $Dest -ArgumentList @(
        "--rime-dll", (Join-Path $InstallDir "rime.dll"),
        "--shared-dir", (Join-Path $InstallDir "schema"),
        "--user-dir", (Join-Path $InstallDir "user-data"),
        "--pipe", "\\.\pipe\yune-windows-ime"
    ) -WindowStyle Hidden | Out-Null
}
finally {
    if ($Held) { try { $Mutex.ReleaseMutex() } catch {} }
    $Mutex.Dispose()
}

Write-Host "=== verifying (connect + pipe security + candidates) ==="
$Deadline = [DateTime]::UtcNow.AddSeconds(120)
$Ok = $false
$Sddl = ""
while ([DateTime]::UtcNow -lt $Deadline -and -not $Ok) {
    $c = $null
    try {
        $c = [System.IO.Pipes.NamedPipeClientStream]::new('.', 'yune-windows-ime', [System.IO.Pipes.PipeDirection]::InOut)
        $c.Connect(500)
        try { $Sddl = $c.GetAccessControl().GetSecurityDescriptorSddlForm('Access') } catch {}
        $req = [System.Text.Encoding]::UTF8.GetBytes("input=ngohaig`ncommit=0`n.`n")
        $c.Write($req, 0, $req.Length); $c.Flush()
        $buf = New-Object byte[] 65536
        $t = $c.ReadAsync($buf, 0, $buf.Length)
        if ($t.Wait(10000) -and $t.Result -gt 0) {
            $json = [System.Text.Encoding]::UTF8.GetString($buf, 0, $t.Result) | ConvertFrom-Json
            if ([bool]$json.ready) {
                $Ok = $true
                Write-Host ("  server ready=True candidate_count=" + $json.candidate_count)
            }
        }
    }
    catch { Start-Sleep -Milliseconds 500 }
    finally { if ($c) { $c.Dispose() } }
}

Get-ChildItem -LiteralPath $InstallDir -Filter "YuneWindowsServer.exe.swap-*" -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {}
}

if (-not $Ok) { throw "new server did not become ready; check for a running YuneWindowsServer and re-run" }
if ($Sddl -match ';;;AC\)') {
    Write-Host "SUCCESS: hardened pipe is live (grants AppContainer/AC). SDDL: $Sddl"
}
else {
    Write-Host "WARNING: server is up but the pipe SDDL does not show the AC grant. SDDL: $Sddl"
}
Write-Host "DONE. Now type Cantonese in Chrome / Telegram / Zed / Explorer to confirm output appears."
