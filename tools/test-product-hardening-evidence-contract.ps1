param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RequiredText {
    param([string]$RelativePath)

    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing required doc: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $Path
}

function Read-RequiredJson {
    param([string]$RelativePath)

    $Text = Read-RequiredText $RelativePath
    try {
        return $Text | ConvertFrom-Json
    }
    catch {
        throw "required JSON is invalid: $RelativePath"
    }
}

function Require-Text {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Context
    )

    if ($Text -notmatch $Pattern) {
        throw "$Context is missing required evidence text: $Pattern"
    }
}

$M01Summary = Read-RequiredJson "docs\evidence\m01\summary.json"
$M02Summary = Read-RequiredJson "docs\evidence\m02\summary.json"

if ($M01Summary.milestone -ne "M01") {
    throw "M01 summary has unexpected milestone: $($M01Summary.milestone)"
}
if ($M01Summary.status -ne "complete") {
    throw "M01 summary must remain complete"
}
if ($M01Summary.evidence_policy -ne "compact-summary-only") {
    throw "M01 summary must document compact-summary-only evidence policy"
}
if ($M01Summary.compatibility.target_id -ne "M01-WIN11-X64") {
    throw "M01 summary must retain compatibility target M01-WIN11-X64"
}
if ($M01Summary.compatibility.live_status -ne "covered-by-m02-summary") {
    throw "M01 summary must record covered live status"
}
if ($M01Summary.compatibility.live_closeout_evidence -ne "docs/evidence/m02/summary.json") {
    throw "M01 summary must point to the M02 compact closeout summary"
}
foreach ($ExpectedPath in @(
        "fresh install",
        "TSF registration",
        "profile activation",
        "Notepad",
        "Chromium",
        "diagnostics export",
        "uninstall",
        "cleanup verification"
    )) {
    if ($ExpectedPath -notin @($M01Summary.compatibility.tested_paths)) {
        throw "M01 compatibility summary is missing tested path: $ExpectedPath"
    }
}
if ($M01Summary.signing.decision -ne "defer-production-signing") {
    throw "M01 signing summary must defer production signing"
}
if ($M01Summary.signing.unsigned_local_dogfood_only -ne $true) {
    throw "M01 signing summary must restrict unsigned artifacts to local dogfood"
}
if ($M01Summary.signing.production_distribution_blocked -ne $true) {
    throw "M01 signing summary must block production/public distribution"
}

if ($M02Summary.milestone -ne "M02") {
    throw "M02 summary has unexpected milestone: $($M02Summary.milestone)"
}
if ($M02Summary.closeout.product_owned_server_start_observed -ne $true) {
    throw "M02 summary must retain product-owned server start evidence"
}
if ($M02Summary.closeout.profile_active_verified_before_typing -ne $true) {
    throw "M02 summary must retain profile active before typing evidence"
}
if ($M02Summary.closeout.no_residue_after_reboot -ne $true) {
    throw "M02 summary must retain post-reboot no-residue cleanup evidence"
}

$Roadmap = Read-RequiredText "docs\roadmap.md"
Require-Text $Roadmap "Compatibility target and signing decision are retained in compact M01 summary evidence" "roadmap"
Require-Text $Roadmap "dogfood\s+packaging,\s+release\s+signing,\s+non-blocking\s+cold-start,\s+and\s+user-data\s+preservation\s+remain\s+open" "roadmap"
if ($Roadmap -match [regex]::Escape("compatibility matrix, signing decision, and dogfood release remain open")) {
    throw "roadmap still reports compatibility matrix and signing decision as open"
}

$Plan = Read-RequiredText "docs\plans\history\m01-plan-windows-product.md"
foreach ($Pattern in @(
        'tools\collect-m01-compatibility-environment.ps1',
        'tools\test-product-hardening-evidence-contract.ps1'
    )) {
    Require-Text $Plan ([regex]::Escape($Pattern)) "archived M01 plan"
}

Write-Host "Product-hardening compatibility and signing evidence summary contract passed."
