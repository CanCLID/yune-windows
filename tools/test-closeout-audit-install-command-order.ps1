param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-install-command-order-test"
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
tools\run-chromium-smoke.ps1 -ApprovedMachineStateChange
tools\run-notepad-smoke.ps1 -ApprovedMachineStateChange
tools\install-yune-windows-ime.ps1 -ApprovedMachineStateChange
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
$InstallGate = $Audit.gates |
    Where-Object { $_.id -eq "fresh-install-registration-activation" } |
    Select-Object -First 1
if (-not $InstallGate) {
    throw "audit did not emit fresh-install-registration-activation gate"
}
if ($InstallGate.status -ne "invalid") {
    throw "audit should reject fresh install/profile evidence when smoke commands occur before install, got $($InstallGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when install/smoke commands are out of order"
}

Write-Host "Closeout audit rejects out-of-order install/smoke command transcripts."
