param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-live-preflight-transcript-test"
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

$Commands = Get-Content -LiteralPath $CommandsPath
if (-not ($Commands -match 'run-p2-win01-live-smoke\.ps1 -PreflightOnly')) {
    throw "complete synthetic fixture must include live-preflight transcript entries"
}
$Commands |
    Where-Object { $_ -notmatch 'run-p2-win01-live-smoke\.ps1 -PreflightOnly' } |
    Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-without-live-preflight-transcript.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-live-preflight-transcript.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "live-preflight",
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId without live-preflight transcript entries, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live-preflight transcript entries are missing"
}

$WrongPathFixtureDir = Join-Path $OutputDir "wrong-preflight-path-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $WrongPathFixtureDir | Out-Null

$WrongPathEvidenceRoot = Join-Path $WrongPathFixtureDir "evidence"
$WrongPathCommandsPath = Join-Path $WrongPathEvidenceRoot "p2-win01-installer\commands.txt"
$ExpectedPreflightPath = [regex]::Escape("$WrongPathEvidenceRoot\p2-win01-installer\live-preflight.json")
$WrongPreflightPath = "$WrongPathEvidenceRoot\p2-win01-installer\unreviewed-live-preflight.json"
$WrongPathCommands = Get-Content -LiteralPath $WrongPathCommandsPath
if (-not ($WrongPathCommands -match $ExpectedPreflightPath)) {
    throw "complete synthetic fixture must include the checked-in live-preflight path"
}
$WrongPathCommands |
    ForEach-Object {
        $_ -replace $ExpectedPreflightPath, $WrongPreflightPath
    } |
    Out-File -LiteralPath $WrongPathCommandsPath -Encoding utf8

$WrongPathJsonPath = Join-Path $OutputDir "audit-wrong-live-preflight-path.json"
$WrongPathMarkdownPath = Join-Path $OutputDir "audit-wrong-live-preflight-path.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $WrongPathEvidenceRoot `
    -JsonPath $WrongPathJsonPath `
    -MarkdownPath $WrongPathMarkdownPath | Out-Null

$WrongPathAudit = Get-Content -Raw -LiteralPath $WrongPathJsonPath | ConvertFrom-Json
foreach ($GateId in @(
        "live-preflight",
        "fresh-install-registration-activation",
        "diagnostics-export",
        "uninstall-cleanup"
    )) {
    $Gate = $WrongPathAudit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId for wrong preflight path"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when live-preflight transcript entries point at the wrong preflight path, got $($Gate.status)"
    }
}
if ($WrongPathAudit.status -eq "complete") {
    throw "audit should not report complete when live-preflight transcript entries point at the wrong preflight path"
}

Write-Host "Closeout audit rejects live transcripts without live-preflight entries or with the wrong preflight path."
