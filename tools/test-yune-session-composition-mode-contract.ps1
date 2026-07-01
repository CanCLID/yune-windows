$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HostSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\host\yune_host_smoke.cpp")
$ServerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")

function Require-Text([string]$Source, [string]$Pattern, [string]$Description) {
    if ($Source -notmatch $Pattern) {
        throw "missing Yune composition-mode contract: $Description"
    }
}

Require-Text $HostSource 'set_option\([^;]+ascii_mode[^;]+False' "host ascii_mode is disabled before smoke input"
Require-Text $HostSource 'get_option\([^;]+ascii_mode[^;]+\)\s*==\s*False' "host ascii_mode disablement is verified"
Require-Text $HostSource 'failed to disable Yune ascii_mode' "host ascii_mode failure is explicit"

Require-Text $ServerSource 'struct YuneState(?s:.*?)bool ascii_mode = false;' "server default state starts in composition mode"
Require-Text $ServerSource 'api_->set_option\(session, "ascii_mode", ToRimeBool\(state_\.ascii_mode\)\)' "server applies state-owned ascii_mode"
Require-Text $ServerSource 'api_->get_option\(session, "ascii_mode"\) ==\s+ToRimeBool\(state_\.ascii_mode\)' "server verifies state-owned ascii_mode"
Require-Text $ServerSource 'failed to apply Yune ascii_mode' "server ascii_mode failure is explicit"

Write-Host "Yune host/server force composition mode before processing smoke input."
