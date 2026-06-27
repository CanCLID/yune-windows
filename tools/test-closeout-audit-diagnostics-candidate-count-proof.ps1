param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-candidate-count-proof-test"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP "yune-windows"))
if (-not $OutputDir.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to clean output directory outside $AllowedRoot"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"
$DiagnosticsZip = Join-Path $EvidenceRoot "p2-win01-settings\registered-session-diagnostics\synthetic.zip"
if (-not (Test-Path -LiteralPath $DiagnosticsZip)) {
    throw "complete synthetic fixture did not write diagnostics bundle"
}

$EditDir = Join-Path $OutputDir "diagnostics-candidate-count-proof-edit"
Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $EditDir -Force

$LogPath = Join-Path $EditDir "logs\tsf-events.log"
if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "diagnostics bundle did not contain logs\tsf-events.log"
}
$LogText = Get-Content -Raw -LiteralPath $LogPath
if ($LogText -notmatch "(^|\s)event=candidate_update(?=\s|$)") {
    throw "synthetic diagnostics log must start with candidate_update evidence"
}
if ($LogText -notmatch "(^|\s)event=candidate_update(?=\s|$).*?(^|\s)candidate_count=[1-9]\d*(?=\s|$)") {
    throw "synthetic diagnostics candidate_update evidence must start with a positive candidate_count"
}

$MutatedLines = foreach ($Line in @($LogText -split "\r?\n")) {
    if ($Line -match "(^|\s)event=candidate_update(?=\s|$)") {
        $Line -replace "(^|\s)candidate_count=\d+(?=\s|$)", '${1}candidate_count=0'
    }
    else {
        $Line
    }
}
$MutatedLines | Out-File -LiteralPath $LogPath -Encoding utf8

Remove-Item -LiteralPath $DiagnosticsZip -Force
Compress-Archive -Path (Join-Path $EditDir "*") -DestinationPath $DiagnosticsZip -Force

$JsonPath = Join-Path $OutputDir "audit-diagnostics-candidate-count-proof.json"
$MarkdownPath = Join-Path $OutputDir "audit-diagnostics-candidate-count-proof.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
if (-not $DiagnosticsGate) {
    throw "audit did not emit diagnostics-export gate"
}
if ($DiagnosticsGate.status -ne "invalid") {
    throw "audit should reject diagnostics bundles whose candidate_update event has no positive candidate_count, got $($DiagnosticsGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when diagnostics candidate_update evidence has no positive candidate_count"
}

Write-Host "Closeout audit rejects diagnostics candidate_update evidence without a positive candidate_count."
