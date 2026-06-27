param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Save-TextSmokeFailureScreenshot',
        'Capture-DesktopScreenshot',
        'captured = \$true',
        'captured = \$false'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing failure-screenshot helper pattern: $Required"
    }
}

$Checks = @(
    @{
        Path = $NotepadSmoke
        Name = "run-notepad-smoke.ps1"
        ScreenshotName = "failure-notepad.png"
    },
    @{
        Path = $ChromiumSmoke
        Name = "run-chromium-smoke.ps1"
        ScreenshotName = "failure-chromium.png"
    }
)

foreach ($Check in $Checks) {
    $Source = Get-Content -Raw -LiteralPath $Check.Path
    foreach ($Required in @(
            [regex]::Escape($Check.ScreenshotName),
            'Failure screenshot:',
            'Failure screenshot captured:',
            'Save-TextSmokeFailureScreenshot',
            'if\s*\(\s*-not\s+\$Pass\s*\)\s*\{(?s:.*?)Save-TextSmokeFailureScreenshot(?s:.*?)Write-TextSmokeResult',
            'catch\s*\{(?s:.*?)Save-TextSmokeFailureScreenshot(?s:.*?)Write-TextSmokeResult',
            'if\s*\(\$CleanupErrors\.Count\s+-gt\s+0\)\s*\{(?s:.*?)Save-TextSmokeFailureScreenshot(?s:.*?)Write-TextSmokeResult(?s:.*?)-FailureScreenshot\s+\$FailureScreenshotName(?s:.*?)-FailureScreenshotCaptured\s+\(\[string\]\$FailureScreenshot\.captured\)(?s:.*?)-FailureScreenshotError\s+\(\[string\]\$FailureScreenshot\.error\)'
        )) {
        if ($Source -notmatch $Required) {
            throw "$($Check.Name) is missing app-smoke failure screenshot pattern: $Required"
        }
    }
}

Write-Host "Live app smokes capture a desktop screenshot for failed app-smoke evidence."
