param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProbePath = Join-Path $RepoRoot "tools\run-chromium-input-probe.ps1"
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"

$ProbeSource = Get-Content -Raw -LiteralPath $ProbePath
$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

if ($SupportSource -notmatch 'function\s+Remove-YuneWindowsPathWithRetry') {
    throw "live smoke support must expose Remove-YuneWindowsPathWithRetry for delayed browser profile cleanup."
}

if ($ProbeSource -notmatch 'Stop-ProcessesUsingPathInCommandLine\s+-Path\s+\$ProfileRoot') {
    throw "Chromium input probe must stop processes using the temporary profile before cleanup."
}

if ($ProbeSource -notmatch 'Remove-YuneWindowsPathWithRetry\s+-Path\s+\$ProfileRoot') {
    throw "Chromium input probe must retry temporary profile cleanup after browser shutdown."
}

Write-Host "Chromium input probe retries temporary profile cleanup after browser shutdown."
