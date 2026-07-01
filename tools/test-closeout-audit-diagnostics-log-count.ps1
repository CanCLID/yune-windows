param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-diagnostics-log-count-test"
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

$EditDir = Join-Path $OutputDir "diagnostics-log-count-edit"
Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $EditDir -Force

$ManifestPath = Join-Path $EditDir "manifest.json"
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "diagnostics bundle did not contain manifest.json"
}
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ([int]$Manifest.diagnostics_logs.file_count -le 0) {
    throw "synthetic diagnostics manifest must start with a positive file_count"
}
$Manifest.diagnostics_logs.file_count = 0
$Manifest | ConvertTo-Json -Depth 8 |
    Out-File -LiteralPath $ManifestPath -Encoding utf8

Remove-Item -LiteralPath $DiagnosticsZip -Force
Compress-Archive -Path (Join-Path $EditDir "*") -DestinationPath $DiagnosticsZip -Force

$JsonPath = Join-Path $OutputDir "audit-diagnostics-log-count.json"
$MarkdownPath = Join-Path $OutputDir "audit-diagnostics-log-count.md"
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
    throw "audit should reject diagnostics bundle whose manifest reports zero log files, got $($DiagnosticsGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when diagnostics manifest reports zero log files"
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EditDir = Join-Path $OutputDir "diagnostics-log-count-mismatch-edit"
Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $EditDir -Force

$ManifestPath = Join-Path $EditDir "manifest.json"
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$Manifest.diagnostics_logs.file_count = 2
$Manifest | ConvertTo-Json -Depth 8 |
    Out-File -LiteralPath $ManifestPath -Encoding utf8

Remove-Item -LiteralPath $DiagnosticsZip -Force
Compress-Archive -Path (Join-Path $EditDir "*") -DestinationPath $DiagnosticsZip -Force

& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
if (-not $DiagnosticsGate) {
    throw "audit did not emit diagnostics-export gate for mismatched manifest log count"
}
if ($DiagnosticsGate.status -ne "invalid") {
    throw "audit should reject diagnostics bundle whose manifest log count does not match bundled logs, got $($DiagnosticsGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when diagnostics manifest log count does not match bundled logs"
}

Write-Host "Closeout audit rejects diagnostics bundles whose manifest log count is zero or mismatched."
