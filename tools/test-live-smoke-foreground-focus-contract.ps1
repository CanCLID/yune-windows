param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Assert-ForegroundProcess',
        'function Set-YuneWindowsForegroundProcess',
        'function Set-YuneWindowsForegroundNotepadWindow',
        'function Set-YuneWindowsForegroundChromiumWindow',
        'function Invoke-YuneWindowsClientClick',
        'function Assert-ForegroundWindowHandle',
        'function Get-ForegroundProcessId',
        'GetForegroundWindow',
        'ClientToScreen',
        'mouse_event',
        'EnumWindows',
        'GetWindowThreadProcessId',
        'SetForegroundWindow',
        'did not have foreground focus before typing'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing foreground focus verification pattern: $Required"
    }
}

$NotepadSource = Get-Content -Raw -LiteralPath $NotepadSmoke
if ($NotepadSource -notmatch 'Set-YuneWindowsForegroundNotepadWindow(?s:.*?)Assert-ForegroundWindowHandle(?s:.*?)Assert-ForegroundProcess(?s:.*?)-ProcessId\s+\$NotepadForegroundProcessId(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)StructuralLogStartLineCount') {
    throw "run-notepad-smoke.ps1 must assert foreground focus for the visible Notepad window before profile re-check and typing."
}

$ChromiumSource = Get-Content -Raw -LiteralPath $ChromiumSmoke
if ($ChromiumSource -notmatch 'Set-YuneWindowsForegroundChromiumWindow(?s:.*?)Assert-ForegroundWindowHandle(?s:.*?)Assert-ForegroundProcess(?s:.*?)-ProcessId\s+\$BrowserForegroundProcessId(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)StructuralLogStartLineCount') {
    throw "run-chromium-smoke.ps1 must assert foreground focus for the visible Chromium window before profile re-check and typing."
}

if ($ChromiumSource -notmatch 'browser-text-field-click(?s:.*?)Invoke-YuneWindowsClientClick(?s:.*?)profile-activation-after-focus' -or
    $ChromiumSource -notmatch 'Chromium smoke before typing(?s:.*?)Invoke-YuneWindowsClientClick(?s:.*?)Send-YuneWindowsAsciiText') {
    throw "run-chromium-smoke.ps1 must click the visible Chromium text field before typing."
}

Write-Host "Live app smokes verify foreground target process and Chromium text-field focus before typing."
