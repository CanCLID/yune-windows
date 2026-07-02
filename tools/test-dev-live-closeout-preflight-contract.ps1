param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ScriptPath = Join-Path $RepoRoot "tools\dev\dev-live-closeout-preflight.ps1"
$RunbookPath = Join-Path $RepoRoot "docs\evidence\m06-m07-live-closeout.md"

foreach ($Path in @($ScriptPath, $RunbookPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing required file: $Path"
    }
}

$Source = Get-Content -Raw -LiteralPath $ScriptPath
$Runbook = Get-Content -Raw -LiteralPath $RunbookPath

foreach ($Required in @(
        'Get-YuneWindowsDevInstallPaths',
        'Get-YuneWindowsDevProcessesUsingModule',
        'Format-YuneWindowsDevProcessSummary',
        'RestartExplorerPlanned',
        'ready_for_tsf_swap',
        'ConvertTo-Json'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "live closeout preflight is missing required source marker: $Required"
    }
}

foreach ($Forbidden in @(
        '(?i)\bCopy-Item\b',
        '(?i)\bMove-Item\b',
        '(?i)\bRemove-Item\b',
        '(?i)\bStop-Process\b',
        '(?i)\bStart-Process\b',
        '(?i)\bregsvr32\b',
        '(?i)\bRegister-',
        '(?i)-ApprovedMachineStateChange\b',
        '(?i)build-tsf-shell\.ps1',
        '(?i)dev-reload-tsf\.ps1',
        '(?i)dev-reload-server\.ps1'
    )) {
    if ($Source -match $Forbidden) {
        throw "live closeout preflight must stay read-only and must not match forbidden pattern: $Forbidden"
    }
}

foreach ($RequiredRunbookText in @(
        'tools\dev\dev-live-closeout-preflight.ps1',
        '-RestartExplorerPlanned',
        'preflight must pass before attempting the TSF DLL swap'
    )) {
    if ($Runbook -notmatch [regex]::Escape($RequiredRunbookText)) {
        throw "combined M06/M07 live runbook is missing preflight text: $RequiredRunbookText"
    }
}

Write-Host "M06/M07 live closeout preflight contract passed."
