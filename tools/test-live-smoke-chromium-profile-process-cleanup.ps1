param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

. $SupportScript

foreach ($RequiredCommand in @("Stop-ProcessesUsingPathInCommandLine", "Remove-YuneWindowsPathWithRetry")) {
    if (-not (Get-Command $RequiredCommand -ErrorAction SilentlyContinue)) {
        throw "live smoke support must expose $RequiredCommand"
    }
}

$ChromiumSource = Get-Content -Raw -LiteralPath $ChromiumSmoke
if ($ChromiumSource -notmatch 'finally\s*\{(?s:.*?)Stop-ProcessesUsingPathInCommandLine\s+-Path\s+\$ProfileRoot(?s:.*?)Remove-YuneWindowsPathWithRetry\s+-Path\s+\$ProfileRoot') {
    throw "run-chromium-smoke.ps1 must stop Chromium processes using the temporary profile before retrying profile cleanup."
}

$TempRoot = Join-Path $env:TEMP ("yune-windows\m01-chromium-profile-cleanup-test\" + [Guid]::NewGuid().ToString("N"))
$ProfileRoot = Join-Path $TempRoot "profile"
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null

$PowerShellPath = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($PowerShellPath)) {
    $PowerShellPath = "powershell.exe"
}

$Marker = "--user-data-dir=$ProfileRoot"
$ChildScript = 'param([string]$Marker) Start-Sleep -Seconds 120'
$Process = $null

try {
    $Process = Start-Process `
        -FilePath $PowerShellPath `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $ChildScript, $Marker) `
        -WindowStyle Hidden `
        -PassThru

    $Deadline = [DateTime]::UtcNow.AddSeconds(5)
    $CommandLine = $null
    do {
        $CimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction SilentlyContinue
        if ($CimProcess -and $CimProcess.CommandLine -and
            $CimProcess.CommandLine.IndexOf($ProfileRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $CommandLine = $CimProcess.CommandLine
            break
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        throw "test child process did not expose the Chromium profile marker in its command line"
    }

    Stop-ProcessesUsingPathInCommandLine -Path $ProfileRoot

    try {
        Wait-Process -Id $Process.Id -Timeout 5 -ErrorAction SilentlyContinue
    }
    catch {
    }

    $Remaining = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if ($Remaining -and -not $Remaining.HasExited) {
        throw "Stop-ProcessesUsingPathInCommandLine did not stop a process using the temporary Chromium profile path"
    }

    $ForwardSlashMarker = "--user-data-dir=$($ProfileRoot.Replace('\', '/'))"
    $Process = Start-Process `
        -FilePath $PowerShellPath `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $ChildScript, $ForwardSlashMarker) `
        -WindowStyle Hidden `
        -PassThru

    $Deadline = [DateTime]::UtcNow.AddSeconds(5)
    $CommandLine = $null
    do {
        $CimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction SilentlyContinue
        if ($CimProcess -and $CimProcess.CommandLine -and
            $CimProcess.CommandLine.IndexOf($ForwardSlashMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $CommandLine = $CimProcess.CommandLine
            break
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        throw "test child process did not expose the forward-slash Chromium profile marker in its command line"
    }

    Stop-ProcessesUsingPathInCommandLine -Path $ProfileRoot

    try {
        Wait-Process -Id $Process.Id -Timeout 5 -ErrorAction SilentlyContinue
    }
    catch {
    }

    $Remaining = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if ($Remaining -and -not $Remaining.HasExited) {
        throw "Stop-ProcessesUsingPathInCommandLine did not stop a process using a forward-slash temporary Chromium profile path"
    }
}
finally {
    if ($Process) {
        $Remaining = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
        if ($Remaining -and -not $Remaining.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Chromium smoke cleanup stops processes using the temporary browser profile path."
