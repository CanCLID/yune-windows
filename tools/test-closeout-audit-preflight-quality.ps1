param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-preflight-quality-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null
$ExistingBrowserPath = Join-Path $OutputDir "browser\msedge.exe"
New-Item -ItemType Directory -Force (Split-Path -Parent $ExistingBrowserPath) | Out-Null
"" | Out-File -LiteralPath $ExistingBrowserPath -Encoding ascii
$MissingBrowserPath = Join-Path $OutputDir "missing-browser\msedge.exe"

function Write-EvidenceFile([string]$RelativePath, [string]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Content | Out-File -LiteralPath $Path -Encoding utf8
}

function Invoke-Audit {
    $JsonPath = Join-Path $OutputDir "audit.json"
    $MarkdownPath = Join-Path $OutputDir "audit.md"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Get-LivePreflightGate {
    $Audit = Invoke-Audit
    $Gate = $Audit.gates | Where-Object { $_.id -eq "live-preflight" } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit live-preflight gate"
    }
    return $Gate
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
            yune_root = "C:\Users\example\Documents\GitHub\yune"
            yune_runtime_path = "C:\Users\example\Documents\GitHub\yune\target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
            yune_schema_path = "C:\Users\example\Documents\GitHub\yune\apps\yune-web\public\schema"
            browser_path = $ExistingBrowserPath
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

Write-EvidenceFile "m01\installer\live-preflight.json" "{}"
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$PlaceholderGate = Get-LivePreflightGate
if ($PlaceholderGate.status -ne "invalid") {
    throw "placeholder live preflight JSON should be invalid, got $($PlaceholderGate.status)"
}

Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$MissingBrowserPreflightPath = Join-Path $EvidenceRoot "m01\installer\live-preflight.json"
$MissingBrowserPreflight = Get-Content -Raw -LiteralPath $MissingBrowserPreflightPath | ConvertFrom-Json
$MissingBrowserPreflight.browser_path = $MissingBrowserPath
$MissingBrowserPreflight | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $MissingBrowserPreflightPath -Encoding utf8
$MissingBrowserGate = Get-LivePreflightGate
if ($MissingBrowserGate.status -ne "invalid") {
    throw "missing-browser live preflight JSON should be invalid, got $($MissingBrowserGate.status)"
}

Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (@{
        machine_state_changed = $false
        machine_state_checked = $true
        machine_state_issues = @()
        filesystem_leftovers = @()
        ready_for_live_smoke = $false
        install_dir_exists = $true
        server_process_count = 0
        yune_runtime_exists = $true
        yune_schema_exists = $true
        tsf_source_exists = $true
        server_source_exists = $true
        build_script_exists = $true
        is_administrator = $false
    } | ConvertTo-Json -Depth 4)
$DirtyInstallGate = Get-LivePreflightGate
if ($DirtyInstallGate.status -ne "invalid") {
    throw "dirty install-target preflight JSON should be invalid, got $($DirtyInstallGate.status)"
}

$DirtyResiduePath = Join-Path $EvidenceRoot "m01\installer\install-preflight.json"
$DirtyLiveResiduePath = Join-Path $EvidenceRoot "m01\installer\live-preflight.json"
Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$ResidueIssue = "Registry key remains: Registry::HKEY_CURRENT_USER\Software\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}"
$ResidueLeftover = "C:\Windows\System32\YuneWindows.dll.old.0"
$DirtyLiveResiduePreflight = Get-Content -Raw -LiteralPath $DirtyLiveResiduePath | ConvertFrom-Json
$DirtyLiveResiduePreflight.machine_state_issues = @($ResidueIssue)
$DirtyLiveResiduePreflight.filesystem_leftovers = @($ResidueLeftover)
$DirtyLiveResiduePreflight | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $DirtyLiveResiduePath -Encoding utf8
$DirtyResiduePreflight = Get-Content -Raw -LiteralPath $DirtyResiduePath | ConvertFrom-Json
$DirtyResiduePreflight.machine_state_issues = @($ResidueIssue)
$DirtyResiduePreflight.filesystem_leftovers = @($ResidueLeftover)
$DirtyResiduePreflight | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $DirtyResiduePath -Encoding utf8
$DirtyResidueGate = Get-LivePreflightGate
if ($DirtyResidueGate.status -ne "invalid") {
    throw "machine-residue preflight JSON should be invalid, got $($DirtyResidueGate.status)"
}
if ($DirtyResidueGate.notes -notmatch "machine-state residue issues: 1") {
    throw "machine-residue preflight notes should name the machine-state residue count, got: $($DirtyResidueGate.notes)"
}
if ($DirtyResidueGate.notes -notmatch "filesystem leftovers: 1") {
    throw "machine-residue preflight notes should name the filesystem leftover count, got: $($DirtyResidueGate.notes)"
}

Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$NotReadyLivePreflight = Get-Content -Raw -LiteralPath $DirtyLiveResiduePath | ConvertFrom-Json
$NotReadyLivePreflight.ready_for_live_smoke = $false
$NotReadyLivePreflight.is_administrator = $false
$NotReadyLivePreflight | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $DirtyLiveResiduePath -Encoding utf8
$NotReadyGate = Get-LivePreflightGate
if ($NotReadyGate.status -ne "invalid") {
    throw "not-ready live preflight JSON should be invalid, got $($NotReadyGate.status)"
}

Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$MalformedTimestampPreflight = Get-Content -Raw -LiteralPath $DirtyLiveResiduePath | ConvertFrom-Json
$MalformedTimestampPreflight.generated_at = "not-a-date"
$MalformedTimestampPreflight | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $DirtyLiveResiduePath -Encoding utf8
$MalformedTimestampGate = Get-LivePreflightGate
if ($MalformedTimestampGate.status -ne "invalid") {
    throw "malformed generated_at preflight JSON should be invalid, got $($MalformedTimestampGate.status)"
}

Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$SelfReferentialPreflight = Get-Content -Raw -LiteralPath $DirtyLiveResiduePath | ConvertFrom-Json
$SelfReferentialPreflight.machine_residue_source = [System.IO.Path]::GetFullPath($DirtyLiveResiduePath)
$SelfReferentialPreflight | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath $DirtyLiveResiduePath -Encoding utf8
$SelfReferentialSourceGate = Get-LivePreflightGate
if ($SelfReferentialSourceGate.status -ne "invalid") {
    throw "self-referential machine_residue_source should be invalid, got $($SelfReferentialSourceGate.status)"
}

Write-EvidenceFile "m01\installer\live-preflight.json" (New-ValidPreflightJson -RequireBrowser $true)
Write-EvidenceFile "m01\installer\install-preflight.json" (New-ValidPreflightJson -RequireBrowser $false)
$ValidGate = Get-LivePreflightGate
if ($ValidGate.status -ne "complete") {
    throw "valid non-mutating preflight evidence should complete live-preflight gate, got $($ValidGate.status)"
}

Write-Host "Closeout audit validates live/install preflight JSON quality."
