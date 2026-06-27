param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$CleanupPath = Join-Path $RepoRoot "tools\clear-yune-windows-machine-residue.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportPath

function Get-FunctionBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$FunctionName,
        [string]$NextFunctionName
    )

    $Start = $Source.IndexOf("function $FunctionName")
    if ($Start -lt 0) {
        throw "tools\live-smoke-support.ps1 is missing $FunctionName."
    }
    $End = $Source.Length
    if ($NextFunctionName) {
        $Next = $Source.IndexOf("function $NextFunctionName", $Start + 1)
        if ($Next -gt $Start) {
            $End = $Next
        }
    }
    return $Source.Substring($Start, $End - $Start)
}

$GetSnapshotBlock = Get-FunctionBlock `
    -Source $SupportSource `
    -FunctionName "Get-YuneWindowsStateSnapshot" `
    -NextFunctionName "Write-YuneWindowsStateSnapshot"
$WriteSnapshotBlock = Get-FunctionBlock `
    -Source $SupportSource `
    -FunctionName "Write-YuneWindowsStateSnapshot" `
    -NextFunctionName "Assert-YuneWindowsActiveInstalledSnapshot"

foreach ($RequiredText in @(
        '[string]$ApprovalNote = ""',
        '[switch]$IncludeMachineResidue',
        'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote',
        'Get-YuneWindowsMachineResidue -InstallDir $InstallRoot')) {
    if (-not $GetSnapshotBlock.Contains($RequiredText)) {
        throw "Get-YuneWindowsStateSnapshot must contain: $RequiredText"
    }
}

$IncludeIndex = $GetSnapshotBlock.IndexOf('if ($IncludeMachineResidue)')
$ApprovalIndex = $GetSnapshotBlock.IndexOf('Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote', $IncludeIndex)
$DetectorIndex = $GetSnapshotBlock.IndexOf('Get-YuneWindowsMachineResidue -InstallDir $InstallRoot', $IncludeIndex)
if ($IncludeIndex -lt 0 -or $ApprovalIndex -lt 0 -or $DetectorIndex -lt 0) {
    throw "Get-YuneWindowsStateSnapshot must guard the IncludeMachineResidue branch before reading residue."
}
if ($ApprovalIndex -gt $DetectorIndex) {
    throw "Get-YuneWindowsStateSnapshot must require an approval note before reading machine residue."
}

foreach ($RequiredText in @(
        '[string]$ApprovalNote = ""',
        '-ApprovalNote $ApprovalNote')) {
    if (-not $WriteSnapshotBlock.Contains($RequiredText)) {
        throw "Write-YuneWindowsStateSnapshot must contain: $RequiredText"
    }
}

function Assert-IncludeResidueSnapshotsPassApprovalNote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Lines = Get-Content -LiteralPath $Path
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -notmatch 'Write-YuneWindowsStateSnapshot') {
            continue
        }

        $Block = [System.Collections.Generic.List[string]]::new()
        $Cursor = $Index
        $Block.Add($Lines[$Cursor]) | Out-Null
        while ($Cursor -lt ($Lines.Count - 1) -and $Lines[$Cursor].TrimEnd().EndsWith('`')) {
            $Cursor++
            $Block.Add($Lines[$Cursor]) | Out-Null
        }

        $BlockText = ($Block -join "`n")
        if ($BlockText -match '-IncludeMachineResidue' -and
            $BlockText -notmatch '-ApprovalNote\s+\$ApprovalNote') {
            throw "$Path writes a machine-residue state snapshot without passing -ApprovalNote."
        }
    }
}

Assert-IncludeResidueSnapshotsPassApprovalNote -Path $OrchestratorPath
Assert-IncludeResidueSnapshotsPassApprovalNote -Path $CleanupPath

. $SupportPath

$script:MachineResidueDetectorCalled = $false
function Get-YuneWindowsMachineResidue {
    $script:MachineResidueDetectorCalled = $true
    throw "machine residue detector executed before approval guard"
}

$TempRoot = Join-Path $env:TEMP "yune-windows\p2-win01-state-snapshot-approval-note"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $TempRoot | Out-Null
$SnapshotPath = Join-Path $TempRoot "snapshot.json"

$GetFailedWithApprovalNoteError = $false
try {
    Get-YuneWindowsStateSnapshot `
        -InstallDir (Join-Path $TempRoot "missing-install") `
        -IncludeMachineResidue | Out-Null
}
catch {
    $GetFailedWithApprovalNoteError = $_.Exception.Message -match "Approved live smoke requires -ApprovalNote"
}
if (-not $GetFailedWithApprovalNoteError) {
    throw "Get-YuneWindowsStateSnapshot -IncludeMachineResidue must fail without -ApprovalNote before residue detection."
}
if ($script:MachineResidueDetectorCalled) {
    throw "Get-YuneWindowsStateSnapshot called the machine residue detector before approval-note validation."
}

$WriteFailedWithApprovalNoteError = $false
try {
    Write-YuneWindowsStateSnapshot `
        -Path $SnapshotPath `
        -InstallDir (Join-Path $TempRoot "missing-install") `
        -IncludeMachineResidue
}
catch {
    $WriteFailedWithApprovalNoteError = $_.Exception.Message -match "Approved live smoke requires -ApprovalNote"
}
if (-not $WriteFailedWithApprovalNoteError) {
    throw "Write-YuneWindowsStateSnapshot -IncludeMachineResidue must fail without -ApprovalNote before residue detection."
}
if ($script:MachineResidueDetectorCalled) {
    throw "Write-YuneWindowsStateSnapshot called the machine residue detector before approval-note validation."
}
if (Test-Path -LiteralPath $SnapshotPath) {
    throw "Write-YuneWindowsStateSnapshot wrote machine-residue output without approval-note validation."
}

Write-Host "State snapshots require approval notes before machine-residue checks."
