param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-closeout-audit-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$Audit = Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1"
if (-not (Test-Path -LiteralPath $Audit)) {
    throw "missing P2-WIN01 closeout audit script: $Audit"
}

$JsonPath = Join-Path $OutputDir "closeout-audit.json"
$MarkdownPath = Join-Path $OutputDir "closeout-audit.md"
& $Audit -JsonPath $JsonPath -MarkdownPath $MarkdownPath
if (-not (Test-Path -LiteralPath $JsonPath)) {
    throw "closeout audit did not create JSON output"
}
if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    throw "closeout audit did not create Markdown output"
}

$Result = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$Markdown = Get-Content -Raw -LiteralPath $MarkdownPath
$IncompleteIds = @($Result.gates | Where-Object { $_.status -ne "complete" } | ForEach-Object { $_.id })
$ExpectedOverallStatus = if ($IncompleteIds.Count -eq 0) { "complete" } else { "incomplete" }
if ($Result.status -ne $ExpectedOverallStatus) {
    throw "P2-WIN01 closeout audit status should be $ExpectedOverallStatus when non-complete gate count is $($IncompleteIds.Count), got $($Result.status)"
}
if ($Result.status -eq "complete") {
    foreach ($StaleCompleteNote in @(
            'live display proof is still needed',
            'approved browser/profile automation still pending',
            'live registered-session export still pending',
            'P2-WIN01 must remain open until every gate is complete')) {
        if ($Markdown -match [regex]::Escape($StaleCompleteNote)) {
            throw "complete closeout audit retained stale pending note: $StaleCompleteNote"
        }
    }
    if ($Markdown -notmatch [regex]::Escape("P2-WIN01 closeout gates are complete.")) {
        throw "complete closeout audit must report completed gates in final note"
    }
}

function Test-TextEvidencePattern {
    param(
        [string]$RelativePath,
        [string]$Pattern
    )
    $EvidencePath = Join-Path $RepoRoot $RelativePath
    return ((Test-Path -LiteralPath $EvidencePath) -and
        (Select-String -Path $EvidencePath -Pattern $Pattern -Quiet))
}

function Test-JsonEvidenceBoolean {
    param(
        [string]$RelativePath,
        [string]$PropertyName
    )
    $EvidencePath = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $EvidencePath)) {
        return $false
    }
    $Evidence = Get-Content -Raw -LiteralPath $EvidencePath | ConvertFrom-Json
    return ($Evidence.PSObject.Properties.Name -contains $PropertyName) -and ($Evidence.$PropertyName -eq $true)
}

$LiveEvidenceRequirements = @(
    @{
        Gate = "tsf-notepad-smoke"
        Present = Test-TextEvidencePattern `
            "docs\evidence\p2-win01-tsf-smoke\notepad-smoke-result.md" `
            "^Status:\s*passed\s*$"
    },
    @{
        Gate = "chromium-text-field-smoke"
        Present = Test-TextEvidencePattern `
            "docs\evidence\p2-win01-tsf-smoke\chromium-smoke-result.md" `
            "^Status:\s*passed\s*$"
    },
    @{
        Gate = "fresh-install-registration-activation"
        Present = Test-TextEvidencePattern `
            "docs\evidence\p2-win01-installer\result.md" `
            "^Status:\s*passed\s*$"
    },
    @{
        Gate = "uninstall-cleanup"
        Present = (
            (Test-TextEvidencePattern `
                "docs\evidence\p2-win01-installer\cleanup-result.md" `
                "^Status:\s*passed\s*$") -and
            (Test-JsonEvidenceBoolean `
                "docs\evidence\p2-win01-installer\cleanup-validation.json" `
                "pass"))
    }
)

foreach ($Requirement in $LiveEvidenceRequirements) {
    if ((-not $Requirement.Present) -and ($IncompleteIds -notcontains $Requirement.Gate)) {
        throw "closeout audit did not report incomplete gate for missing or failing live evidence: $($Requirement.Gate)"
    }
}

$EngineBoundary = $Result.gates | Where-Object { $_.id -eq "engine-boundary" } | Select-Object -First 1
if (-not $EngineBoundary) {
    throw "closeout audit is missing the engine-boundary gate"
}
if ($EngineBoundary.status -ne "complete") {
    throw "engine-boundary gate should be complete for current implementation sources, got $($EngineBoundary.status)"
}

$LivePreflight = $Result.gates | Where-Object { $_.id -eq "live-preflight" } | Select-Object -First 1
if (-not $LivePreflight) {
    throw "closeout audit is missing the live-preflight gate"
}

$PreflightResidueCount = 0
foreach ($RelativePreflightPath in @(
        "docs\evidence\p2-win01-installer\live-preflight.json",
        "docs\evidence\p2-win01-installer\install-preflight.json")) {
    $PreflightPath = Join-Path $RepoRoot $RelativePreflightPath
    if (Test-Path -LiteralPath $PreflightPath) {
        $Preflight = Get-Content -Raw -LiteralPath $PreflightPath | ConvertFrom-Json
        $PreflightResidueCount += @($Preflight.machine_state_issues).Count
        $PreflightResidueCount += @($Preflight.filesystem_leftovers).Count
    }
}
$ExpectedLivePreflightStatus = "complete"
$AnyPreflightEvidence = $false
foreach ($RelativePreflightPath in @(
        "docs\evidence\p2-win01-installer\live-preflight.json",
        "docs\evidence\p2-win01-installer\install-preflight.json")) {
    if (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePreflightPath)) {
        $AnyPreflightEvidence = $true
    }
}
if (-not $AnyPreflightEvidence) {
    $Requirements = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\requirements.md")
    if ($Requirements -notmatch "Fresh post-rename live evidence\s+is\s+required") {
        throw "missing live preflight evidence and requirements do not mark post-rename evidence as pending"
    }
    $ExpectedLivePreflightStatus = "missing"
}
if ($PreflightResidueCount -gt 0) {
    $ExpectedLivePreflightStatus = "invalid"
}
$CommandsPath = Join-Path $RepoRoot "docs\evidence\p2-win01-installer\commands.txt"
if (Test-Path -LiteralPath $CommandsPath) {
    $CommandsText = Get-Content -Raw -LiteralPath $CommandsPath
    $FailedCommandLines = @($CommandsText -split "`r?`n" | Where-Object { $_ -match '^FAIL\s+' })
    $RecoveredDelayedDeleteFailure =
        ($FailedCommandLines.Count -eq 1) -and
        ($FailedCommandLines[0] -match '^FAIL\s+.*uninstall-yune-windows-ime\.ps1') -and
        ($FailedCommandLines[0] -match 'locked YuneWindowsTSF\.dll')
    if (($FailedCommandLines.Count -gt 0) -and (-not $RecoveredDelayedDeleteFailure)) {
        $ExpectedLivePreflightStatus = "invalid"
    }
}
if ($LivePreflight.status -ne $ExpectedLivePreflightStatus) {
    throw "live-preflight gate should be $ExpectedLivePreflightStatus for current durable preflight evidence, got $($LivePreflight.status)"
}

Write-Host "P2-WIN01 closeout audit smoke passed: status=$($Result.status), incomplete=$($IncompleteIds.Count)"
