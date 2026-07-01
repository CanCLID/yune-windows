param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-structural-line-count-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
$NotepadResult = Join-Path $EvidenceRoot "m01\tsf-smoke\notepad-smoke-result.md"
$ChromiumResult = Join-Path $EvidenceRoot "m01\tsf-smoke\chromium-smoke-result.md"

foreach ($ResultPath in @($NotepadResult, $ChromiumResult)) {
    $Text = Get-Content -Raw -LiteralPath $ResultPath
    $Text = $Text -replace "Structural new log lines: 3", "Structural new log lines: 0"
    $Text | Out-File -LiteralPath $ResultPath -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-structural-line-count.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-structural-line-count.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$NotepadGate = $Audit.gates | Where-Object { $_.id -eq "tsf-notepad-smoke" } | Select-Object -First 1
$ChromiumGate = $Audit.gates | Where-Object { $_.id -eq "chromium-text-field-smoke" } | Select-Object -First 1
if ($NotepadGate.status -eq "complete" -or $ChromiumGate.status -eq "complete") {
    throw "closeout audit should reject text-smoke evidence without positive structural line count; got notepad=$($NotepadGate.status), chromium=$($ChromiumGate.status)"
}

Write-Host "Closeout audit rejects text-smoke evidence without positive structural line count."
