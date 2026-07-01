$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$NotepadSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-notepad-smoke.ps1")
$ChromiumSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-chromium-smoke.ps1")

foreach ($Entry in @(
        @{ Name = "Notepad"; Source = $NotepadSmoke },
        @{ Name = "Chromium"; Source = $ChromiumSmoke }
    )) {
    if ($Entry.Source -match 'start-yune-windows-server\.ps1') {
        throw "$($Entry.Name) smoke must not manually start YuneWindowsServer.exe after M02."
    }
    foreach ($Pattern in @(
            'Assert-NoYuneWindowsServerProcess',
            'product_owned_server_start_observed',
            'product_owned_server_ready_observed',
            'ProductOwnedServerStartObserved',
            'ProductOwnedServerReadyObserved',
            'Wait-YuneWindowsProductOwnedServerReady',
            'server launch probe',
            'Cancel-YuneWindowsTextComposition',
            'composition cancel after server launch probe',
            'target-reset-after-server-ready',
            'YuneWindowsServer'
        )) {
        if ($Entry.Source -notmatch [regex]::Escape($Pattern)) {
            throw "$($Entry.Name) smoke is missing product-owned server evidence pattern: $Pattern"
        }
    }
}

Write-Host "Text-field smokes rely on product-owned shared-server startup."
