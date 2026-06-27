param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Wait-YuneWindowsProcessExit',
        'Wait-Process',
        'Stop-ProcessTree(?s:.*?)Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$Id',
        'Stop-ProcessesUsingPathInCommandLine(?s:.*?)Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$ProcessId'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke cleanup must wait for stopped processes before removing app/profile state: $Required"
    }
}

$ChromiumSource = Get-Content -Raw -LiteralPath $ChromiumSmoke
if ($ChromiumSource -notmatch 'finally\s*\{(?s:.*?)Stop-ProcessTree\s+-ProcessId\s+\$BrowserProcess\.Id(?s:.*?)Stop-ProcessesUsingPathInCommandLine\s+-Path\s+\$ProfileRoot(?s:.*?)Remove-YuneWindowsPathWithRetry\s+-Path\s+\$ProfileRoot') {
    throw "Chromium smoke must stop and wait on profile-using processes before retrying temporary profile cleanup."
}

Write-Host "Live smoke cleanup waits for stopped processes before removing app/profile state."
