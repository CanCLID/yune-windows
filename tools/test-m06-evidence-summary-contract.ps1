param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$EvidenceRoot = Join-Path $RepoRoot "docs\evidence\m06"
$SummaryPath = Join-Path $EvidenceRoot "summary.md"
$JsonPath = Join-Path $EvidenceRoot "summary.json"
$MatrixPath = Join-Path $EvidenceRoot "matrix.md"

foreach ($Path in @($SummaryPath, $JsonPath, $MatrixPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M06 evidence file: $Path"
    }
}

$Summary = Get-Content -Raw -LiteralPath $SummaryPath
$Matrix = Get-Content -Raw -LiteralPath $MatrixPath
$Evidence = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json

foreach ($RequiredSection in @(
        "## Executed Proof",
        "## Host Matrix",
        "## Holder-free Live Proof",
        "## Follow-up Coverage",
        "## Deferred"
    )) {
    if ($Summary -notmatch [regex]::Escape($RequiredSection)) {
        throw "M06 evidence summary must contain section: $RequiredSection"
    }
}

# M06 is complete: the summary must record the root cause of the no-output hosts
# and the live host-matrix pass so "complete" is backed by evidence.
foreach ($Required in @(
        "Status: complete",
        "default security descriptor",
        "ERROR_ACCESS_DENIED",
        "reboot-free",
        "Chrome / Telegram / Zed / Explorer",
        "first press"
    )) {
    if ($Summary -notmatch [regex]::Escape($Required)) {
        throw "M06 summary is missing completion evidence text: $Required"
    }
}

$ExecutedText = (@($Evidence.executed_proof) -join "`n")
foreach ($Required in @(
        "server pipe-security contract passed",
        "F2a shared server survives client disconnects",
        "F1/F2b/F5/F6 key-path source contract passed",
        "server IME state protocol contract passed after startup dictionary warm-up",
        "TSF shell build"
    )) {
    if ($ExecutedText -notmatch [regex]::Escape($Required)) {
        throw "M06 executed proof is missing: $Required"
    }
}

if ($Evidence.status -ne "complete") {
    throw "M06 summary status must be complete."
}
if ($Evidence.manual_live_required -ne $false) {
    throw "M06 summary JSON must record manual_live_required=false once live proof lands."
}
if ($Evidence.plan_archived -ne $true) {
    throw "M06 plan must be archived once the live host matrix is filled."
}
if ($Evidence.host_matrix.status -ne "passed") {
    throw "M06 host matrix status must be passed."
}
if (@($Evidence.live_proof).Count -lt 1) {
    throw "M06 summary JSON must record at least one passing live_proof entry."
}

foreach ($HostName in @("Notepad", "Chromium browser", "Telegram Desktop")) {
    if ($Matrix -notmatch [regex]::Escape($HostName)) {
        throw "M06 matrix is missing required host: $HostName"
    }
}
foreach ($Required in @(
        "Shift+/",
        "Shift+=",
        "Shift+-",
        "tools\collect-m06-compatibility-environment.ps1",
        "tools\capture-m06-tsf-events-window.ps1"
    )) {
    if ($Matrix -notmatch [regex]::Escape($Required)) {
        throw "M06 matrix/operator script is missing: $Required"
    }
}

Write-Host "M06 evidence summary records the complete milestone with live host-matrix proof."
