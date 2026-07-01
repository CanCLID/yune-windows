$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$NotepadSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-notepad-smoke.ps1")
$ChromiumSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-chromium-smoke.ps1")

foreach ($Entry in @(
        @{ Name = "Notepad"; Source = $NotepadSmoke },
        @{ Name = "Chromium"; Source = $ChromiumSmoke }
    )) {
    if ($Entry.Source -match '--activate') {
        throw "$($Entry.Name) smoke must not reactivate the profile immediately before typing."
    }
    foreach ($Pattern in @(
            'Assert-YuneWindowsProfileActive',
            'profile_active_verified_before_typing'
        )) {
        if ($Entry.Source -notmatch [regex]::Escape($Pattern)) {
            throw "$($Entry.Name) smoke is missing cold profile verification pattern: $Pattern"
        }
    }
}

Write-Host "Text-field smokes verify profile selection without hiding activation loss."
