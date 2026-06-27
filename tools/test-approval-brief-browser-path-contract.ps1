param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BriefScript = Join-Path $RepoRoot "tools\write-p2-win01-approval-brief.ps1"
if (-not (Test-Path -LiteralPath $BriefScript)) {
    throw "missing approval brief writer: tools\write-p2-win01-approval-brief.ps1"
}

$TempDir = Join-Path $env:TEMP "yune-windows\p2-win01-approval-brief-browser-path-test"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$CleanupPlanPath = Join-Path $TempDir "machine-cleanup-plan.json"
$AuditPath = Join-Path $TempDir "audit.json"
$OutputPath = Join-Path $TempDir "approval-brief.md"
$LivePreflightPath = Join-Path $TempDir "live-preflight.json"
$CurrentResiduePath = Join-Path $TempDir "current-residue.json"
$SyntheticBrowserPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

$CleanupPlan = [ordered]@{
    generated_at = "2026-06-25T14:13:35.2880334-07:00"
    machine_state_changed = $false
    machine_state_checked = $true
    install_dir = "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme"
    residue_detector = "Get-YuneWindowsMachineResidue"
    requires_current_session_approval = $true
    blocked_live_preflight = $true
    residue_summary = [ordered]@{
        machine_state_issue_count = 1
        pending_rename_count = 1
        registry_entry_count = 0
        registry_check_failure_count = 0
        filesystem_leftover_count = 1
        affected_path_count = 1
    }
    residue_groups = @(
        [ordered]@{
            affected_path = "C:\Windows\System32\YuneWindows.dll.old.0"
            approval_required = $true
            pending_rename_entries = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
            registry_entries = @()
            registry_check_failures = @()
            machine_state_entries = @()
            filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
        }
    )
} | ConvertTo-Json -Depth 8
$CleanupPlan | Out-File -LiteralPath $CleanupPlanPath -Encoding utf8

$CurrentResidue = [ordered]@{
    generated_at = "2026-06-25T14:14:19.4882370-07:00"
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6
$CurrentResidue | Out-File -LiteralPath $CurrentResiduePath -Encoding utf8

$Audit = [ordered]@{
    generated_at = "2026-06-25T14:15:19.4882370-07:00"
    status = "incomplete"
    gates = @(
        [ordered]@{
            id = "live-preflight"
            status = "invalid"
            notes = "Preflight evidence is invalid: machine-state residue issues: 1; filesystem leftovers: 1."
        }
    )
} | ConvertTo-Json -Depth 8
$Audit | Out-File -LiteralPath $AuditPath -Encoding utf8

$LivePreflight = [ordered]@{
    generated_at = "2026-06-25T14:16:19.4882370-07:00"
    machine_state_changed = $false
    browser_available = $true
    browser_path = $SyntheticBrowserPath
    ready_for_live_smoke = $false
} | ConvertTo-Json -Depth 6
$LivePreflight | Out-File -LiteralPath $LivePreflightPath -Encoding utf8

& powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
    -CleanupPlanPath $CleanupPlanPath `
    -AuditPath $AuditPath `
    -OutputPath $OutputPath `
    -YuneRoot "C:\Users\laubonghaudoi\Documents\GitHub\yune" `
    -InstallDir "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme" `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "approval brief writer failed with exit code $LASTEXITCODE"
}

$Brief = Get-Content -Raw -LiteralPath $OutputPath
$QuotedBrowserPath = "-BrowserPath '$SyntheticBrowserPath'"
foreach ($Expected in @(
        "Chromium browser path: $SyntheticBrowserPath",
        $QuotedBrowserPath,
        "tools\clear-yune-windows-machine-residue.ps1",
        "approval.md records this resolved browser path for transcript matching."
    )) {
    if ($Brief -notmatch [regex]::Escape($Expected)) {
        throw "approval brief is missing resolved browser-path evidence: $Expected"
    }
}

$BrowserPathCommandCount = ([regex]::Matches($Brief, [regex]::Escape($QuotedBrowserPath))).Count
if ($BrowserPathCommandCount -lt 3) {
    throw "approval brief should include the resolved browser path on cleanup, preflight, and live commands, got $BrowserPathCommandCount command entries"
}

Write-Host "Approval brief carries the resolved Chromium browser path into operator commands."
