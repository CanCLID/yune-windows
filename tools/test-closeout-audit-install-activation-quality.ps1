param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-install-activation-quality-test"
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

function Read-InstallGateStatus([string]$Name) {
    $JsonPath = Join-Path $OutputDir "$Name.json"
    $MarkdownPath = Join-Path $OutputDir "$Name.md"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null

    $Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    $InstallGate = $Audit.gates | Where-Object { $_.id -eq "fresh-install-registration-activation" } | Select-Object -First 1
    if (-not $InstallGate) {
        throw "audit did not emit fresh-install-registration-activation gate"
    }
    return $InstallGate.status
}

function Update-StateSnapshotCapturedAt([string]$RelativePath, [string]$CapturedAt) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $State = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $State.captured_at = $CapturedAt
    $State | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $Path -Encoding utf8
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
Write-EvidenceFile "m01\installer\result.md" @"
# Install And Smoke Result

Status: passed

Fresh install: completed.
Notepad smoke: completed.
Chromium smoke: completed.
Diagnostics bundle: synthetic.zip.
"@
Write-EvidenceFile "m01\installer\post-install-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": []
}
"@
Write-EvidenceFile "m01\tsf-smoke\notepad-post-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": []
}
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
    throw "audit should reject install/profile evidence without installed files, registration, and active profile proof, got $($InstallGate.status)"
}

Write-Host "Closeout audit rejects weak install/profile activation evidence."

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

Update-StateSnapshotCapturedAt `
    -RelativePath "m01\installer\pre-install-state.json" `
    -CapturedAt "2026-06-25T09:00:03.0000000-07:00"
$OutOfOrderPreInstallStatus = Read-InstallGateStatus "audit-with-pre-install-after-post-install"
if ($OutOfOrderPreInstallStatus -ne "invalid") {
    throw "audit should reject install evidence when pre-install state is captured after post-install state, got $OutOfOrderPreInstallStatus"
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

Update-StateSnapshotCapturedAt `
    -RelativePath "m01\installer\post-install-state.json" `
    -CapturedAt "2026-06-25T09:00:07.0000000-07:00"
$LatePostInstallStatus = Read-InstallGateStatus "audit-with-post-install-after-app-smokes"
if ($LatePostInstallStatus -ne "invalid") {
    throw "audit should reject install evidence when post-install state is captured after app smoke results, got $LatePostInstallStatus"
}

Write-Host "Closeout audit rejects chronologically impossible install/profile state evidence."
