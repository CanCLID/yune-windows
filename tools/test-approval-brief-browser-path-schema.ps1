param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BriefScript = Join-Path $RepoRoot "tools\write-m01-approval-brief.ps1"
if (-not (Test-Path -LiteralPath $BriefScript)) {
    throw "missing approval brief writer: tools\write-m01-approval-brief.ps1"
}

$TempDir = Join-Path $env:TEMP "yune-windows\m01-approval-brief-browser-path-schema-test"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Force $TempDir | Out-Null

$CleanupPlanPath = Join-Path $TempDir "machine-cleanup-plan.json"
$AuditPath = Join-Path $TempDir "audit.json"
$OutputPath = Join-Path $TempDir "approval-brief.md"
$LivePreflightPath = Join-Path $TempDir "live-preflight.json"
$CurrentResiduePath = Join-Path $TempDir "current-residue.json"

[ordered]@{
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
} | ConvertTo-Json -Depth 8 |
    Out-File -LiteralPath $CleanupPlanPath -Encoding utf8

[ordered]@{
    generated_at = "2026-06-25T14:14:19.4882370-07:00"
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 |
    Out-File -LiteralPath $CurrentResiduePath -Encoding utf8

[ordered]@{
    generated_at = "2026-06-25T14:15:19.4882370-07:00"
    status = "incomplete"
    gates = @(
        [ordered]@{
            id = "live-preflight"
            status = "invalid"
            notes = "Preflight evidence is invalid: machine-state residue issues: 1; filesystem leftovers: 1."
        }
    )
} | ConvertTo-Json -Depth 8 |
    Out-File -LiteralPath $AuditPath -Encoding utf8

function Write-LivePreflightBrowserPath([object]$BrowserPath) {
    [ordered]@{
        generated_at = "2026-06-25T14:16:19.4882370-07:00"
        machine_state_changed = $false
        browser_available = $true
        browser_path = $BrowserPath
        ready_for_live_smoke = $false
    } | ConvertTo-Json -Depth 6 |
        Out-File -LiteralPath $LivePreflightPath -Encoding utf8
}

function Invoke-BriefExpectingFailure([string]$CaseName, [string[]]$ExtraArgs = @()) {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
            -CleanupPlanPath $CleanupPlanPath `
            -AuditPath $AuditPath `
            -OutputPath $OutputPath `
            -YuneRoot "C:\Users\laubonghaudoi\Documents\GitHub\yune" `
            -InstallDir "C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme" `
            -CurrentResiduePath $CurrentResiduePath `
            @ExtraArgs 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($ExitCode -eq 0) {
        throw "approval brief writer should reject $CaseName, but it exited 0"
    }
    if (($Output -join "`n") -notmatch "concrete Chromium browser path") {
        throw "approval brief writer rejected $CaseName without naming the browser-path problem: $($Output -join "`n")"
    }
}

Write-LivePreflightBrowserPath "<auto-detect>"
Invoke-BriefExpectingFailure "placeholder live-preflight browser_path"

Write-LivePreflightBrowserPath $true
Invoke-BriefExpectingFailure "non-string live-preflight browser_path"

$MissingLivePreflightBrowserPath = Join-Path $TempDir "missing-live-preflight-browser.exe"
Write-LivePreflightBrowserPath $MissingLivePreflightBrowserPath
Invoke-BriefExpectingFailure "missing live-preflight browser_path"

Write-LivePreflightBrowserPath ""
Invoke-BriefExpectingFailure `
    -CaseName "placeholder explicit BrowserPath" `
    -ExtraArgs @("-BrowserPath", "<auto-detect>")

$MissingBrowserPath = Join-Path $TempDir "missing-browser.exe"
Invoke-BriefExpectingFailure `
    -CaseName "missing explicit BrowserPath" `
    -ExtraArgs @("-BrowserPath", $MissingBrowserPath)

Write-Host "Approval brief rejects non-concrete Chromium browser paths."
