param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$LegacyMap = Join-Path $RepoRoot "docs\reference\legacy-milestone-map.md"
$Roots = @(
    "README.md",
    "AGENTS.md",
    "docs",
    "tools",
    "src"
)

$OldLabelPattern = ('p2' + '-win|' + 'P2' + '-WIN')
$Files = foreach ($Root in $Roots) {
    $Path = Join-Path $RepoRoot $Root
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Item -LiteralPath $Path
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path -Recurse -File
    }
}

$UnexpectedHits = @()
foreach ($File in $Files) {
    $FullName = [System.IO.Path]::GetFullPath($File.FullName)
    $IsLegacyMap = [string]::Equals(
        $FullName,
        [System.IO.Path]::GetFullPath($LegacyMap),
        [System.StringComparison]::OrdinalIgnoreCase)
    $Hits = @(Select-String -LiteralPath $FullName -Pattern $OldLabelPattern)
    if (($Hits.Count -gt 0) -and (-not $IsLegacyMap)) {
        $UnexpectedHits += @($Hits | ForEach-Object {
                "$($_.Path):$($_.LineNumber):$($_.Line.Trim())"
            })
    }
}
if ($UnexpectedHits.Count -gt 0) {
    throw "old milestone labels are only allowed in docs\reference\legacy-milestone-map.md:`n$($UnexpectedHits -join "`n")"
}

if (-not (Test-Path -LiteralPath $LegacyMap -PathType Leaf)) {
    throw "missing legacy milestone map: docs\reference\legacy-milestone-map.md"
}
$LegacyMapText = Get-Content -Raw -LiteralPath $LegacyMap
foreach ($Index in 1..5) {
    $Legacy = ("P2" + "-WIN{0:D2}") -f $Index
    $Current = "M{0:D2}" -f $Index
    if ($LegacyMapText -notmatch [regex]::Escape("| $Legacy | $Current |")) {
        throw "legacy milestone map is missing $Legacy -> $Current"
    }
}

$TrackedPaths = @(& git -C $RepoRoot ls-files)
$BadTrackedPaths = @($TrackedPaths | Where-Object { $_ -match $OldLabelPattern })
if ($BadTrackedPaths.Count -gt 0) {
    throw "tracked paths must not use old milestone labels:`n$($BadTrackedPaths -join "`n")"
}

foreach ($Index in 1..5) {
    $Current = "m{0:D2}" -f $Index
    $EvidenceSummary = Join-Path $RepoRoot "docs\evidence\$Current\summary.json"
    if ($Index -eq 5) {
        $EvidenceSummary = Join-Path $RepoRoot "docs\evidence\$Current\README.md"
    }
    if (-not (Test-Path -LiteralPath $EvidenceSummary -PathType Leaf)) {
        throw "missing compact evidence root file: $EvidenceSummary"
    }
}

foreach ($Expected in @(
        "docs\plans\history\m01-plan-windows-product.md",
        "docs\plans\history\m02-plan-server-lifecycle-cleanup-hardening.md",
        "docs\plans\history\m03-plan-dev-inner-loop.md",
        "docs\plans\history\m04-plan-candidate-window-typing-quality.md",
        "docs\plans\active\m05-plan-ime-toggles-language-bar-settings.md",
        "tools\run-m01-live-smoke.ps1",
        "tools\start-m01-elevated-live-smoke.ps1",
        "tools\run-m01-detached-live-smoke-helper.ps1",
        "tools\audit-m01-closeout.ps1",
        "tools\write-m01-approval-brief.ps1",
        "tools\collect-m01-compatibility-environment.ps1",
        "tools\test-m01-closeout-audit.ps1"
    )) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Expected) -PathType Leaf)) {
        throw "missing M-style path: $Expected"
    }
}

Write-Host "Milestone naming contract passed."
