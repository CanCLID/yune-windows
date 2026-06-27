param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Assert-SmokeScriptFailureEvidence(
    [string]$RelativePath,
    [string]$ResultFileName
) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing smoke script: $RelativePath"
    }

    $Source = Get-Content -Raw -LiteralPath $Path
    foreach ($Required in @(
            'function\s+Write-TextSmokeResult',
            'Status:\s+\$Status',
            'Failure stage:\s+\$FailureStage',
            'Failure message:\s+\$FailureMessage',
            [regex]::Escape($ResultFileName),
            '\$CurrentStage\s*=',
            'catch\s*\{(?s:.*?)Write-TextSmokeResult(?s:.*?)-Status\s+"failed"',
            'catch\s*\{(?s:.*?)FailureStage\s+\$CurrentStage',
            'catch\s*\{(?s:.*?)FailureMessage\s+\$_\.Exception\.Message',
            'Observed clipboard text after select-all/copy:',
            'Matches expected Yune commit:'
        )) {
        if ($Source -notmatch $Required) {
            throw "$RelativePath is missing durable app-smoke failure evidence pattern: $Required"
        }
    }

    $CatchStart = $Source.IndexOf('if (-not $ResultWritten)')
    if ($CatchStart -lt 0) {
        throw "$RelativePath is missing generic failure result write guard."
    }
    $CatchEnd = $Source.IndexOf('throw', $CatchStart)
    if ($CatchEnd -lt $CatchStart) {
        throw "$RelativePath generic failure result write guard is missing the rethrow boundary."
    }
    $GenericFailureBlock = $Source.Substring($CatchStart, $CatchEnd - $CatchStart)
    foreach ($Required in @(
            '-Pass\s+\(\[string\]\$Pass\)',
            '-Raw\s+\(\[string\]\$Raw\)',
            '-MatchesExpectedCommit\s+\(\[string\]\$MatchesExpectedCommit\)',
            '-StructuralCandidateUpdateObserved\s+\(\[string\]\$StructuralCandidateUpdateObserved\)',
            '-StructuralCommitEventObserved\s+\(\[string\]\$StructuralCommitEventObserved\)',
            '-StructuralNewLineCount\s+\(\[string\]\(\$NewStructuralLogLines\.Count\)\)'
        )) {
        if ($GenericFailureBlock -notmatch $Required) {
            throw "$RelativePath generic failure result must preserve current pass/raw/commit/structural evidence field: $Required"
        }
    }
}

Assert-SmokeScriptFailureEvidence `
    -RelativePath "tools\run-notepad-smoke.ps1" `
    -ResultFileName "notepad-smoke-result.md"
Assert-SmokeScriptFailureEvidence `
    -RelativePath "tools\run-chromium-smoke.ps1" `
    -ResultFileName "chromium-smoke-result.md"

Write-Host "Live app smoke scripts write durable failure result evidence."
