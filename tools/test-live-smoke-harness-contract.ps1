param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath

function Require-File([string]$RelativePath) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing required live-smoke harness file: $RelativePath"
    }
    return $Path
}

function Require-Text([string]$RelativePath, [string]$Pattern, [string]$Reason) {
    $Path = Require-File $RelativePath
    if (-not (Select-String -Path $Path -Pattern $Pattern -Quiet)) {
        throw "$RelativePath is missing $Reason"
    }
}

Require-File "tools\live-smoke-support.ps1" | Out-Null

foreach ($Smoke in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    Require-Text $Smoke "live-smoke-support.ps1" "shared live-smoke support"
    Require-Text $Smoke "Capture-DesktopScreenshot" "candidate-display screenshot capture"
    Require-Text $Smoke '\$TypedInput = "ngohaig"' "approved typed input value"
    Require-Text $Smoke 'Send-YuneWindowsAsciiText -Text \$TypedInput' "composition before commit"
    Require-Text $Smoke 'Send-YuneWindowsVirtualKey -VirtualKey 0x20' "separate commit key after screenshot"
    Require-Text $Smoke "Input method: Win32 virtual-key typed test input\." "typed-input result evidence"
    Require-Text $Smoke "candidate-display.*\.png" "candidate-display screenshot path"
    Require-Text $Smoke "pre-state.json" "pre-state snapshot"
    Require-Text $Smoke "post-state.json" "post-state snapshot"
}

$Orchestrator = "tools\run-p2-win01-live-smoke.ps1"
Require-Text $Orchestrator "ApprovedMachineStateChange" "approval gate"
Require-Text $Orchestrator "PreflightOnly" "non-mutating preflight mode"
Require-Text $Orchestrator "Write-P2Win01PreflightReport" "shared preflight report"
Require-Text $Orchestrator "install-yune-windows-ime.ps1" "install step"
Require-Text $Orchestrator "run-notepad-smoke.ps1" "Notepad smoke step"
Require-Text $Orchestrator "run-chromium-smoke.ps1" "Chromium smoke step"
Require-Text $Orchestrator "export-yune-windows-diagnostics.ps1" "diagnostics export step"
Require-Text $Orchestrator "uninstall-yune-windows-ime.ps1" "uninstall step"
if ($OrchestratorSource -match 'Record-Command\s+"tools\\run-chromium-smoke\.ps1 -ApprovedMachineStateChange"') {
    throw "tools\run-p2-win01-live-smoke.ps1 records a stale Chromium command that is not the command it runs"
}
Require-Text $Orchestrator 'install-yune-windows-ime\.ps1.*-InstallDir.*Format-CommandValue \$InstallDir' "install transcript with exact install directory"
Require-Text $Orchestrator 'run-notepad-smoke\.ps1.*-InstallDir.*Format-CommandValue \$InstallDir' "Notepad transcript with exact install directory"
Require-Text $Orchestrator 'run-chromium-smoke\.ps1.*-InstallDir.*Format-CommandValue \$InstallDir' "Chromium transcript with exact install directory"
Require-Text $Orchestrator 'export-yune-windows-diagnostics\.ps1.*-InstallDir.*Format-CommandValue \$InstallDir' "diagnostics transcript with exact install directory"
Require-Text $Orchestrator 'uninstall-yune-windows-ime\.ps1.*-InstallDir.*Format-CommandValue \$InstallDir' "uninstall transcript with exact install directory"
Require-Text $Orchestrator "audit-p2-win01-closeout.ps1" "closeout audit regeneration"
Require-Text $Orchestrator "commands.txt" "command transcript"
Require-Text $Orchestrator "result.md" "installer result evidence"
Require-Text $Orchestrator 'Status "failed"' "failed-stage result evidence"
Require-Text $Orchestrator "Failure stage:" "failed-stage label"
Require-Text $Orchestrator "cleanup-result.md" "cleanup result evidence"
Require-Text $Orchestrator "cleanup-validation.json" "machine-readable cleanup validation"
Require-Text $Orchestrator "Test-YuneWindowsCleanupState" "cleanup validator"
Require-Text $Orchestrator "ProfileProbePath" "external profile-state probe"
Require-Text $Orchestrator "RequireProfileState" "required post-cleanup TSF profile verification"

Require-Text "tools\install-yune-windows-ime.ps1" "PreflightOnly" "install preflight mode"
Require-Text "tools\live-smoke-support.ps1" "New-P2Win01PreflightReport" "shared preflight function"
Require-Text "tools\live-smoke-support.ps1" "Test-YuneWindowsCleanupState" "shared cleanup validator"
Require-Text "tools\live-smoke-support.ps1" "ProfileToolPath" "external profile-state probe support"

Write-Host "Live smoke harness contract is ready for approval-gated execution."
