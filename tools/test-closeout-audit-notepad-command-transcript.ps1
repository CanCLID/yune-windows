param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-notepad-command-transcript-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $FixtureDir "evidence"))
$CommandsPath = Join-Path $EvidenceRoot "m01\installer\commands.txt"
if (-not (Test-Path -LiteralPath $CommandsPath)) {
    throw "complete fixture did not write commands.txt"
}

(Get-Content -LiteralPath $CommandsPath) |
    Where-Object { $_ -notmatch "run-notepad-smoke\.ps1" } |
    Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-missing-notepad-transcript.json"
$MarkdownPath = Join-Path $OutputDir "audit-missing-notepad-transcript.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InvalidGateIds = @(
    "tsf-notepad-smoke",
    "candidate-display-live",
    "fresh-install-registration-activation"
)
foreach ($GateId in $InvalidGateIds) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when live command transcripts omit the approved Notepad smoke command, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts omit the approved Notepad smoke command"
}

Write-Host "Closeout audit rejects Notepad smoke evidence without approved command transcript entries."
