param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-exact-event-token-test"
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

$EditDir = Join-Path $OutputDir "diagnostics-exact-event-token-edit"
Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $EditDir -Force

$LogPath = Join-Path $EditDir "logs\tsf-events.log"
$LogText = Get-Content -Raw -LiteralPath $LogPath
if ($LogText -notmatch "event=commit_text") {
    throw "synthetic diagnostics log must start with commit_text evidence"
}
$LogText = $LogText -replace "event=commit_text", "event=commit_text_failed"
$LogText | Out-File -LiteralPath $LogPath -Encoding utf8

Remove-Item -LiteralPath $DiagnosticsZip -Force
Compress-Archive -Path (Join-Path $EditDir "*") -DestinationPath $DiagnosticsZip -Force

$JsonPath = Join-Path $OutputDir "audit-diagnostics-exact-event-token.json"
$MarkdownPath = Join-Path $OutputDir "audit-diagnostics-exact-event-token.md"
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
    throw "audit should reject diagnostics bundles with commit_text_failed but no exact commit_text event, got $($DiagnosticsGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when diagnostics commit_text evidence is only commit_text_failed"
}

Write-Host "Closeout audit requires exact diagnostics commit_text structural event tokens."
