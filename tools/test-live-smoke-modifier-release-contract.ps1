param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

foreach ($Required in @(
        'function Release-YuneWindowsModifierKeys',
        'VK_CONTROL',
        'VK_MENU',
        'VK_SHIFT',
        '0x5b',
        '0x5c',
        'New-YuneWindowsKeyboardInput -VirtualKey $VirtualKey -ScanCode $ScanCode -Flags 2',
        'Release-YuneWindowsModifierKeys -Context "$Context target reset"'
    )) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke support must release modifiers after target reset before typed input: $Required"
    }
}

foreach ($RelativePath in @(
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1",
        "tools\run-chromium-input-probe.ps1"
    )) {
    $Source = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $RelativePath)
    $ResetIndex = $Source.IndexOf('Reset-TextSmokeTargetContent')
    $TypingIndex = $Source.IndexOf('Send-YuneWindowsAsciiText -Text $TypedInput')
    if ($ResetIndex -lt 0 -or $TypingIndex -lt 0 -or $ResetIndex -ge $TypingIndex) {
        throw "$RelativePath must reset target content before typing."
    }
}

Write-Host "Live smoke releases shortcut modifiers after target reset before typed input."
