param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

if (-not (Test-StructuralEventLine -Line "event=commit_text sequence=3 buffer_length=7 candidate_count=5" -EventName "commit_text")) {
    throw "exact commit_text event token should match"
}
if (Test-StructuralEventLine -Line "event=commit_text_failed sequence=3 buffer_length=7 candidate_count=5" -EventName "commit_text") {
    throw "commit_text_failed must not satisfy commit_text evidence"
}
if (-not (Test-StructuralEventLine -Line "event=candidate_update sequence=2 buffer_length=7 candidate_count=5" -EventName "candidate_update")) {
    throw "exact candidate_update event token should match"
}
if (Test-StructuralEventLine -Line "event=candidate_update_failed sequence=2 buffer_length=7 candidate_count=5" -EventName "candidate_update") {
    throw "candidate_update_failed must not satisfy candidate_update evidence"
}
if (-not (Test-StructuralCandidateUpdateLine -Line "event=candidate_update sequence=2 buffer_length=7 candidate_count=5")) {
    throw "candidate_update with positive candidate_count should satisfy candidate display evidence"
}
if (Test-StructuralCandidateUpdateLine -Line "event=candidate_update sequence=2 buffer_length=7 candidate_count=0") {
    throw "candidate_update with zero candidate_count must not satisfy candidate display evidence"
}
if (Test-StructuralCandidateUpdateLine -Line "event=candidate_update_failed sequence=2 buffer_length=7 candidate_count=5") {
    throw "candidate_update_failed must not satisfy candidate display evidence"
}

foreach ($Smoke in @(
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $Smoke
    $Source = Get-Content -Raw -LiteralPath $Path
    if (-not $Source.Contains('Test-StructuralCandidateUpdateLine -Line $_')) {
        throw "$Smoke must use positive-count structural candidate_update matching"
    }
    if (-not $Source.Contains('Test-StructuralEventLine -Line $_ -EventName "commit_text"')) {
        throw "$Smoke must use exact structural event matching for commit_text"
    }
}

Write-Host "Live text-field smokes use exact structural event token matching with positive candidate counts."
