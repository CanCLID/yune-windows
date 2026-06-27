param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\live-smoke-support.ps1")
foreach ($Required in @(
        'SendInput',
        'public struct KeyboardInput',
        'public struct Input',
        'MapVirtualKey',
        '$ScanCode = [byte]([YuneWindowsWindows.ForegroundWindow]::MapVirtualKey([uint32]$VirtualKey, 0) -band 0xff)',
        '$InputSize = [System.Runtime.InteropServices.Marshal]::SizeOf([YuneWindowsWindows.Input]::new())',
        'SendInput([uint32]$Inputs.Length, $Inputs, $InputSize)',
        'if ($SentInputCount -ne $Inputs.Length)'
    )) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "live-smoke support must send virtual-key input with scan-code evidence path: $Required"
    }
}

foreach ($RelativePath in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    $Path = Join-Path $RepoRoot $RelativePath
    $Source = Get-Content -Raw -LiteralPath $Path
    $Name = Split-Path -Leaf $Path

    foreach ($Required in @(
            '$TypedInput = "ngohaig"',
            'Input method: Win32 virtual-key typed test input.',
            'Reset-TextSmokeTargetContent',
            'Send-YuneWindowsAsciiText -Text $TypedInput',
            'Send-YuneWindowsVirtualKey -VirtualKey 0x20'
        )) {
        if ($Source -notmatch [regex]::Escape($Required)) {
            throw "$Name is missing typed-input evidence pattern: $Required"
        }
    }

    $TypingIndex = $Source.IndexOf('Send-YuneWindowsAsciiText -Text $TypedInput')
    $ClipboardCopyIndex = $Source.IndexOf('[System.Windows.Forms.SendKeys]::SendWait("^c")')
    if ($TypingIndex -lt 0 -or $ClipboardCopyIndex -lt 0 -or $TypingIndex -ge $ClipboardCopyIndex) {
        throw "$Name must send the approved test input before clipboard capture."
    }

    $BeforeTyping = $Source.Substring(0, $TypingIndex)
    if ($BeforeTyping -match 'Clipboard\]::SetText') {
        throw "$Name must not seed typed-smoke input through the clipboard before typing."
    }
}

Write-Host "Live app smokes record that the approved test input is typed through virtual-key events, not pasted."
