param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-diagnostics-structural-events-test"
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
$DiagnosticsZip = Join-Path $EvidenceRoot "m01\settings\registered-session-diagnostics\synthetic.zip"
if (-not (Test-Path -LiteralPath $DiagnosticsZip)) {
    throw "complete synthetic fixture did not write diagnostics bundle"
}

$EditDir = Join-Path $OutputDir "diagnostics-structural-events-edit"
Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $EditDir -Force

$LogPath = Join-Path $EditDir "logs\tsf-events.log"
if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "diagnostics bundle did not contain logs\tsf-events.log"
}
$LogText = Get-Content -Raw -LiteralPath $LogPath
if (($LogText -notmatch "event=candidate_update") -or ($LogText -notmatch "event=commit_text")) {
    throw "synthetic diagnostics log must start with candidate_update and commit_text events"
}
@(
    "event=key_down sequence=1 buffer_length=1 candidate_count=0",
    "event=composition_state sequence=2 buffer_length=7 candidate_count=5"
) | Out-File -LiteralPath $LogPath -Encoding utf8

Remove-Item -LiteralPath $DiagnosticsZip -Force
Compress-Archive -Path (Join-Path $EditDir "*") -DestinationPath $DiagnosticsZip -Force

$JsonPath = Join-Path $OutputDir "audit-diagnostics-structural-events.json"
$MarkdownPath = Join-Path $OutputDir "audit-diagnostics-structural-events.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
if (-not $DiagnosticsGate) {
    throw "audit did not emit diagnostics-export gate"
}
if ($DiagnosticsGate.status -ne "invalid") {
    throw "audit should reject diagnostics bundle without candidate_update and commit_text structural events, got $($DiagnosticsGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when diagnostics structural events are incomplete"
}

Write-Host "Closeout audit rejects diagnostics bundles without candidate_update and commit_text events."
