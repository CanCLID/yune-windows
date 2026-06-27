param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

foreach ($Path in @($SupportScript, $NotepadSmoke, $ChromiumSmoke)) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing required script: $Path"
    }
}

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Wait-YuneWindowsProcessExit',
        '\[switch\]\$RequireExit',
        'throw \$Message',
        'function Stop-ProcessTree(?s:.*?)(CleanupErrors|cleanup failed)',
        'function Stop-ProcessesUsingPathInCommandLine(?s:.*?)(CleanupErrors|cleanup failed)',
        'Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$Id(?s:.*?)-RequireExit',
        'Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$ProcessId(?s:.*?)-RequireExit'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke cleanup must fail when stopped processes remain: $Required"
    }
}

foreach ($SmokeScript in @($NotepadSmoke, $ChromiumSmoke)) {
    $SmokeSource = Get-Content -Raw -LiteralPath $SmokeScript
    $SmokeName = Split-Path -Leaf $SmokeScript
    foreach ($Required in @(
            'CleanupErrors',
            'Wait-YuneWindowsProcessExit(?s:.*?)-RequireExit',
            'cleanup failed',
            'if\s*\(\$CleanupErrors\.Count\s+-gt\s+0\)\s*\{(?s:.*?)Write-TextSmokeResult(?s:.*?)-Status\s+"failed"',
            'if\s*\(\$CleanupErrors\.Count\s+-gt\s+0\)\s*\{(?s:.*?)FailureStage\s+"cleanup"',
            'if\s*\(\$CleanupErrors\.Count\s+-gt\s+0\)\s*\{(?s:.*?)FailureMessage\s+\$CleanupFailureMessage',
            'if\s*\(\$CleanupErrors\.Count\s+-gt\s+0\)\s*\{(?s:.*?)throw\s+\$CleanupFailureMessage'
        )) {
        if ($SmokeSource -notmatch $Required) {
            throw "$SmokeName must preserve cleanup failures in app-smoke results: $Required"
        }
    }
}

. $SupportScript
$PowerShellExe = Join-Path $PSHOME "powershell.exe"
$Process = Start-Process `
    -FilePath $PowerShellExe `
    -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 10") `
    -WindowStyle Hidden `
    -PassThru

try {
    try {
        Wait-YuneWindowsProcessExit `
            -ProcessId $Process.Id `
            -TimeoutSeconds 1 `
            -RequireExit
        throw "Wait-YuneWindowsProcessExit unexpectedly accepted a still-running process"
    }
    catch {
        if ($_.Exception.Message -notmatch "did not exit within 1 seconds") {
            throw
        }
    }
}
finally {
    $Remaining = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if ($Remaining -and -not $Remaining.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Live smoke cleanup fails when stopped processes remain after the cleanup wait."
