param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-pre-state-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $OutputDir "evidence"))
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
        generated_at = "2026-06-25T09:00:10.0000000-07:00"
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
        "event=candidate_update sequence=2 buffer_length=7 candidate_count=5",
        "event=commit_text sequence=3 buffer_length=7 candidate_count=5"
    ) | Out-File -LiteralPath (Join-Path $LogDir "tsf-events.log") -Encoding utf8
    "synthetic diagnostics bundle" |
        Out-File -LiteralPath (Join-Path $SourceDir "notes.txt") -Encoding utf8
    Compress-Archive -Path (Join-Path $SourceDir "*") -DestinationPath $ZipPath -Force
}

function Write-DiagnosticsPreState([bool]$Active, [string]$CapturedAt = "2026-06-25T09:00:06.0000000-07:00") {
    $ActiveText = if ($Active) { "true" } else { "false" }
    Write-EvidenceFile "p2-win01-settings\diagnostics-pre-state.json" @"
{
  "captured_at": "$CapturedAt",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":$ActiveText}",
  "server_processes": []
}
"@
}

function Write-AppSmokeResultDates(
    [string]$NotepadDate = "2026-06-25T09:00:05.0000000-07:00",
    [string]$ChromiumDate = "2026-06-25T09:00:05.5000000-07:00"
) {
    Write-EvidenceFile "p2-win01-tsf-smoke\notepad-smoke-result.md" @"
# Notepad Smoke Result

Date: $NotepadDate
"@
    Write-EvidenceFile "p2-win01-tsf-smoke\chromium-smoke-result.md" @"
# Chromium Smoke Result

Date: $ChromiumDate
"@
}

function Read-DiagnosticsGateStatus {
    param(
        [string]$Name
    )

    $JsonPath = Join-Path $OutputDir "$Name.json"
    $MarkdownPath = Join-Path $OutputDir "$Name.md"
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null

    $Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    $DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
    if (-not $DiagnosticsGate) {
        throw "audit did not emit diagnostics-export gate"
    }
    return $DiagnosticsGate.status
}

$SyntheticInstallDir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
$SyntheticYuneRoot = "C:\Users\example\Documents\GitHub\yune"
$SyntheticDiagnosticsOutputDir = Join-Path $EvidenceRoot "p2-win01-settings\registered-session-diagnostics"
$SyntheticBrowserPath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
Write-EvidenceFile "p2-win01-settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "p2-win01-installer\approval.md" @'
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: C:\Program Files\Microsoft\Edge\Application\msedge.exe
'@
Write-EvidenceFile "p2-win01-installer\commands.txt" @"
tools\run-p2-win01-live-smoke.ps1 -PreflightOnly -PreflightPath '$EvidenceRoot\p2-win01-installer\live-preflight.json' -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -BrowserPath '$SyntheticBrowserPath'
PASS tools\run-p2-win01-live-smoke.ps1 -PreflightOnly -PreflightPath '$EvidenceRoot\p2-win01-installer\live-preflight.json' -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -BrowserPath '$SyntheticBrowserPath'
tools\install-yune-windows-ime.ps1 -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\install-yune-windows-ime.ps1 -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
tools\run-notepad-smoke.ps1 -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\run-notepad-smoke.ps1 -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
tools\run-chromium-smoke.ps1 -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -BrowserPath '$SyntheticBrowserPath' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\run-chromium-smoke.ps1 -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -BrowserPath '$SyntheticBrowserPath' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
tools\export-yune-windows-diagnostics.ps1 -OutputDir '$SyntheticDiagnosticsOutputDir' -InstallDir '$SyntheticInstallDir'
PASS tools\export-yune-windows-diagnostics.ps1 -OutputDir '$SyntheticDiagnosticsOutputDir' -InstallDir '$SyntheticInstallDir'
tools\uninstall-yune-windows-ime.ps1 -InstallDir '$SyntheticInstallDir' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\uninstall-yune-windows-ime.ps1 -InstallDir '$SyntheticInstallDir' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
"@
Write-AppSmokeResultDates
Write-DiagnosticsBundle "p2-win01-settings\registered-session-diagnostics\synthetic.zip"
$SyntheticDiagnosticsBundle = Join-Path $SyntheticDiagnosticsOutputDir "synthetic.zip"
Write-EvidenceFile "p2-win01-installer\result.md" @"
# Install And Smoke Result

Date: 2026-06-25T09:00:00.0000000-07:00

Status: passed

Fresh install: completed.
Notepad smoke: completed.
Chromium smoke: completed.
Diagnostics bundle:

````text
$SyntheticDiagnosticsBundle
````
"@

$MissingStatus = Read-DiagnosticsGateStatus "missing-pre-state"
if ($MissingStatus -ne "invalid") {
    throw "audit should reject diagnostics export without diagnostics-pre-state.json, got $MissingStatus"
}

Write-DiagnosticsPreState -Active $false
$InactiveStatus = Read-DiagnosticsGateStatus "inactive-pre-state"
if ($InactiveStatus -ne "invalid") {
    throw "audit should reject diagnostics export without active profile pre-state, got $InactiveStatus"
}

Write-DiagnosticsPreState -Active $true
$ActiveStatus = Read-DiagnosticsGateStatus "active-pre-state"
if ($ActiveStatus -ne "complete") {
    throw "audit should accept diagnostics export with active installed pre-state, got $ActiveStatus"
}

Write-DiagnosticsPreState -Active $true -CapturedAt "2026-06-25T09:00:04.0000000-07:00"
$PreSmokePreStateStatus = Read-DiagnosticsGateStatus "pre-smoke-pre-state"
if ($PreSmokePreStateStatus -ne "invalid") {
    throw "audit should reject diagnostics pre-state captured before app smoke result evidence, got $PreSmokePreStateStatus"
}

Write-DiagnosticsPreState -Active $true -CapturedAt "2026-06-25T09:00:11.0000000-07:00"
$PostExportPreStateStatus = Read-DiagnosticsGateStatus "post-export-pre-state"
if ($PostExportPreStateStatus -ne "invalid") {
    throw "audit should reject diagnostics pre-state captured after diagnostics bundle generation, got $PostExportPreStateStatus"
}

Write-Host "Closeout audit requires active installed diagnostics pre-state evidence."
