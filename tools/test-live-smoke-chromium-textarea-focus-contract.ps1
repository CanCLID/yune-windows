param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$ChromiumSource = Get-Content -Raw -LiteralPath $ChromiumSmoke

foreach ($Required in @(
        'id="yune_windows-chromium-smoke-input"',
        'function focusSmokeInput',
        'function markSmokeFocusState',
        'yune_windows-chromium-smoke-input',
        'Textarea Focused',
        'DOMContentLoaded',
        'window.addEventListener\(''focus''',
        'document.addEventListener\(''visibilitychange''',
        'setTimeout\(focusSmokeInput',
        '--do-not-de-elevate',
        'Wait-YuneWindowsWindowTitle',
        'Chromium text-field click verified before typing',
        'Chromium textarea focus verified before typing'
    )) {
    if ($ChromiumSource -notmatch $Required) {
        throw "run-chromium-smoke.ps1 is missing Chromium textarea focus hardening pattern: $Required"
    }
}

$SupportSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\live-smoke-support.ps1")
foreach ($RequiredSupport in @(
        'function Wait-YuneWindowsWindowTitle',
        'Get-YuneWindowsWindowTitle',
        'Last title'
    )) {
    if ($SupportSource -notmatch $RequiredSupport) {
        throw "live-smoke-support.ps1 is missing Chromium textarea title-wait support: $RequiredSupport"
    }
}

Write-Host "Chromium smoke page actively focuses the textarea before live typing."
