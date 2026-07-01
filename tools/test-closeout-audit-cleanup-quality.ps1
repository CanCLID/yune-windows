param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-cleanup-quality-test"
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

Write-EvidenceFile "m01\bootstrap\repo-state.md" "repo state"
Write-EvidenceFile "m01\bootstrap\reference-audit.md" "reference audit"
Write-EvidenceFile "m01\bootstrap\process-model.md" "process model"
Write-EvidenceFile "m01\bootstrap\first-smoke-target.md" "first smoke"
Write-EvidenceFile "m01\yune-host\result.json" '{"status": {"schema_id": "jyut6ping3"}}'
Write-EvidenceFile "m01\tsf-smoke\server-ipc-smoke.md" "server ipc smoke"
Write-EvidenceFile "m01\candidate-window\build-preflight.md" "candidate preflight"
Write-EvidenceFile "m01\settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "m01\settings\webview2-spike.md" 'Decision: `defer-settings`'
Write-EvidenceFile "m01\tsf-smoke\machine-state-gates.md" "approval gates"
Write-EvidenceFile "m01\installer\live-preflight.json" '{"machine_state_changed": false}'
Write-EvidenceFile "m01\installer\install-preflight.json" '{"machine_state_changed": false}'
Write-EvidenceFile "m01\installer\commands.txt" @"
tools\install-yune-windows-ime.ps1 -ApprovedMachineStateChange
tools\run-notepad-smoke.ps1 -ApprovedMachineStateChange
tools\run-chromium-smoke.ps1 -ApprovedMachineStateChange
tools\uninstall-yune-windows-ime.ps1 -ApprovedMachineStateChange
"@
Write-EvidenceFile "m01\installer\cleanup-result.md" "Pass: True"
Write-EvidenceFile "m01\installer\cleanup-validation.json" '{"pass": true}'
Write-EvidenceFile "m01\installer\post-cleanup-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme",
  "install_dir_exists": true,
  "profile_state_verified": false,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": [
    {
      "Path": "C:\\Users\\example\\AppData\\Local\\Yune\\WindowsIme\\YuneWindowsServer.exe"
    }
  ]
}
"@

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$CleanupGate = $Audit.gates | Where-Object { $_.id -eq "uninstall-cleanup" } | Select-Object -First 1
if (-not $CleanupGate) {
    throw "audit did not emit uninstall-cleanup gate"
}
if ($CleanupGate.status -ne "invalid") {
    throw "audit should reject placeholder cleanup evidence with residual state, got $($CleanupGate.status)"
}

Write-Host "Closeout audit rejects placeholder cleanup evidence with residual state."
