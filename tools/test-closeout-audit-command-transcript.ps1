param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-command-test"
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
Write-EvidenceFile "m01\yune-host\result.json" '{"status":{"schema_id":"jyut6ping3"}}'
Write-EvidenceFile "m01\tsf-smoke\server-ipc-smoke.md" "server ipc smoke"
Write-EvidenceFile "m01\candidate-window\build-preflight.md" "candidate preflight"
Write-EvidenceFile "m01\settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "m01\settings\webview2-spike.md" 'Decision: `defer-settings`'
Write-EvidenceFile "m01\tsf-smoke\machine-state-gates.md" "approval gates"
Write-EvidenceFile "m01\installer\live-preflight.json" '{"machine_state_changed":false}'
Write-EvidenceFile "m01\installer\install-preflight.json" '{"machine_state_changed":false}'
Write-EvidenceFile "m01\installer\post-install-state.json" '{"profile_state_verified":true}'
Write-EvidenceFile "m01\installer\result.md" @"
# Install And Smoke Result

Fresh install: attempted through tools.
Notepad smoke: see notepad result.
Chromium smoke: see chromium result.
Diagnostics bundle: synthetic.zip
"@
Write-EvidenceFile "m01\installer\commands.txt" @"
tools\install-yune-windows-ime.ps1
tools\run-notepad-smoke.ps1
tools\run-chromium-smoke.ps1
tools\uninstall-yune-windows-ime.ps1
"@

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InstallGate = $Audit.gates | Where-Object { $_.id -eq "fresh-install-registration-activation" } | Select-Object -First 1
if (-not $InstallGate) {
    throw "audit did not emit fresh-install-registration-activation gate"
}
if ($InstallGate.status -ne "invalid") {
    throw "audit should reject command transcript without approval switches, got $($InstallGate.status)"
}

$CompleteFixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $CompleteFixtureDir | Out-Null

$CompleteEvidenceRoot = Join-Path $CompleteFixtureDir "evidence"
$CompleteCommandsPath = Join-Path $CompleteEvidenceRoot "m01\installer\commands.txt"
if (-not (Test-Path -LiteralPath $CompleteCommandsPath)) {
    throw "complete synthetic fixture did not write commands.txt"
}
(Get-Content -LiteralPath $CompleteCommandsPath) |
    ForEach-Object { $_ -replace "\s+-ApprovalNote\s+'[^']+'", "" } |
    Out-File -LiteralPath $CompleteCommandsPath -Encoding utf8

$ApprovalNoteJsonPath = Join-Path $OutputDir "audit-missing-approval-note.json"
$ApprovalNoteMarkdownPath = Join-Path $OutputDir "audit-missing-approval-note.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $CompleteEvidenceRoot `
    -JsonPath $ApprovalNoteJsonPath `
    -MarkdownPath $ApprovalNoteMarkdownPath | Out-Null

$ApprovalNoteAudit = Get-Content -Raw -LiteralPath $ApprovalNoteJsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $ApprovalNoteAudit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId for missing transcript approval notes"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when live command transcripts omit -ApprovalNote, got $($Gate.status)"
    }
}
if ($ApprovalNoteAudit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts omit -ApprovalNote"
}

$EmptyApprovalNoteFixtureDir = Join-Path $OutputDir "empty-approval-note-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $EmptyApprovalNoteFixtureDir | Out-Null

$EmptyApprovalNoteEvidenceRoot = Join-Path $EmptyApprovalNoteFixtureDir "evidence"
$EmptyApprovalNoteCommandsPath = Join-Path $EmptyApprovalNoteEvidenceRoot "m01\installer\commands.txt"
if (-not (Test-Path -LiteralPath $EmptyApprovalNoteCommandsPath)) {
    throw "empty approval-note fixture did not write commands.txt"
}
(Get-Content -LiteralPath $EmptyApprovalNoteCommandsPath) |
    ForEach-Object { $_ -replace "\s+-ApprovalNote\s+'[^']+'", " -ApprovalNote ''" } |
    Out-File -LiteralPath $EmptyApprovalNoteCommandsPath -Encoding utf8

$EmptyApprovalNoteJsonPath = Join-Path $OutputDir "audit-empty-approval-note.json"
$EmptyApprovalNoteMarkdownPath = Join-Path $OutputDir "audit-empty-approval-note.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EmptyApprovalNoteEvidenceRoot `
    -JsonPath $EmptyApprovalNoteJsonPath `
    -MarkdownPath $EmptyApprovalNoteMarkdownPath | Out-Null

$EmptyApprovalNoteAudit = Get-Content -Raw -LiteralPath $EmptyApprovalNoteJsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $EmptyApprovalNoteAudit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId for empty transcript approval notes"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when live command transcripts use empty -ApprovalNote values, got $($Gate.status)"
    }
}
if ($EmptyApprovalNoteAudit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts use empty -ApprovalNote values"
}

$MismatchedApprovalNoteFixtureDir = Join-Path $OutputDir "mismatched-approval-note-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $MismatchedApprovalNoteFixtureDir | Out-Null

$MismatchedApprovalNoteEvidenceRoot = Join-Path $MismatchedApprovalNoteFixtureDir "evidence"
$MismatchedApprovalNoteCommandsPath = Join-Path $MismatchedApprovalNoteEvidenceRoot "m01\installer\commands.txt"
if (-not (Test-Path -LiteralPath $MismatchedApprovalNoteCommandsPath)) {
    throw "mismatched approval-note fixture did not write commands.txt"
}
(Get-Content -LiteralPath $MismatchedApprovalNoteCommandsPath) |
    ForEach-Object {
        $_ -replace "\s+-ApprovalNote\s+'[^']+'", " -ApprovalNote 'Different approval note from transcript.'"
    } |
    Out-File -LiteralPath $MismatchedApprovalNoteCommandsPath -Encoding utf8

$MismatchedApprovalNoteJsonPath = Join-Path $OutputDir "audit-mismatched-approval-note.json"
$MismatchedApprovalNoteMarkdownPath = Join-Path $OutputDir "audit-mismatched-approval-note.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $MismatchedApprovalNoteEvidenceRoot `
    -JsonPath $MismatchedApprovalNoteJsonPath `
    -MarkdownPath $MismatchedApprovalNoteMarkdownPath | Out-Null

$MismatchedApprovalNoteAudit = Get-Content -Raw -LiteralPath $MismatchedApprovalNoteJsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $MismatchedApprovalNoteAudit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId for mismatched transcript approval notes"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when live command transcripts use a different -ApprovalNote value than approval.md, got $($Gate.status)"
    }
}
if ($MismatchedApprovalNoteAudit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts use a different -ApprovalNote value than approval.md"
}

Write-Host "Closeout audit rejects live command transcripts without approval switches or matching non-empty approval notes."
