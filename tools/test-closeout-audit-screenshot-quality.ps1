param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-screenshot-quality-test"
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

function Write-EvidenceBytes([string]$RelativePath, [byte[]]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllBytes($Path, $Content)
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
Write-EvidenceFile "m01\tsf-smoke\notepad-smoke-result.md" @"
# Notepad Smoke

Pass: True
Raw ASCII observed: False
"@
Write-EvidenceFile "m01\tsf-smoke\chromium-smoke-result.md" @"
# Chromium Smoke

Pass: True
Raw ASCII observed: False
"@

$TinyPlaceholder = [byte[]](0x89, 0x50, 0x4e, 0x47)
foreach ($Screenshot in @(
    "m01\tsf-smoke\candidate-display-notepad.png",
    "m01\tsf-smoke\notepad-commit.png",
    "m01\tsf-smoke\candidate-display-chromium.png",
    "m01\tsf-smoke\chromium-commit.png"
)) {
    Write-EvidenceBytes $Screenshot $TinyPlaceholder
}

Write-EvidenceFile "m01\installer\commands.txt" @"
tools\install-yune-windows-ime.ps1 -ApprovedMachineStateChange
tools\run-notepad-smoke.ps1 -ApprovedMachineStateChange
tools\run-chromium-smoke.ps1 -ApprovedMachineStateChange
tools\uninstall-yune-windows-ime.ps1 -ApprovedMachineStateChange
"@
Write-EvidenceFile "m01\installer\post-install-state.json" '{"profile_state_verified": true}'
Write-EvidenceFile "m01\installer\result.md" @"
# Install And Smoke Result

Status: passed
Fresh install: completed.
Notepad smoke: completed.
Chromium smoke: completed.
Diagnostics bundle: synthetic.zip.
"@

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @(
    "tsf-notepad-smoke",
    "chromium-text-field-smoke",
    "candidate-display-live"
)) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject placeholder screenshot evidence for $GateId, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects placeholder screenshot evidence."
