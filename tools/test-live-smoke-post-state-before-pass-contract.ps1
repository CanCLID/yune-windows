param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

foreach ($Check in @(
        @{
            RelativePath = "tools\run-notepad-smoke.ps1"
            StateFile = "notepad-post-state.json"
        },
        @{
            RelativePath = "tools\run-chromium-smoke.ps1"
            StateFile = "chromium-post-state.json"
        }
    )) {
    $Path = Join-Path $RepoRoot $Check.RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing smoke script: $($Check.RelativePath)"
    }

    $Source = Get-Content -Raw -LiteralPath $Path
    $Name = Split-Path -Leaf $Path
    foreach ($Required in @(
            'PostStateSnapshotWritten',
            'function Write-PostSmokeStateSnapshot',
            $Check.StateFile,
            'if (-not $PostStateSnapshotWritten)'
        )) {
        if ($Source -notmatch [regex]::Escape($Required)) {
            throw "$Name is missing post-smoke state snapshot pattern: $Required"
        }
    }

    $SuccessPattern = '\$CurrentStage\s*=\s+"post-state"(?s:.*?)' +
        'Write-PostSmokeStateSnapshot(?s:.*?)' +
        'Write-TextSmokeResult(?s:.*?)-Status\s+"passed"'
    if ($Source -notmatch $SuccessPattern) {
        throw "$Name must write the app-specific post-smoke state snapshot before writing a passed result."
    }
}

Write-Host "Live app smokes write post-smoke state before reporting a passing result."
