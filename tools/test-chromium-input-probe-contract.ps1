param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProbePath = Join-Path $RepoRoot "tools\run-chromium-input-probe.ps1"

if (-not (Test-Path -LiteralPath $ProbePath -PathType Leaf)) {
    throw "missing non-elevated Chromium input probe: tools\run-chromium-input-probe.ps1"
}

$Source = Get-Content -Raw -LiteralPath $ProbePath

foreach ($Required in @(
        '[Threading.Thread]::CurrentThread.ApartmentState -ne "STA"',
        'Find-ChromiumBrowserPath -RequestedPath $BrowserPath',
        'Set-YuneWindowsForegroundChromiumWindow',
        'Invoke-YuneWindowsClientClick',
        'Wait-YuneWindowsWindowTitle',
        'Reset-TextSmokeTargetContent',
        'Reset-TextSmokeClipboard',
        '$TypedInput = "ngohaig"',
        'Send-YuneWindowsAsciiText -Text $TypedInput',
        'Get-YuneWindowsChromiumSmokeEventSummary',
        'ClipboardClearedAfterCapture',
        'machine_state_changed = $false',
        'product_closeout_evidence = $false',
        'Stop-ProcessTree',
        'Stop-ProcessesUsingPathInCommandLine',
        'chromium-input-probe.json'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "Chromium input probe is missing contract text: $Required"
    }
}

foreach ($Forbidden in @(
        'ApprovedMachineStateChange',
        'regsvr32',
        'YuneWindowsProfileTool',
        '--activate',
        'Assert-YuneWindowsProfileActive',
        'Write-YuneWindowsStateSnapshot',
        'Get-YuneWindowsMachineResidue'
    )) {
    if ($Source -match [regex]::Escape($Forbidden)) {
        throw "Chromium input probe must remain non-elevated and product-neutral; found: $Forbidden"
    }
}

Write-Host "Non-elevated Chromium input probe validates browser key delivery without TSF machine-state changes."
