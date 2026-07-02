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

if ($Summary -match "Status:\s*complete\b") {
    throw "M06 summary must not mark the milestone complete before the holder-free host matrix is filled."
}

foreach ($Required in @(
        "implementation complete; holder-free live host matrix pending",
        "F1, F2a/F2b, F5, and F6",
        "manual holder-free live verification remains required",
        "No host pass/fail claims are made"
    )) {
    if ($Summary -notmatch [regex]::Escape($Required)) {
        throw "M06 summary is missing boundary text: $Required"
    }
}

$ExecutedText = (@($Evidence.executed_proof) -join "`n")
foreach ($Required in @(
        "F2a shared server survives client disconnects",
        "F1/F2b/F5/F6 key-path source contract passed",
        "punctuation commit contract passed",
        "TSF key-eating contract passed",
        "TSF shell build"
    )) {
    if ($ExecutedText -notmatch [regex]::Escape($Required)) {
        throw "M06 executed proof is missing: $Required"
    }
}

if ($Evidence.status -ne "implementation_complete_live_pending") {
    throw "M06 summary status must be implementation_complete_live_pending until live host matrix evidence lands."
}
if ($Evidence.manual_live_required -ne $true) {
    throw "M06 summary JSON must record manual_live_required=true."
}
if ($Evidence.plan_archived -ne $false) {
    throw "M06 plan must stay active until live host-matrix closeout is complete."
}
if ($Evidence.host_matrix.status -ne "pending_holder_free_live_verification") {
    throw "M06 host matrix status must remain pending until operator evidence lands."
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

Write-Host "M06 evidence summary keeps local proof separate from pending holder-free live matrix evidence."
