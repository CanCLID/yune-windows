param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-complete-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $OutputDir "evidence"))
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null
Add-Type -AssemblyName System.Drawing

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

function New-TestPngBytes([System.Drawing.Color]$Color) {
    $Bitmap = [System.Drawing.Bitmap]::new(640, 360)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $Stream = [System.IO.MemoryStream]::new()
    try {
        $Graphics.Clear($Color)
        $Bitmap.Save($Stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $Stream.ToArray()
    }
    finally {
        $Stream.Dispose()
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
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
        generated_at = "2026-06-25T09:00:07.0000000-07:00"
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
    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }
    Compress-Archive -Path (Join-Path $SourceDir "*") -DestinationPath $ZipPath -Force
}

function New-ValidPreflightJson([bool]$RequireBrowser) {
    return ([ordered]@{
            generated_at = "2026-06-25T09:00:00.0000000-07:00"
            machine_state_changed = $false
            machine_state_checked = $true
            machine_residue_source = "Get-YuneWindowsMachineResidue"
            machine_state_issues = @()
            filesystem_leftovers = @()
            ready_for_live_smoke = $true
            install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
            install_dir_exists = $false
            server_process_count = 0
            yune_root = $SyntheticYuneRoot
            yune_runtime_path = "$SyntheticYuneRoot\target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
            yune_schema_path = "$SyntheticYuneRoot\apps\yune-web\public\schema"
            browser_path = $SyntheticBrowserPath
            yune_runtime_exists = $true
            yune_schema_exists = $true
            tsf_source_exists = $true
            server_source_exists = $true
            build_script_exists = $true
            is_administrator = $true
            is_sta = $true
            browser_available = $RequireBrowser
        } | ConvertTo-Json -Depth 4)
}

$CandidatePng = New-TestPngBytes ([System.Drawing.Color]::White)
$CommitPng = New-TestPngBytes ([System.Drawing.Color]::LightGray)
$ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))
$SyntheticInstallDir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
$SyntheticYuneRoot = "C:\Users\example\Documents\GitHub\yune"
$SyntheticDiagnosticsOutputDir = Join-Path $EvidenceRoot "m01\settings\registered-session-diagnostics"
$SyntheticBrowserPath = Join-Path $OutputDir "browser\msedge.exe"
New-Item -ItemType Directory -Force (Split-Path -Parent $SyntheticBrowserPath) | Out-Null
"" | Out-File -LiteralPath $SyntheticBrowserPath -Encoding ascii
$SyntheticInstallDirJson = $SyntheticInstallDir.Replace("\", "\\")

Write-EvidenceFile "m01\bootstrap\repo-state.md" "repo state"
Write-EvidenceFile "m01\bootstrap\reference-audit.md" "reference audit"
Write-EvidenceFile "m01\bootstrap\process-model.md" "process model"
Write-EvidenceFile "m01\bootstrap\first-smoke-target.md" "first smoke"
Write-EvidenceFile "m01\yune-host\result.json" '{"status": {"schema_id": "jyut6ping3"}}'
Write-EvidenceFile "m01\tsf-smoke\server-ipc-smoke.md" "shared server IPC returned non-raw Yune candidates"
Write-EvidenceFile "m01\candidate-window\build-preflight.md" "candidate preflight"
Write-EvidenceFile "m01\settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "m01\settings\webview2-spike.md" 'Decision: `defer-settings`'
Write-EvidenceFile "m01\tsf-smoke\machine-state-gates.md" @'
# Machine-State Approval Gates

Pass.

Observed output:

```text
Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs. Cleanup helper also refused before machine residue cleanup. Standalone approved machine-state scripts and the full live sequence also refused blank or approval-brief placeholder approval notes before post-approval context checks or machine-state work.
```

## Covered Scripts

- `tools\install-yune-windows-ime.ps1`
- `tools\uninstall-yune-windows-ime.ps1`
- `tools\clear-yune-windows-machine-residue.ps1`
- `tools\run-notepad-smoke.ps1`
- `tools\run-chromium-smoke.ps1`
- `tools\run-m01-live-smoke.ps1`

The scripts were invoked without `-ApprovedMachineStateChange`; each refused
before registration, uninstall, machine residue cleanup, profile activation,
Notepad automation, Chromium automation, full live-sequence orchestration, or
cleanup could run.

The standalone install, uninstall, machine-residue cleanup, Notepad smoke, and
Chromium smoke scripts were also invoked with `-ApprovedMachineStateChange` but
without `-ApprovalNote`; each refused before elevation checks, TSF
registration, cleanup, profile activation, or app automation could run.

The full live sequence was also invoked with `-ApprovedMachineStateChange` but
without `-ApprovalNote`; it refused before elevated/STA context checks,
command transcript writes, profile-probe build, install, registration, app
automation, or cleanup could run.
'@
Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
Write-EvidenceFile "m01\installer\approval.md" @"
# Live Smoke Approval

Date: 2026-06-25T09:00:00.0000000-07:00

Approval note: User approved elevated live smoke in this session.

Machine state changed before approval evidence: false

Administrator: True

STA: True

Install dir: C:\Users\example\AppData\Local\Yune\WindowsIme

Yune root: C:\Users\example\Documents\GitHub\yune

Browser path: $SyntheticBrowserPath
"@

Write-EvidenceFile "m01\tsf-smoke\notepad-smoke-result.md" @"
# Notepad Smoke

Date: 2026-06-25T09:00:05.5000000-07:00

Status: passed

Observed clipboard text after select-all/copy:

````text
$ExpectedCommit
````

Pass: True
Raw ASCII observed: False
Foreground target verified before typing: True
Active profile verified before typing: True
Input method: Win32 virtual-key typed test input.
Clipboard cleared before typing: True
Clipboard cleared after capture: True
Candidate-display screenshot captured: True
Commit screenshot captured: True
Candidate/commit screenshots distinct: True
Matches expected Yune commit: True
Structural candidate update observed: True
Structural candidate update candidate count positive: True
Structural commit event observed: True
Structural candidate window failure observed: False
Structural event matcher: exact event tokens
Structural new log lines: 3
"@
Write-EvidenceFile "m01\tsf-smoke\notepad-post-state.json" @"
{
  "captured_at": "2026-06-25T09:00:05.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": []
}
"@
Write-EvidenceBytes "m01\tsf-smoke\candidate-display-notepad.png" $CandidatePng
Write-EvidenceBytes "m01\tsf-smoke\notepad-commit.png" $CommitPng

Write-EvidenceFile "m01\tsf-smoke\chromium-smoke-result.md" @"
# Chromium Smoke

Date: 2026-06-25T09:00:06.5000000-07:00

Status: passed

Observed clipboard text after select-all/copy:

````text
$ExpectedCommit
````

Pass: True
Raw ASCII observed: False
Foreground target verified before typing: True
Chromium text-field click verified before typing: True
Chromium textarea focus verified before typing: True
Active profile verified before typing: True
Input method: Win32 virtual-key typed test input.
Clipboard cleared before typing: True
Clipboard cleared after capture: True
Candidate-display screenshot captured: True
Commit screenshot captured: True
Candidate/commit screenshots distinct: True
Matches expected Yune commit: True
Structural candidate update observed: True
Structural candidate update candidate count positive: True
Structural commit event observed: True
Structural candidate window failure observed: False
Structural event matcher: exact event tokens
Structural new log lines: 3
"@
Write-EvidenceFile "m01\tsf-smoke\chromium-post-state.json" @"
{
  "captured_at": "2026-06-25T09:00:06.0000000-07:00",
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": []
}
"@
Write-EvidenceBytes "m01\tsf-smoke\candidate-display-chromium.png" $CandidatePng
Write-EvidenceBytes "m01\tsf-smoke\chromium-commit.png" $CommitPng

Write-EvidenceFile "m01\installer\commands.txt" @"
tools\run-m01-live-smoke.ps1 -PreflightOnly -PreflightPath '$EvidenceRoot\m01\installer\live-preflight.json' -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -BrowserPath '$SyntheticBrowserPath'
PASS tools\run-m01-live-smoke.ps1 -PreflightOnly -PreflightPath '$EvidenceRoot\m01\installer\live-preflight.json' -YuneRoot '$SyntheticYuneRoot' -InstallDir '$SyntheticInstallDir' -BrowserPath '$SyntheticBrowserPath'
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
Write-EvidenceFile "m01\installer\pre-install-state.json" @"
{
  "captured_at": "2026-06-25T09:00:01.0000000-07:00",
  "install_dir": "$SyntheticInstallDirJson",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": [],
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
"@
Write-EvidenceFile "m01\installer\post-install-state.json" @"
{
  "captured_at": "2026-06-25T09:00:02.0000000-07:00",
  "install_dir": "$SyntheticInstallDirJson",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":false}",
  "server_processes": [],
  "machine_registration_checked": true,
  "machine_registration_verified": true,
  "machine_registration_registered": true,
  "machine_registration_required_keys": [
    "Registry::HKEY_CLASSES_ROOT\\CLSID\\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}",
    "Registry::HKEY_CLASSES_ROOT\\CLSID\\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\\InprocServer32",
    "Registry::HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\CTF\\TIP\\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\\LanguageProfile\\0x00000c04\\{3AE69B8D-19B4-4267-8F21-E239666D6632}"
  ],
  "machine_registration_missing_keys": [],
  "machine_registration_registry_check_errors": [],
  "machine_registration_expected_dll_path": "$SyntheticInstallDirJson\\YuneWindowsTSF.dll",
  "machine_registration_dll_path": "$SyntheticInstallDirJson\\YuneWindowsTSF.dll",
  "machine_registration_dll_path_matches": true
}
"@
Write-EvidenceFile "m01\installer\result.md" @"
# Install And Smoke Result

Date: 2026-06-25T09:00:11.0000000-07:00

Status: passed

Fresh install: completed.
Notepad smoke: completed.
Chromium smoke: completed.
Diagnostics bundle:

````text
$SyntheticDiagnosticsOutputDir\synthetic.zip
````
"@
Write-EvidenceFile "m01\settings\diagnostics-pre-state.json" @"
{
  "captured_at": "2026-06-25T09:00:07.0000000-07:00",
  "install_dir": "$SyntheticInstallDirJson",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":true}",
  "server_processes": []
}
"@
Write-DiagnosticsBundle "m01\settings\registered-session-diagnostics\synthetic.zip"
Write-EvidenceFile "m01\installer\cleanup-validation.json" '{"generated_at": "2026-06-25T09:00:09.0000000-07:00", "pass": true, "issues": []}'
Write-EvidenceFile "m01\installer\post-cleanup-state.json" @"
{
  "captured_at": "2026-06-25T09:00:08.0000000-07:00",
  "install_dir": "$SyntheticInstallDirJson",
  "install_dir_exists": false,
  "profile_tool_exists": false,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":false,\"active\":false}",
  "server_processes": [],
  "machine_state_checked": true,
  "machine_state_issues": [],
  "filesystem_leftovers": []
}
"@
Write-EvidenceFile "m01\installer\cleanup-result.md" @'
# Cleanup Result

Date: 2026-06-25T09:00:10.0000000-07:00

Status: passed

Pass: True
'@

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
if ($Audit.status -ne "complete") {
    $GateSummary = ($Audit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
    throw "synthetic complete evidence should close M01 audit, got status=$($Audit.status): $GateSummary"
}

foreach ($Gate in $Audit.gates) {
    if ($Gate.status -ne "complete") {
        throw "synthetic complete evidence should complete gate $($Gate.id), got $($Gate.status)"
    }
}

Write-Host "Closeout audit accepts complete synthetic evidence."
