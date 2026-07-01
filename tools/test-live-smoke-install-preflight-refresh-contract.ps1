param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1"
$InstallScriptPath = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"

$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
$InstallSource = Get-Content -Raw -LiteralPath $InstallScriptPath

foreach ($Required in @(
        '[string]$BrowserPath = ""',
        '-BrowserPath $BrowserPath'
    )) {
    if ($InstallSource -notmatch [regex]::Escape($Required)) {
        throw "install preflight is missing browser-path support: $Required"
    }
}

foreach ($Required in @(
        '$CurrentStage = "install-preflight"',
        '$InstallPreflightPath = Join-Path $InstallerEvidence "install-preflight.json"',
        '$InstallPreflightCommand = "tools\install-yune-windows-ime.ps1 -PreflightOnly',
        '$InstallPreflightCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"',
        'Record-Command $InstallPreflightCommand',
        '-PreflightOnly',
        '-PreflightPath $InstallPreflightPath',
        '-RefreshCurrentResidue',
        '-ApprovalNote $ApprovalNote',
        '-BrowserPath $ResolvedBrowserPath',
        'Assert-M01PreflightReady',
        'Record-CommandSuccess $InstallPreflightCommand',
        'Record-CommandFailure $InstallPreflightCommand',
        '-FailureStage $CurrentStage'
    )) {
    if ($OrchestratorSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke orchestrator is missing install-preflight refresh pattern: $Required"
    }
}

$LivePreflightIndex = $OrchestratorSource.IndexOf('$CurrentStage = "live-preflight"')
$InstallPreflightIndex = $OrchestratorSource.IndexOf('$CurrentStage = "install-preflight"')
$ProfileBuildIndex = $OrchestratorSource.IndexOf('$CurrentStage = "profile-probe-build"')
$InstallIndex = $OrchestratorSource.IndexOf('$CurrentStage = "install"')
if ($LivePreflightIndex -lt 0 -or
    $InstallPreflightIndex -lt 0 -or
    $ProfileBuildIndex -lt 0 -or
    $InstallIndex -lt 0) {
    throw "live smoke orchestrator is missing expected stage markers."
}
if (-not ($LivePreflightIndex -lt $InstallPreflightIndex -and
        $InstallPreflightIndex -lt $ProfileBuildIndex -and
        $InstallPreflightIndex -lt $InstallIndex)) {
    throw "install preflight must run after live preflight and before profile build/install."
}

$CommandIndex = $OrchestratorSource.IndexOf('$InstallPreflightCommand = "tools\install-yune-windows-ime.ps1 -PreflightOnly', $InstallPreflightIndex)
$AppendBrowserIndex = $OrchestratorSource.IndexOf('$InstallPreflightCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"', $InstallPreflightIndex)
$RecordIndex = $OrchestratorSource.IndexOf('Record-Command $InstallPreflightCommand', $InstallPreflightIndex)
$InvokeIndex = $OrchestratorSource.IndexOf('& (Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1")', $InstallPreflightIndex)
$AssertIndex = $OrchestratorSource.IndexOf('Assert-M01PreflightReady', $InstallPreflightIndex)
$SuccessIndex = $OrchestratorSource.IndexOf('Record-CommandSuccess $InstallPreflightCommand', $InstallPreflightIndex)
$FailureIndex = $OrchestratorSource.IndexOf('Record-CommandFailure $InstallPreflightCommand', $InstallPreflightIndex)
if ($CommandIndex -lt 0 -or
    $AppendBrowserIndex -lt 0 -or
    $RecordIndex -lt 0 -or
    $InvokeIndex -lt 0 -or
    $AssertIndex -lt 0 -or
    $SuccessIndex -lt 0 -or
    $FailureIndex -lt 0) {
    throw "live smoke orchestrator is missing expected install-preflight command transcript markers."
}
if (-not ($InstallPreflightIndex -lt $CommandIndex -and
        $CommandIndex -lt $AppendBrowserIndex -and
        $AppendBrowserIndex -lt $RecordIndex -and
        $RecordIndex -lt $InvokeIndex -and
        $InvokeIndex -lt $AssertIndex -and
        $AssertIndex -lt $SuccessIndex)) {
    throw "install-preflight command transcript must record start before assertion and PASS after assertion."
}
if ($FailureIndex -lt $RecordIndex) {
    throw "install-preflight command transcript must record FAIL only after the start line can be written."
}

Write-Host "Live smoke refreshes install preflight before profile build/install."
