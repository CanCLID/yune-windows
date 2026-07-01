param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Assert-NoYuneWindowsServerProcess',
        'Get-Process -Name "YuneWindowsServer"',
        'YuneWindowsServer.exe process'
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
    if ($GuardIndex -lt 0) {
        throw "$RelativePath must check for stale YuneWindowsServer.exe before product-owned server startup is exercised."
    }
    if ($Source -match 'start-yune-windows-server\.ps1') {
        throw "$RelativePath must not manually start YuneWindowsServer.exe after P2-WIN02."
    }
    if ($Source -notmatch '\$CurrentStage = "server-preflight"(?s:.*?)Assert-NoYuneWindowsServerProcess') {
        throw "$RelativePath must record a server-preflight stage before refusing stale shared-server processes."
    }
    if ($Source -notmatch 'ProductOwnedServerStartObserved') {
        throw "$RelativePath must record product-owned server startup evidence."
    }
}

Write-Host "Live app smokes reject stale shared-server processes before exercising product-owned startup."
