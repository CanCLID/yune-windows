param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-browser-path-transcript-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $FixtureDir "evidence"))
$CommandsPath = Join-Path $EvidenceRoot "p2-win01-installer\commands.txt"
if (-not (Test-Path -LiteralPath $CommandsPath)) {
    throw "complete fixture did not write commands.txt"
}

(Get-Content -LiteralPath $CommandsPath) |
    ForEach-Object {
        $_ -replace "\s-BrowserPath\s+'[^']+'", ""
    } |
    Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-missing-browser-path.json"
$MarkdownPath = Join-Path $OutputDir "audit-missing-browser-path.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InvalidGateIds = @(
    "fresh-install-registration-activation",
    "chromium-text-field-smoke"
)
foreach ($GateId in $InvalidGateIds) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when live command transcripts omit the approved Chromium browser path, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts omit the approved Chromium browser path"
}

Write-Host "Closeout audit rejects live command transcripts that omit the approved Chromium browser path."
