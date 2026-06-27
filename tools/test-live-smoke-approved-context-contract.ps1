param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorScript = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Require-ApprovedLiveSmokeContext',
        'Test-IsAdministrator',
        'ApartmentState',
        'elevated STA PowerShell session'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing approved-context guard pattern: $Required"
    }
}

$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorScript
$Pattern = 'Require-ApprovedMachineStateChange(?s:.*?)Require-LiveSmokeApprovalNote -ApprovalNote \$ApprovalNote(?s:.*?)Require-ApprovedLiveSmokeContext(?s:.*?)\$RepoRoot\s*=\s*Resolve-Path(?s:.*?)\$CurrentStage\s*=\s*"profile-probe-build"'
if ($OrchestratorSource -notmatch $Pattern) {
    throw "run-p2-win01-live-smoke.ps1 must reject blank approval notes, then verify elevated STA context before profile-probe build or command recording."
}

Write-Host "Approved live-smoke sequence verifies approval note and elevated STA context before machine-state work."
