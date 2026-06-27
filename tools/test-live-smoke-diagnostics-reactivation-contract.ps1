param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$Source = Get-Content -Raw -LiteralPath $OrchestratorPath

foreach ($Required in @(
        '$DiagnosticsProfileTool = Join-Path $InstallDir "YuneWindowsProfileTool.exe"',
        '$DiagnosticsActivationCommand = "YuneWindowsProfileTool.exe --activate for diagnostics pre-state"',
        'Invoke-YuneWindowsProfileTool',
        '-Arguments @("--activate")',
        '-Operation "diagnostics pre-state profile reactivation"',
        'Assert-YuneWindowsProfileActive',
        '-Context "Diagnostics pre-state"',
        'Record-CommandSuccess $DiagnosticsActivationCommand')) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "live smoke orchestrator must reactivate YuneWindows before diagnostics pre-state: $Required"
    }
}

$ChromiumIndex = $Source.IndexOf('$CurrentStage = "chromium-smoke"')
$DiagnosticsActivationIndex = $Source.IndexOf('$CurrentStage = "diagnostics-profile-reactivation"')
$DiagnosticsPreStateIndex = $Source.IndexOf('$CurrentStage = "diagnostics-pre-state"')
if ($ChromiumIndex -lt 0 -or $DiagnosticsActivationIndex -lt 0 -or $DiagnosticsPreStateIndex -lt 0) {
    throw "live smoke orchestrator is missing expected Chromium, diagnostics reactivation, or diagnostics pre-state stages."
}
if ($ChromiumIndex -gt $DiagnosticsActivationIndex -or $DiagnosticsActivationIndex -gt $DiagnosticsPreStateIndex) {
    throw "live smoke orchestrator must reactivate YuneWindows after Chromium and before diagnostics pre-state."
}

Write-Host "Live smoke reactivates YuneWindows before diagnostics pre-state after app cleanup deactivation."
