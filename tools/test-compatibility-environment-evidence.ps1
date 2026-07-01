param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Collector = Join-Path $RepoRoot "tools\collect-p2-win01-compatibility-environment.ps1"
if (-not (Test-Path -LiteralPath $Collector)) {
    throw "missing compatibility environment collector: tools\collect-p2-win01-compatibility-environment.ps1"
}

$Source = Get-Content -Raw -LiteralPath $Collector
foreach ($Required in @(
        'live-smoke-support\.ps1',
        'Find-ChromiumBrowserPath',
        'machine_state_changed\s*=\s*\$false',
        'compatibility_target_id',
        'P2-WIN01-WIN11-X64',
        'approval_required_for_live_gates\s*=\s*\$true',
        'live_status\s*=\s*"covered-by-p2-win02-live-closeout"',
        'live_closeout_evidence',
        'p2_win01_closes\s*=\s*\$true'
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

$OutputPath = Join-Path $env:TEMP "yune-windows\p2-win01-compatibility-environment-test.json"
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
        "p2_win01_closes"
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
if ($Environment.compatibility_target_id -ne "P2-WIN01-WIN11-X64") {
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
if ($Environment.live_status -ne "covered-by-p2-win02-live-closeout") {
    throw "compatibility environment must record covered live status, got $($Environment.live_status)"
}
if ($Environment.live_closeout_evidence -ne "docs/evidence/p2-win02-server-lifecycle/live-closeout-20260630-203015.md") {
    throw "compatibility environment must point to the recovered P2-WIN02 live closeout evidence"
}
if ($Environment.p2_win01_closes -ne $true) {
    throw "compatibility environment must claim P2-WIN01 closeout after recovered live closeout"
}

$DurablePath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\compatibility-environment.json"
if (-not (Test-Path -LiteralPath $DurablePath)) {
    $Requirements = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\requirements.md")
    if ($Requirements -notmatch "Fresh post-rename live evidence\s+is\s+required") {
        throw "missing durable compatibility environment evidence and requirements do not mark post-rename evidence as pending"
    }
    Write-Host "Compatibility environment durable evidence is omitted from the public baseline; post-rename evidence is pending."
    return
}

$CompatibilityMatrixPath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\compatibility-matrix.md"
if (-not (Test-Path -LiteralPath $CompatibilityMatrixPath)) {
    $Roadmap = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\roadmap.md")
    if ($Roadmap -notmatch "Dogfood is not ready until fresh post-rename evidence proves") {
        throw "missing compatibility matrix and roadmap does not mark post-rename evidence as pending"
    }
    Write-Host "Compatibility matrix evidence is omitted from the public baseline; post-rename evidence is pending."
    return
}
$CompatibilityMatrix = Get-Content -Raw -LiteralPath $CompatibilityMatrixPath
if ($CompatibilityMatrix -notmatch [regex]::Escape("compatibility-environment.json")) {
    throw "compatibility matrix must reference compatibility-environment.json"
}
if ($CompatibilityMatrix -match [regex]::Escape("pending-approved-live-run")) {
    throw "compatibility matrix must not retain pending-approved-live-run after live closeout"
}
if ($CompatibilityMatrix -notmatch [regex]::Escape("docs/evidence/p2-win02-server-lifecycle/live-closeout-20260630-203015.md")) {
    throw "compatibility matrix must point to the recovered P2-WIN02 live closeout evidence"
}

$DurableEnvironment = Get-Content -Raw -LiteralPath $DurablePath | ConvertFrom-Json
if ($DurableEnvironment.live_status -ne "covered-by-p2-win02-live-closeout") {
    throw "durable compatibility environment must record covered live status"
}
if ($DurableEnvironment.live_closeout_evidence -ne "docs/evidence/p2-win02-server-lifecycle/live-closeout-20260630-203015.md") {
    throw "durable compatibility environment must point to recovered live closeout evidence"
}
if ($DurableEnvironment.p2_win01_closes -ne $true) {
    throw "durable compatibility environment must record that the recovered live closeout closes P2-WIN01"
}

$Plan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\plans\history\p2-win01-plan-windows-product.md")
foreach ($RequiredPlanText in @(
        'tools\collect-p2-win01-compatibility-environment.ps1',
        'tools\test-compatibility-environment-evidence.ps1',
        'docs\evidence\p2-win01-installer\compatibility-environment.json'
    )) {
    if ($Plan -notmatch [regex]::Escape($RequiredPlanText)) {
        throw "active plan is missing compatibility environment evidence reference: $RequiredPlanText"
    }
}

Write-Host "Compatibility environment evidence is non-mutating and recorded for P2-WIN01."
