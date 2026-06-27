param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

foreach ($Smoke in @(
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $Smoke
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing smoke script: $Smoke"
    }

    $Source = Get-Content -Raw -LiteralPath $Path
    if (-not $Source.Contains("Structural event matcher: exact event tokens")) {
        throw "$Smoke must write exact structural-event matcher proof to app-smoke result evidence"
    }
}

Write-Host "Live app smokes write exact structural-event matcher proof in result evidence."
