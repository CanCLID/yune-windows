param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
if (-not (Test-Path -LiteralPath $OrchestratorPath)) {
    throw "missing live smoke orchestrator: $OrchestratorPath"
}

$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
$Lines = @($OrchestratorSource -split "\r?\n")

function Find-SnapshotBlock([string]$SnapshotName) {
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -notmatch 'Write-YuneWindowsStateSnapshot') {
            continue
        }
        $WindowEnd = [Math]::Min($Lines.Count - 1, $Index + 8)
        $Block = ($Lines[$Index..$WindowEnd] -join "`n")
        if ($Block -match [regex]::Escape($SnapshotName)) {
            return $Block
        }
        if ($SnapshotName -eq "pre-install-state.json" -and
            $Block -match '-Path\s+\$PreInstallStatePath') {
            return $Block
        }
        if ($SnapshotName -eq "post-cleanup-state.json" -and
            $Block -match '-Path\s+\$PostCleanupStatePath') {
            return $Block
        }
    }
    return $null
}

function Find-SnapshotCallLine([string]$SnapshotName) {
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -notmatch 'Write-YuneWindowsStateSnapshot') {
            continue
        }
        $WindowEnd = [Math]::Min($Lines.Count - 1, $Index + 8)
        $Block = ($Lines[$Index..$WindowEnd] -join "`n")
        if ($Block -match [regex]::Escape($SnapshotName)) {
            return $Index
        }
        if ($SnapshotName -eq "pre-install-state.json" -and
            $Block -match '-Path\s+\$PreInstallStatePath') {
            return $Index
        }
        if ($SnapshotName -eq "post-cleanup-state.json" -and
            $Block -match '-Path\s+\$PostCleanupStatePath') {
            return $Index
        }
    }
    return -1
}

if ($OrchestratorSource -notmatch '\$PreInstallStatePath\s*=\s*Join-Path\s+\$InstallerEvidence\s+"pre-install-state\.json"') {
    throw "live smoke orchestrator does not define pre-install-state.json evidence path"
}
if ($OrchestratorSource -notmatch '\$PostCleanupStatePath\s*=\s*Join-Path\s+\$InstallerEvidence\s+"post-cleanup-state\.json"') {
    throw "live smoke orchestrator does not define post-cleanup-state.json evidence path"
}

$PreInstallBlock = Find-SnapshotBlock "pre-install-state.json"
if ($null -eq $PreInstallBlock) {
    throw "live smoke orchestrator does not capture pre-install-state.json"
}
if ($PreInstallBlock -notmatch '-ProfileToolPath\s+\$ProfileProbePath') {
    throw "pre-install state snapshot must use the external profile probe to record TSF profile state before registration"
}

$PreInstallBlockLine = -1
$BuildProbeLine = -1
for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    if ($BuildProbeLine -lt 0 -and
        $Lines[$Index] -match 'build-tsf-shell\.ps1') {
        $BuildProbeLine = $Index
    }
}
$PreInstallBlockLine = Find-SnapshotCallLine "pre-install-state.json"
if ($BuildProbeLine -lt 0) {
    throw "live smoke orchestrator must build the profile probe before pre-install state capture"
}
if ($BuildProbeLine -ge $PreInstallBlockLine) {
    throw "profile probe build must occur before pre-install state capture"
}

$PostCleanupBlock = Find-SnapshotBlock "post-cleanup-state.json"
if ($null -eq $PostCleanupBlock) {
    throw "live smoke orchestrator does not capture post-cleanup-state.json"
}
if ($PostCleanupBlock -notmatch '-ProfileToolPath\s+\$ProfileProbePath') {
    throw "post-cleanup state snapshot must keep using the external profile probe"
}

Write-Host "Live smoke pre-install and post-cleanup snapshots use the external profile probe."
