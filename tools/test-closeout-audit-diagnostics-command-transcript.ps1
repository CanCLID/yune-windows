param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-command-test"
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

function Write-DiagnosticsBundle([string]$RelativePath) {
    $ZipPath = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $ZipPath) | Out-Null
    $SourceDir = Join-Path $OutputDir "diagnostics-source"
    if (Test-Path -LiteralPath $SourceDir) {
        Remove-Item -LiteralPath $SourceDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force $SourceDir | Out-Null
    [ordered]@{
        product = "Yune Windows"
        generated_at = "2026-06-25T09:00:00.0000000-07:00"
        machine_state = [ordered]@{
            registry_collected = $false
        }
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
        sensitive_context = [ordered]@{
            typed_content_logs = $false
            ai_staging = $false
        }
    } | ConvertTo-Json -Depth 4 |
        Out-File -LiteralPath (Join-Path $SourceDir "manifest.json") -Encoding utf8
    $LogDir = Join-Path $SourceDir "logs"
    New-Item -ItemType Directory -Force $LogDir | Out-Null
    @(
        "event=key_down sequence=1 buffer_length=1 candidate_count=0",
        "event=candidate_update sequence=2 buffer_length=7 candidate_count=5"
    ) | Out-File -LiteralPath (Join-Path $LogDir "tsf-events.log") -Encoding utf8
    "synthetic diagnostics bundle" |
        Out-File -LiteralPath (Join-Path $SourceDir "notes.txt") -Encoding utf8
    Compress-Archive -Path (Join-Path $SourceDir "*") -DestinationPath $ZipPath -Force
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
Write-DiagnosticsBundle "p2-win01-settings\registered-session-diagnostics\synthetic.zip"

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
if (-not $DiagnosticsGate) {
    throw "audit did not emit diagnostics-export gate"
}
if ($DiagnosticsGate.status -ne "invalid") {
    throw "audit should reject registered-session diagnostics without an export command transcript, got $($DiagnosticsGate.status)"
}

Write-Host "Closeout audit rejects diagnostics bundles without export command transcript."
