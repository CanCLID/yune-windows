param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Require-Text([string]$RelativePath, [string]$Pattern, [string]$Reason) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing required file: $RelativePath"
    }
    if (-not (Select-String -Path $Path -Pattern $Pattern -Quiet)) {
        throw "$RelativePath is missing $Reason"
    }
}

foreach ($Smoke in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    Require-Text $Smoke "ExpectedCommitText" "expected Yune commit text"
    Require-Text $Smoke "MatchesExpectedCommit" "expected-commit comparison"
    Require-Text $Smoke '\$Pass\s*=\s*\$MatchesExpectedCommit\s+-and' "pass criteria tied to expected Yune commit"
    Require-Text $Smoke "StructuralCandidateUpdateObserved" "structural candidate-update comparison"
    Require-Text $Smoke "StructuralCommitEventObserved" "structural commit-event comparison"
    Require-Text $Smoke "Matches expected Yune commit:" "result evidence for expected Yune commit"
}

Write-Host "Live text-field smokes require the expected Yune commit and structural TSF events for ngohaig."
