param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

foreach ($RelativePath in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing smoke script: $RelativePath"
    }

    $Source = Get-Content -Raw -LiteralPath $Path
    $Name = Split-Path -Leaf $Path
    $PassPattern = '\$Pass\s*=\s*\$MatchesExpectedCommit\s+-and\s*' +
        '\$ForegroundTargetVerifiedBeforeTyping\s+-and\s*' +
        '(\$TextFieldClickVerifiedBeforeTyping\s+-and\s*)?' +
        '(\$TextareaFocusVerifiedBeforeTyping\s+-and\s*)?' +
        '\$ActiveProfileVerifiedBeforeTyping\s+-and\s*' +
        '\$ClipboardClearedBeforeTyping\s+-and\s*' +
        '\$ClipboardClearedAfterCapture\s+-and\s*' +
        '\$CandidateScreenshotCaptured\s+-and\s*' +
        '\$CommitScreenshotCaptured\s+-and\s*' +
        '\$CandidateCommitScreenshotsDistinct\s+-and\s*' +
        '\$StructuralCandidateUpdateObserved\s+-and\s*' +
        '\$StructuralCandidateUpdateCandidateCountPositive\s+-and\s*' +
        '\$StructuralCommitEventObserved'

    if ($Source -notmatch $PassPattern) {
        throw "$Name must require foreground-target proof, active-profile proof, clipboard cleanup, screenshot capture, expected commit text, and structural TSF events before reporting Pass: True."
    }

    if ($Name -eq "run-chromium-smoke.ps1" -and
        $Source -notmatch '\$Pass\s*=\s*\$MatchesExpectedCommit(?s:.*?)\$TextareaFocusVerifiedBeforeTyping\s+-and(?s:.*?)\$ActiveProfileVerifiedBeforeTyping') {
        throw "$Name must require title-confirmed Chromium textarea focus before reporting Pass: True."
    }

    if ($Name -eq "run-chromium-smoke.ps1" -and
        $Source -notmatch '\$Pass\s*=\s*\$MatchesExpectedCommit(?s:.*?)\$TextFieldClickVerifiedBeforeTyping\s+-and(?s:.*?)\$TextareaFocusVerifiedBeforeTyping') {
        throw "$Name must require Win32 text-field click proof before reporting Pass: True."
    }

    foreach ($RequiredLine in @(
            "Candidate-display screenshot captured:",
            "Commit screenshot captured:",
            "Candidate/commit screenshots distinct:",
            "Chromium text-field click verified before typing:",
            "Chromium textarea focus verified before typing:",
            "Structural candidate update candidate count positive:"
        )) {
        if ($Name -eq "run-notepad-smoke.ps1" -and $RequiredLine.StartsWith("Chromium ")) {
            continue
        }
        if ($Source -notmatch [regex]::Escape($RequiredLine)) {
            throw "$Name must write result evidence line: $RequiredLine"
        }
    }
}

Write-Host "Live app-smoke pass criteria require foreground, active-profile, clipboard cleanup, screenshot quality, expected commit, and structural-event proof."
