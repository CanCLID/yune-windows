param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Reset-TextSmokeClipboard',
        'System.Windows.Forms.Clipboard',
        'Clipboard]::Clear',
        'clipboard could not be cleared before typing'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing clipboard isolation pattern: $Required"
    }
}

foreach ($SmokeScript in @($NotepadSmoke, $ChromiumSmoke)) {
    $SmokeSource = Get-Content -Raw -LiteralPath $SmokeScript
    $SmokeName = Split-Path -Leaf $SmokeScript
    if ($SmokeSource -notmatch 'Reset-TextSmokeClipboard') {
        throw "$SmokeName must clear the clipboard before typing so stale text cannot satisfy the smoke."
    }
    if ($SmokeSource -notmatch '(Set-YuneWindowsForegroundProcess|Set-YuneWindowsForegroundNotepadWindow|Set-YuneWindowsForegroundChromiumWindow)(?s:.*?)Assert-ForegroundProcess(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)Reset-TextSmokeClipboard(?s:.*?)StructuralLogStartLineCount') {
        throw "$SmokeName must clear the clipboard after app focus/profile verification and before typing."
    }
    if ($SmokeSource -notmatch 'ClipboardClearedAfterCapture') {
        throw "$SmokeName must record that clipboard state was cleared after evidence capture."
    }
    if ($SmokeSource -notmatch 'Clipboard\]::GetText\(\)(?s:.*?)Reset-TextSmokeClipboard(?s:.*?)ClipboardClearedAfterCapture\s*=\s*\$true') {
        throw "$SmokeName must clear the clipboard after capturing observed text evidence."
    }
    if ($SmokeSource -notmatch 'Clipboard cleared after capture: \$ClipboardClearedAfterCapture') {
        throw "$SmokeName result evidence must report whether clipboard state was cleared after capture."
    }
    if ($SmokeSource -notmatch 'ClipboardClearedAfterFailure') {
        throw "$SmokeName must record whether clipboard state was cleared after a failed smoke."
    }
    if ($SmokeSource -notmatch 'catch\s*\{(?s:.*?)if\s*\(\s*-not\s+\$ClipboardClearedAfterCapture\s*\)(?s:.*?)Reset-TextSmokeClipboard(?s:.*?)ClipboardClearedAfterFailure\s*=\s*\$true(?s:.*?)Write-TextSmokeResult') {
        throw "$SmokeName must attempt clipboard cleanup in the failure path before writing failure evidence."
    }
    if ($SmokeSource -notmatch 'Clipboard cleared after failure: \$ClipboardClearedAfterFailure') {
        throw "$SmokeName failure result evidence must report whether failure-path clipboard cleanup ran."
    }
}

Write-Host "Live app smokes clear clipboard evidence state before typing, after capture, and after failed capture paths."
