param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-command-order-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = Join-Path $FixtureDir "evidence"
$CommandsPath = Join-Path $EvidenceRoot "m01\installer\commands.txt"
$CompleteCommands = @(Get-Content -LiteralPath $CommandsPath)
$ReorderedCommands = @(
    $CompleteCommands | Where-Object { $_ -match "run-chromium-smoke\.ps1" }
    $CompleteCommands | Where-Object { $_ -match "run-notepad-smoke\.ps1" }
    $CompleteCommands | Where-Object { $_ -match "install-yune-windows-ime\.ps1" }
    $CompleteCommands | Where-Object { $_ -match "run-m01-live-smoke\.ps1" }
    $CompleteCommands | Where-Object { $_ -match "export-yune-windows-diagnostics\.ps1" }
    $CompleteCommands | Where-Object { $_ -match "uninstall-yune-windows-ime\.ps1" }
)
$ReorderedCommands | Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InvalidGateIds = @(
    "tsf-notepad-smoke",
    "candidate-display-live",
    "chromium-text-field-smoke",
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
        throw "audit should reject $GateId evidence with out-of-order live commands, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live commands are out of order"
}

Write-Host "Closeout audit rejects out-of-order live command transcripts."
