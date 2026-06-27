param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

foreach ($Required in @(
        'function New-YuneWindowsKeyboardInput',
        '$KeyboardInput = [YuneWindowsWindows.KeyboardInput]::new()',
        '$InputUnion = [YuneWindowsWindows.InputUnion]::new()',
        '$InputUnion.ki = $KeyboardInput',
        '$Input.U = $InputUnion',
        'New-YuneWindowsKeyboardInput -VirtualKey 0 -ScanCode $ScanCode -Flags 0x0008',
        'New-YuneWindowsKeyboardInput -VirtualKey 0 -ScanCode $ScanCode -Flags (0x0008 -bor 2)'
    )) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "SendInput helper must build complete keyboard INPUT records explicitly: $Required"
    }
}

if ($SupportSource -match '\$Inputs\[[^\]]+\]\.U\.ki\.') {
    throw "SendInput helper must not assign nested INPUT union fields through array-element chains."
}

Write-Host "SendInput helper builds complete keyboard INPUT records explicitly."
