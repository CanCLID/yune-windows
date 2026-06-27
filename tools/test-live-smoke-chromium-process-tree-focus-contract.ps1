param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Get-ProcessAncestorIds',
        'function Stop-ProcessTree',
        'function Stop-ProcessesUsingPathInCommandLine',
        'function Get-YuneWindowsProcessIdsUsingPathInCommandLine',
        'function Set-YuneWindowsForegroundChromiumWindow',
        'ParentProcessId',
        'CommandLine',
        'YuneWindows Chromium Smoke',
        'ProfileRoot'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing Chromium process-tree focus pattern: $Required"
    }
}

$ChromiumSource = Get-Content -Raw -LiteralPath $ChromiumSmoke
if ($ChromiumSource -notmatch 'Set-YuneWindowsForegroundChromiumWindow(?s:.*?)-ProfileRoot\s+\$ProfileRoot(?s:.*?)Assert-ForegroundWindowHandle(?s:.*?)Assert-ForegroundProcess(?s:.*?)-ProcessId\s+\$BrowserForegroundProcessId(?s:.*?)Assert-YuneWindowsProfileActive') {
    throw "run-chromium-smoke.ps1 must focus the visible Chromium window tied to the temporary profile before typing."
}
foreach ($Required in @(
        '"--app=$Uri"',
        '"--disable-sync"',
        '"--no-default-browser-check"',
        'Chromium smoke browser modal dismissal'
    )) {
    if ($ChromiumSource -notmatch [regex]::Escape($Required)) {
        throw "run-chromium-smoke.ps1 must suppress or dismiss Chromium first-run/sync UI before typing: $Required"
    }
}
if ($ChromiumSource -match '"--guest"') {
    throw "run-chromium-smoke.ps1 should not use Chromium guest mode; the temporary user-data directory already isolates the smoke and app mode gives a cleaner text-field target."
}
if ($ChromiumSource -notmatch 'finally\s*\{(?s:.*?)Stop-ProcessTree\s+-ProcessId\s+\$BrowserProcess\.Id') {
    throw "run-chromium-smoke.ps1 must stop the launched Chromium process tree during cleanup."
}
if ($ChromiumSource -notmatch 'finally\s*\{(?s:.*?)Stop-ProcessesUsingPathInCommandLine\s+-Path\s+\$ProfileRoot(?s:.*?)Remove-YuneWindowsPathWithRetry\s+-Path\s+\$ProfileRoot') {
    throw "run-chromium-smoke.ps1 must stop Chromium processes using the temporary profile before retrying profile cleanup."
}
if ($ChromiumSource -notmatch 'finally\s*\{(?s:.*?)Remove-YuneWindowsPathWithRetry\s+-Path\s+\$ProfileRoot') {
    throw "run-chromium-smoke.ps1 must remove the temporary Chromium user-data directory during cleanup."
}

$NotepadSource = Get-Content -Raw -LiteralPath $NotepadSmoke
if ($NotepadSource -match '-AllowDescendantProcess') {
    throw "run-notepad-smoke.ps1 must keep exact foreground-process verification."
}

Write-Host "Chromium smoke allows foreground focus on a launched browser descendant process."
