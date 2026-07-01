param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$LiveSmoke = Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Wait-YuneWindowsProfileRegistered',
        '-Arguments @("--state")',
        'Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $true',
        'Start-Sleep -Milliseconds $DelayMilliseconds',
        'profile registration did not become visible'
    )) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke support is missing bounded profile-registration wait pattern: $Required"
    }
}

$LiveSource = Get-Content -Raw -LiteralPath $LiveSmoke
foreach ($Required in @(
        '$CurrentStage = "post-install-profile-registration"',
        '$ProfileRegistrationCommand = "YuneWindowsProfileTool.exe --state wait for profile registration"',
        'Wait-YuneWindowsProfileRegistered',
        '-Operation "text-field smoke profile activation"'
    )) {
    if ($LiveSource -notmatch [regex]::Escape($Required)) {
        throw "live orchestrator is missing profile-registration wait before activation pattern: $Required"
    }
}

$WaitIndex = $LiveSource.IndexOf('Wait-YuneWindowsProfileRegistered')
$ActivateIndex = $LiveSource.IndexOf('-Operation "text-field smoke profile activation"')
if ($WaitIndex -lt 0 -or $ActivateIndex -lt 0 -or $WaitIndex -gt $ActivateIndex) {
    throw "live orchestrator must wait for profile registration before activating the YuneWindows profile."
}

Write-Host "Live smoke waits for profile registration before activation."
