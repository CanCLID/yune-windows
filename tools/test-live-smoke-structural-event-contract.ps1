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
    foreach ($Required in @(
            'StructuralLogPath',
            'StructuralLogStartLineCount',
            'Get-NewStructuralLogLines',
            'Structural candidate update observed:',
            'Structural candidate update candidate count positive:',
            'Structural commit event observed:',
            'Structural event matcher: exact event tokens',
            'Test-StructuralCandidateUpdateLine -Line $_',
            'Test-StructuralEventLine -Line $_ -EventName "commit_text"'
        )) {
        if (-not $Source.Contains($Required)) {
            throw "$Smoke is missing structural event evidence pattern: $Required"
        }
    }
}

Write-Host "Live text-field smokes record exact structural TSF candidate and commit event proof."
