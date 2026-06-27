param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-command-completion-test"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP "yune-windows"))
if (-not $OutputDir.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to clean output directory outside $AllowedRoot"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = Join-Path $FixtureDir "evidence"
$CommandsPath = Join-Path $EvidenceRoot "p2-win01-installer\commands.txt"
if (-not (Test-Path -LiteralPath $CommandsPath)) {
    throw "complete synthetic fixture did not write commands.txt"
}

$CommandsWithoutCompletion = @(
    Get-Content -LiteralPath $CommandsPath |
        Where-Object { $_ -notmatch '^(PASS|FAIL)\s+' }
)
$CommandsWithoutCompletion | Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-without-command-completion.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-command-completion.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "tsf-notepad-smoke",
        "candidate-display-live",
        "chromium-text-field-smoke",
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId without completed live command transcript entries, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live command completion entries are missing"
}

$FixtureWithFailureDir = Join-Path $OutputDir "complete-fixture-with-failure"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureWithFailureDir | Out-Null

$EvidenceRootWithFailure = Join-Path $FixtureWithFailureDir "evidence"
$CommandsWithFailurePath = Join-Path $EvidenceRootWithFailure "p2-win01-installer\commands.txt"
if (-not (Test-Path -LiteralPath $CommandsWithFailurePath)) {
    throw "complete synthetic fixture did not write commands.txt for failed-command case"
}

$CommandsWithFailure = @(
    "FAIL tools\export-yune-windows-diagnostics.ps1 -OutputDir 'synthetic' -InstallDir 'synthetic' # synthetic validation failure"
    Get-Content -LiteralPath $CommandsWithFailurePath
)
$CommandsWithFailure | Out-File -LiteralPath $CommandsWithFailurePath -Encoding utf8

$FailedCommandJsonPath = Join-Path $OutputDir "audit-with-failed-command.json"
$FailedCommandMarkdownPath = Join-Path $OutputDir "audit-with-failed-command.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRootWithFailure `
    -JsonPath $FailedCommandJsonPath `
    -MarkdownPath $FailedCommandMarkdownPath | Out-Null

$AuditWithFailedCommand = Get-Content -Raw -LiteralPath $FailedCommandJsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "tsf-notepad-smoke",
        "candidate-display-live",
        "chromium-text-field-smoke",
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $AuditWithFailedCommand.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId for failed-command case"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when the live command transcript contains FAIL entries, got $($Gate.status)"
    }
}
if ($AuditWithFailedCommand.status -eq "complete") {
    throw "audit should not report complete when commands.txt contains failed live command entries"
}

Write-Host "Closeout audit rejects live transcripts without command completion entries or with failed command entries."
