param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-install-dir-transcript-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = Join-Path $FixtureDir "evidence"
$CommandsPath = Join-Path $EvidenceRoot "m01\installer\commands.txt"
@"
tools\install-yune-windows-ime.ps1 -ApprovedMachineStateChange
tools\run-notepad-smoke.ps1 -ApprovedMachineStateChange
tools\run-chromium-smoke.ps1 -ApprovedMachineStateChange
tools\export-yune-windows-diagnostics.ps1
tools\uninstall-yune-windows-ime.ps1 -ApprovedMachineStateChange
"@ | Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InvalidGateIds = @(
    "fresh-install-registration-activation",
    "diagnostics-export",
    "uninstall-cleanup"
)
foreach ($GateId in $InvalidGateIds) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId evidence when live commands omit -InstallDir, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts omit -InstallDir"
}

$MismatchedFixtureDir = Join-Path $OutputDir "mismatched-install-dir-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $MismatchedFixtureDir | Out-Null

$MismatchedEvidenceRoot = Join-Path $MismatchedFixtureDir "evidence"
$MismatchedCommandsPath = Join-Path $MismatchedEvidenceRoot "m01\installer\commands.txt"
if (-not (Test-Path -LiteralPath $MismatchedCommandsPath)) {
    throw "mismatched install-dir fixture did not write commands.txt"
}
(Get-Content -LiteralPath $MismatchedCommandsPath) |
    ForEach-Object {
        $_ -replace "-InstallDir\s+'[^']+'", "-InstallDir 'C:\Users\example\AppData\Local\Yune\DifferentIme'"
    } |
    Out-File -LiteralPath $MismatchedCommandsPath -Encoding utf8

$MismatchedJsonPath = Join-Path $OutputDir "audit-mismatched-install-dir.json"
$MismatchedMarkdownPath = Join-Path $OutputDir "audit-mismatched-install-dir.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $MismatchedEvidenceRoot `
    -JsonPath $MismatchedJsonPath `
    -MarkdownPath $MismatchedMarkdownPath | Out-Null

$MismatchedAudit = Get-Content -Raw -LiteralPath $MismatchedJsonPath | ConvertFrom-Json
foreach ($GateId in $InvalidGateIds) {
    $Gate = $MismatchedAudit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate for mismatched install directory"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId evidence when live commands use an install directory different from approval.md, got $($Gate.status)"
    }
}
if ($MismatchedAudit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts use an install directory different from approval.md"
}

Write-Host "Closeout audit rejects live command transcripts that omit or mismatch install directories."
