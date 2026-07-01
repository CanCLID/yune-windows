param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadPath = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumPath = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$UninstallPath = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportPath
if ($SupportSource -notmatch 'function Invoke-YuneWindowsProfileDeactivationForSmoke') {
    throw "live smoke support must expose a reusable profile deactivation helper for app cleanup."
}
foreach ($Required in @(
        '-Arguments @("--deactivate")',
        'Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false',
        'profile deactivation for cleanup')) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "profile deactivation helper is missing required behavior: $Required"
    }
}

function Assert-SmokeScriptDoesNotOwnProfileActivationCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$SmokeName
    )

    $Source = Get-Content -Raw -LiteralPath $Path
    if ($Source -match '--activate') {
        throw "$SmokeName must not activate the profile; live orchestrator owns text-field profile selection."
    }
    if ($Source -match 'Invoke-YuneWindowsProfileDeactivationForSmoke') {
        throw "$SmokeName must not deactivate the profile between text-field smokes."
    }

    $FinallyIndex = $Source.LastIndexOf('finally {', [System.StringComparison]::Ordinal)
    if ($FinallyIndex -lt 0) {
        throw "$SmokeName is missing a finally cleanup block."
    }
    $FinallySource = $Source.Substring($FinallyIndex)
    if ($FinallySource -notmatch 'Stop-Process|Stop-ProcessTree|Stop-YuneWindowsNotepadSmokeProcesses') {
        throw "$SmokeName must still clean up its target app/server processes."
    }
}

Assert-SmokeScriptDoesNotOwnProfileActivationCleanup `
    -Path $NotepadPath `
    -SmokeName "Notepad smoke"

Assert-SmokeScriptDoesNotOwnProfileActivationCleanup `
    -Path $ChromiumPath `
    -SmokeName "Chromium smoke"

$UninstallSource = Get-Content -Raw -LiteralPath $UninstallPath
if ($UninstallSource -notmatch 'Invoke-YuneWindowsProfileDeactivation\s+-ProfileToolPath\s+\$ProfileTool') {
    throw "uninstaller must deactivate the YuneWindows profile before unregistering/cleanup."
}

Write-Host "Text-field smokes preserve one-time profile selection; uninstall owns profile deactivation cleanup."
