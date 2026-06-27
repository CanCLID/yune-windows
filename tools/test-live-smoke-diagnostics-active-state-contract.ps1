param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$Source = Get-Content -Raw -LiteralPath $OrchestratorPath

function Require-OrderedText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Needle,
        [Parameter(Mandatory = $true)]
        [string]$Reason,
        [Parameter(Mandatory = $true)]
        [ref]$PreviousIndex
    )

    $Index = $Source.IndexOf($Needle, $PreviousIndex.Value + 1)
    if ($Index -lt 0) {
        throw "tools\run-p2-win01-live-smoke.ps1 is missing $Reason."
    }
    if ($Index -le $PreviousIndex.Value) {
        throw "tools\run-p2-win01-live-smoke.ps1 records $Reason out of order."
    }
    $PreviousIndex.Value = $Index
}

$PreviousIndex = [ref](-1)
Require-OrderedText '$CurrentStage = "diagnostics-pre-state"' "diagnostics pre-state stage" $PreviousIndex
Require-OrderedText 'diagnostics-pre-state.json' "diagnostics pre-state snapshot path" $PreviousIndex
Require-OrderedText 'Invoke-YuneWindowsInteractiveScript' "interactive diagnostics pre-state snapshot launch" $PreviousIndex
Require-OrderedText 'write-yune-windows-state-snapshot.ps1' "interactive diagnostics pre-state snapshot helper" $PreviousIndex
Require-OrderedText '$DiagnosticsPreStatePath' "diagnostics pre-state snapshot path argument" $PreviousIndex
Require-OrderedText '-AssertActiveInstalled' "interactive diagnostics active-state assertion argument" $PreviousIndex
Require-OrderedText 'Assert-YuneWindowsActiveInstalledSnapshot' "active installed profile assertion before diagnostics export" $PreviousIndex
Require-OrderedText '$DiagnosticsCommand = "tools\export-yune-windows-diagnostics.ps1' "registered-session diagnostics command construction" $PreviousIndex
Require-OrderedText 'Record-Command $DiagnosticsCommand' "registered-session diagnostics command transcript" $PreviousIndex
Require-OrderedText 'Record-CommandSuccess $DiagnosticsCommand' "registered-session diagnostics command completion transcript" $PreviousIndex

Write-Host "Live smoke validates active installed state before registered-session diagnostics export."
