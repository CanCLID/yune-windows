param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-foreground-evidence-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
$NotepadResult = Join-Path $EvidenceRoot "p2-win01-tsf-smoke\notepad-smoke-result.md"
$ChromiumResult = Join-Path $EvidenceRoot "p2-win01-tsf-smoke\chromium-smoke-result.md"

foreach ($ResultPath in @($NotepadResult, $ChromiumResult)) {
    $Text = Get-Content -Raw -LiteralPath $ResultPath
    $Text = $Text -replace "Foreground target verified before typing: True\r?\n", ""
    $Text | Out-File -LiteralPath $ResultPath -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-foreground-evidence.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-foreground-evidence.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$NotepadGate = $Audit.gates | Where-Object { $_.id -eq "tsf-notepad-smoke" } | Select-Object -First 1
$ChromiumGate = $Audit.gates | Where-Object { $_.id -eq "chromium-text-field-smoke" } | Select-Object -First 1
if ($NotepadGate.status -eq "complete" -or $ChromiumGate.status -eq "complete") {
    throw "closeout audit should reject text-smoke evidence without foreground target proof; got notepad=$($NotepadGate.status), chromium=$($ChromiumGate.status)"
}

Write-Host "Closeout audit rejects text-smoke evidence without foreground target proof."
