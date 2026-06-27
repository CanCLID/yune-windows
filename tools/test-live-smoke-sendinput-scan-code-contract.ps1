param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

foreach ($Required in @(
        'New-YuneWindowsKeyboardInput -VirtualKey 0 -ScanCode $ScanCode -Flags 0x0008',
        'New-YuneWindowsKeyboardInput -VirtualKey 0 -ScanCode $ScanCode -Flags (0x0008 -bor 2)'
    )) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "SendInput helper must dispatch typed input as scan-code keyboard events: $Required"
    }
}

Write-Host "SendInput helper dispatches typed input as scan-code keyboard events."
