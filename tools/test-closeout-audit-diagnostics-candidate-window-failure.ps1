param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-candidate-window-failure-test"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
$ZipPath = Join-Path $EvidenceRoot "p2-win01-settings\registered-session-diagnostics\synthetic.zip"
$ExpandedDir = Join-Path $OutputDir "expanded-diagnostics"
Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExpandedDir -Force
Add-Content `
    -LiteralPath (Join-Path $ExpandedDir "logs\tsf-events.log") `
    -Value "event=candidate_window_failed sequence=4 buffer_length=7 candidate_count=5"
Remove-Item -LiteralPath $ZipPath -Force
Compress-Archive -Path (Join-Path $ExpandedDir "*") -DestinationPath $ZipPath -Force

$JsonPath = Join-Path $OutputDir "audit-with-diagnostics-candidate-window-failure.json"
$MarkdownPath = Join-Path $OutputDir "audit-with-diagnostics-candidate-window-failure.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$Gate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
if (-not $Gate) {
    throw "audit did not emit diagnostics-export gate"
}
if ($Gate.status -ne "invalid") {
    throw "audit should reject diagnostics containing candidate_window_failed, got $($Gate.status)"
}

Write-Host "Closeout audit rejects diagnostics bundles containing candidate_window_failed."
