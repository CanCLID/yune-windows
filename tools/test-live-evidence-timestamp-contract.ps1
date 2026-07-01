param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-live-evidence-timestamp-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$EvidenceWriters = @(
    "tools\run-m01-live-smoke.ps1",
    "tools\run-notepad-smoke.ps1",
    "tools\run-chromium-smoke.ps1",
    "tools\audit-m01-closeout.ps1"
)

foreach ($RelativePath in $EvidenceWriters) {
    $Path = Join-Path $RepoRoot $RelativePath
    $Source = Get-Content -Raw -LiteralPath $Path
    if ($Source -match 'Date:\s+2026-06-25\.') {
        throw "$RelativePath must not hardcode the M01 evidence date"
    }
    if ($Source -notmatch '\(Get-Date\)\.ToString\("o"\)') {
        throw "$RelativePath must write ISO timestamps with Get-Date.ToString(`"o`")"
    }
}

$AuditJsonPath = Join-Path $OutputDir "audit.json"
$AuditMarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot (Join-Path $OutputDir "evidence") `
    -JsonPath $AuditJsonPath `
    -MarkdownPath $AuditMarkdownPath | Out-Null

$AuditMarkdown = Get-Content -Raw -LiteralPath $AuditMarkdownPath
if ($AuditMarkdown -notmatch 'Date:\s+\d{4}-\d{2}-\d{2}T') {
    throw "closeout audit Markdown must write an ISO timestamped Date field"
}

Write-Host "Live evidence writers use generated ISO timestamps."
