param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

foreach ($RelativePath in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    $Path = Join-Path $RepoRoot $RelativePath
    $Source = Get-Content -Raw -LiteralPath $Path
    $Name = Split-Path -Leaf $Path

    foreach ($Required in @(
            '$ForegroundTargetVerifiedBeforeTyping = $false',
            'Foreground target verified before typing: $ForegroundTargetVerifiedBeforeTyping',
            'Assert-ForegroundProcess',
            '$ForegroundTargetVerifiedBeforeTyping = $true'
        )) {
        if ($Source -notmatch [regex]::Escape($Required)) {
            throw "$Name is missing foreground-verification evidence pattern: $Required"
        }
    }

    $AssertIndex = $Source.IndexOf("Assert-ForegroundProcess")
    $VerifiedIndex = $Source.IndexOf('$ForegroundTargetVerifiedBeforeTyping = $true')
    $TypingIndex = $Source.IndexOf('Send-YuneWindowsAsciiText -Text $TypedInput')
    if ($AssertIndex -lt 0 -or $VerifiedIndex -lt 0 -or $TypingIndex -lt 0) {
        throw "$Name is missing foreground verification, result state, or typing call."
    }
    if ($AssertIndex -ge $VerifiedIndex -or $VerifiedIndex -ge $TypingIndex) {
        throw "$Name must record foreground target verification after Assert-ForegroundProcess and before typing."
    }
}

Write-Host "Live app smokes record foreground target verification before typing."
