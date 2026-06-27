param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$ProductHardeningEvidence = @(
    "docs\evidence\p2-win01-installer\compatibility-matrix.md",
    "docs\evidence\p2-win01-installer\signing-decision.md"
)
$MissingProductHardeningEvidence = @($ProductHardeningEvidence | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_))
    })
if ($MissingProductHardeningEvidence.Count -gt 0) {
    $Roadmap = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\roadmap.md")
    $Requirements = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\requirements.md")
    if (($Roadmap -notmatch "Dogfood is not ready until fresh post-rename evidence proves") -or
        ($Requirements -notmatch "Fresh post-rename live evidence\s+is\s+required")) {
        throw "missing product-hardening evidence and public docs do not mark post-rename evidence as pending"
    }
    Write-Host "Product-hardening evidence is omitted from the public baseline; post-rename evidence is pending."
    return
}

function Read-RequiredDoc {
    param(
        [string]$RelativePath
    )

    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing product-hardening evidence doc: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $Path
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

$Compatibility = Read-RequiredDoc "docs\evidence\p2-win01-installer\compatibility-matrix.md"
foreach ($Pattern in @(
        '# P2-WIN01 Compatibility Matrix',
        'Status: pending-approved-live-run',
        'P2-WIN01-WIN11-X64',
        'Notepad',
        'Chromium',
        'fresh install',
        'TSF registration',
        'profile activation',
        'diagnostics export',
        'uninstall',
        'cleanup verification',
        'does not close P2-WIN01'
    )) {
    Require-Text $Compatibility ([regex]::Escape($Pattern)) "compatibility matrix"
}

$Signing = Read-RequiredDoc "docs\evidence\p2-win01-installer\signing-decision.md"
foreach ($Pattern in @(
        '# P2-WIN01 Signing Decision',
        'Decision: defer-production-signing',
        'Unsigned\s+local\s+dogfood\s+artifacts\s+are\s+allowed\s+only\s+for\s+approved\s+P2-WIN01\s+evidence\s+collection',
        'Production\s+or\s+public\s+distribution\s+remains\s+blocked',
        'code-signing\s+certificate',
        'installer\s+result\s+must\s+record\s+exact\s+artifact\s+paths',
        'does not close P2-WIN01'
    )) {
    if ($Pattern -match '\\s') {
        Require-Text $Signing $Pattern "signing decision"
    }
    else {
        Require-Text $Signing ([regex]::Escape($Pattern)) "signing decision"
    }
}

$Roadmap = Read-RequiredDoc "docs\roadmap.md"
Require-Text $Roadmap "compatibility\s+matrix\s+and\s+signing\s+decision\s+are\s+recorded" "roadmap"
Require-Text $Roadmap "dogfood\s+live\s+release\s+remain(s)?\s+open" "roadmap"
if ($Roadmap -match [regex]::Escape("compatibility matrix, signing decision, and dogfood release remain open")) {
    throw "roadmap still reports compatibility matrix and signing decision as open"
}

$Plan = Read-RequiredDoc "docs\plans\active\p2-win01-plan-windows-product.md"
foreach ($Pattern in @(
        'docs\evidence\p2-win01-installer\compatibility-matrix.md',
        'docs\evidence\p2-win01-installer\signing-decision.md',
        'tools\test-product-hardening-evidence-contract.ps1'
    )) {
    Require-Text $Plan ([regex]::Escape($Pattern)) "active plan"
}

Write-Host "Product-hardening compatibility and signing evidence contract passed."
