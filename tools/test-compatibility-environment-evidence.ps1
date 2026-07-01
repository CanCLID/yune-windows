param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Collector = Join-Path $RepoRoot "tools\collect-m01-compatibility-environment.ps1"
if (-not (Test-Path -LiteralPath $Collector)) {
    throw "missing compatibility environment collector: tools\collect-m01-compatibility-environment.ps1"
}

$Source = Get-Content -Raw -LiteralPath $Collector
foreach ($Required in @(
        'live-smoke-support\.ps1',
        'Find-ChromiumBrowserPath',
        'machine_state_changed\s*=\s*\$false',
        'compatibility_target_id',
        'M01-WIN11-X64',
        'approval_required_for_live_gates\s*=\s*\$true',
        'live_status\s*=\s*"covered-by-m02-summary"',
        'live_closeout_evidence\s*=\s*"docs/evidence/m02/summary\.json"',
        'm01_closes\s*=\s*\$true'
    )) {
    if ($Source -notmatch $Required) {
        throw "compatibility environment collector is missing required pattern: $Required"
    }
}

foreach ($Forbidden in @(
        'Remove-Item',
        'Remove-ItemProperty',
        'Set-ItemProperty',
        'New-ItemProperty',
        'reg\.exe',
        'regsvr32',
        'Stop-Process',
        'Start-Process'
    )) {
    if ($Source -match $Forbidden) {
        throw "compatibility environment collector must be non-mutating and must not contain: $Forbidden"
    }
}

$OutputPath = Join-Path $env:TEMP "yune-windows\m01-compatibility-environment-test.json"
& powershell -NoProfile -ExecutionPolicy Bypass -File $Collector -OutputPath $OutputPath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "compatibility environment collector failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "compatibility environment collector did not write output: $OutputPath"
}

$Environment = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
foreach ($Property in @(
        "generated_at",
        "machine_state_changed",
        "compatibility_target_id",
        "os_caption",
        "os_version",
        "os_build",
        "os_architecture",
        "process_architecture",
        "browser_path",
        "browser_available",
        "approval_required_for_live_gates",
        "live_status",
        "live_closeout_evidence",
        "m01_closes"
    )) {
    if (-not $Environment.PSObject.Properties.Name.Contains($Property)) {
        throw "compatibility environment output is missing field: $Property"
    }
}

try {
    [DateTimeOffset]::Parse($Environment.generated_at) | Out-Null
}
catch {
    throw "compatibility environment generated_at is not parseable ISO timestamp: $($Environment.generated_at)"
}

if ($Environment.machine_state_changed -ne $false) {
    throw "compatibility environment must record machine_state_changed=false"
}
if ($Environment.compatibility_target_id -ne "M01-WIN11-X64") {
    throw "unexpected compatibility target: $($Environment.compatibility_target_id)"
}
if ([string]::IsNullOrWhiteSpace($Environment.os_caption)) {
    throw "compatibility environment must record os_caption"
}
if ([string]::IsNullOrWhiteSpace($Environment.os_architecture)) {
    throw "compatibility environment must record os_architecture"
}
if ($Environment.approval_required_for_live_gates -ne $true) {
    throw "compatibility environment must keep live gates approval-required"
}
if ($Environment.live_status -ne "covered-by-m02-summary") {
    throw "compatibility environment must record covered summary status, got $($Environment.live_status)"
}
if ($Environment.live_closeout_evidence -ne "docs/evidence/m02/summary.json") {
    throw "compatibility environment must point to the M02 summary evidence"
}
if ($Environment.m01_closes -ne $true) {
    throw "compatibility environment must claim M01 closeout after covered live closeout"
}

$M01SummaryPath = Join-Path $RepoRoot "docs\evidence\m01\summary.json"
$M02SummaryPath = Join-Path $RepoRoot "docs\evidence\m02\summary.json"
foreach ($Path in @($M01SummaryPath, $M02SummaryPath)) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing compact evidence summary: $Path"
    }
}

$M01Summary = Get-Content -Raw -LiteralPath $M01SummaryPath | ConvertFrom-Json
$M02Summary = Get-Content -Raw -LiteralPath $M02SummaryPath | ConvertFrom-Json
if ($M01Summary.compatibility.target_id -ne "M01-WIN11-X64") {
    throw "M01 summary must retain compatibility target M01-WIN11-X64"
}
if ($M01Summary.compatibility.live_status -ne "covered-by-m02-summary") {
    throw "M01 summary must retain covered live status"
}
if ($M01Summary.compatibility.live_closeout_evidence -ne "docs/evidence/m02/summary.json") {
    throw "M01 summary must point to M02 summary evidence"
}
if ($M02Summary.closeout.live_status -ne "covered-by-m02-summary") {
    throw "M02 summary must retain closeout coverage status"
}
if ($M02Summary.closeout.no_residue_after_reboot -ne $true) {
    throw "M02 summary must retain post-reboot no-residue result"
}

$Plan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\plans\history\m01-plan-windows-product.md")
foreach ($RequiredPlanText in @(
        'tools\collect-m01-compatibility-environment.ps1',
        'tools\test-compatibility-environment-evidence.ps1'
    )) {
    if ($Plan -notmatch [regex]::Escape($RequiredPlanText)) {
        throw "archived plan is missing compatibility environment reference: $RequiredPlanText"
    }
}

Write-Host "Compatibility environment evidence is non-mutating and summarized for M01."
