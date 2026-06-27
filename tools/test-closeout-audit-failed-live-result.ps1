param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-failed-live-result-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null

function Write-EvidenceFile([string]$RelativePath, [string]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Content | Out-File -LiteralPath $Path -Encoding utf8
}

Write-EvidenceFile "p2-win01-bootstrap\repo-state.md" "repo state"
Write-EvidenceFile "p2-win01-bootstrap\reference-audit.md" "reference audit"
Write-EvidenceFile "p2-win01-bootstrap\process-model.md" "process model"
Write-EvidenceFile "p2-win01-bootstrap\first-smoke-target.md" "first smoke"
Write-EvidenceFile "p2-win01-yune-host\result.json" '{"status": {"schema_id": "jyut6ping3"}}'
Write-EvidenceFile "p2-win01-tsf-smoke\server-ipc-smoke.md" "server ipc smoke"
Write-EvidenceFile "p2-win01-candidate-window\build-preflight.md" "candidate preflight"
Write-EvidenceFile "p2-win01-settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "p2-win01-settings\webview2-spike.md" 'Decision: `defer-settings`'
Write-EvidenceFile "p2-win01-tsf-smoke\machine-state-gates.md" "approval gates"
Write-EvidenceFile "p2-win01-installer\live-preflight.json" '{"machine_state_changed": false}'
Write-EvidenceFile "p2-win01-installer\install-preflight.json" '{"machine_state_changed": false}'
Write-EvidenceFile "p2-win01-installer\commands.txt" @"
tools\install-yune-windows-ime.ps1 -ApprovedMachineStateChange
tools\run-notepad-smoke.ps1 -ApprovedMachineStateChange
tools\run-chromium-smoke.ps1 -ApprovedMachineStateChange
tools\uninstall-yune-windows-ime.ps1 -ApprovedMachineStateChange
"@
Write-EvidenceFile "p2-win01-installer\post-install-state.json" '{"profile_state_verified": true}'
Write-EvidenceFile "p2-win01-installer\result.md" @"
# Install And Smoke Result

Status: failed
Failure stage: chromium-smoke

Fresh install: completed.
Notepad smoke: completed.
Chromium smoke: failed.
Diagnostics bundle: not captured.
"@

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InstallGate = $Audit.gates | Where-Object { $_.id -eq "fresh-install-registration-activation" } | Select-Object -First 1
if (-not $InstallGate) {
    throw "audit did not emit fresh-install-registration-activation gate"
}
if ($InstallGate.status -ne "invalid") {
    throw "audit should reject failed live result for install/profile activation, got $($InstallGate.status)"
}

Write-Host "Closeout audit rejects failed live install/profile result evidence."
