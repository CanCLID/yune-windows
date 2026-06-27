param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadPath = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumPath = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

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

function Assert-SmokeScriptDeactivatesBeforeClosingTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$SmokeName,
        [Parameter(Mandatory = $true)]
        [string[]]$CloseMarkers
    )

    $Source = Get-Content -Raw -LiteralPath $Path
    if ($Source -notmatch '\$ProfileActivatedForSmoke\s*=\s*\$false') {
        throw "$SmokeName must initialize profile-activation tracking."
    }
    if ($Source -notmatch '(?s)--activate.*?Assert-YuneWindowsProfileActive.*?\$ProfileActivatedForSmoke\s*=\s*\$true') {
        throw "$SmokeName must mark the profile active only after activation is verified."
    }

    $FinallyIndex = $Source.LastIndexOf('finally {', [System.StringComparison]::Ordinal)
    if ($FinallyIndex -lt 0) {
        throw "$SmokeName is missing a finally cleanup block."
    }
    $FinallySource = $Source.Substring($FinallyIndex)
    $DeactivateIndex = $FinallySource.IndexOf(
        'Invoke-YuneWindowsProfileDeactivationForSmoke',
        [System.StringComparison]::Ordinal)
    if ($DeactivateIndex -lt 0) {
        throw "$SmokeName must deactivate the YuneWindows profile during cleanup."
    }
    foreach ($Marker in $CloseMarkers) {
        $CloseIndex = $FinallySource.IndexOf($Marker, [System.StringComparison]::Ordinal)
        if ($CloseIndex -ge 0 -and $CloseIndex -lt $DeactivateIndex) {
            throw "$SmokeName must deactivate the YuneWindows profile before target cleanup marker: $Marker"
        }
    }
}

Assert-SmokeScriptDeactivatesBeforeClosingTarget `
    -Path $NotepadPath `
    -SmokeName "Notepad smoke" `
    -CloseMarkers @(
        'Stop-Process -Id $Notepad.Id',
        'Stop-YuneWindowsNotepadSmokeProcesses',
        'Stop-Process -Id $ServerProcess.Id'
    )

Assert-SmokeScriptDeactivatesBeforeClosingTarget `
    -Path $ChromiumPath `
    -SmokeName "Chromium smoke" `
    -CloseMarkers @(
        'Stop-ProcessTree -ProcessId $BrowserProcess.Id',
        'Stop-ProcessesUsingPathInCommandLine',
        'Stop-Process -Id $ServerProcess.Id'
    )

Write-Host "Live app smokes deactivate the YuneWindows profile before target cleanup returns focus to the launcher."
