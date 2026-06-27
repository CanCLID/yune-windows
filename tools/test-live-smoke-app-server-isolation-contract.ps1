param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Assert-NoYuneWindowsServerProcess',
        'Get-Process -Name "YuneWindowsServer"',
        'before starting the controlled shared server'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing stale shared-server guard pattern: $Required"
    }
}

foreach ($RelativePath in @(
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $RelativePath
    $Source = Get-Content -Raw -LiteralPath $Path
    $GuardIndex = $Source.IndexOf("Assert-NoYuneWindowsServerProcess", [System.StringComparison]::Ordinal)
    $StartIndex = $Source.IndexOf("start-yune-windows-server.ps1", [System.StringComparison]::Ordinal)
    if ($GuardIndex -lt 0) {
        throw "$RelativePath must check for stale YuneWindowsServer.exe before starting its controlled server."
    }
    if ($StartIndex -lt 0) {
        throw "$RelativePath is missing shared-server startup."
    }
    if ($GuardIndex -gt $StartIndex) {
        throw "$RelativePath checks for stale YuneWindowsServer.exe after shared-server startup."
    }
    if ($Source -notmatch '\$CurrentStage = "server-preflight"(?s:.*?)Assert-NoYuneWindowsServerProcess') {
        throw "$RelativePath must record a server-preflight stage before refusing stale shared-server processes."
    }
}

Write-Host "Live app smokes reject stale shared-server processes before starting controlled app smoke servers."
