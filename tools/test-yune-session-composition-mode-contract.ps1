$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HostSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\host\yune_host_smoke.cpp")
$ServerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")

function Require-Text([string]$Source, [string]$Pattern, [string]$Description) {
    if ($Source -notmatch $Pattern) {
        throw "missing Yune composition-mode contract: $Description"
    }
}

foreach ($Source in @($HostSource, $ServerSource)) {
    Require-Text $Source 'set_option\([^;]+ascii_mode[^;]+False' "ascii_mode is disabled before smoke input"
    Require-Text $Source 'get_option\([^;]+ascii_mode[^;]+\)\s*==\s*False' "ascii_mode disablement is verified"
    Require-Text $Source 'failed to disable Yune ascii_mode' "ascii_mode failure is explicit"
}

Write-Host "Yune host/server force composition mode before processing smoke input."
