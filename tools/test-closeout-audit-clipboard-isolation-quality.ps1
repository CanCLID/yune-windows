param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-clipboard-isolation-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$EvidenceRoot = Join-Path $OutputDir "evidence"
foreach ($RelativePath in @(
        "m01\tsf-smoke\notepad-smoke-result.md",
        "m01\tsf-smoke\chromium-smoke-result.md"
    )) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $Text = $Text -replace "(?m)^Clipboard cleared before typing:\s*True\s*\r?\n?", ""
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-clipboard-reset.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-clipboard-reset.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @("tsf-notepad-smoke", "chromium-text-field-smoke")) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId evidence without clipboard-reset proof, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without clipboard-reset proof."

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

foreach ($RelativePath in @(
        "m01\tsf-smoke\notepad-smoke-result.md",
        "m01\tsf-smoke\chromium-smoke-result.md"
    )) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $Text = $Text -replace "(?m)^Clipboard cleared after capture:\s*True\s*\r?\n?", ""
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-clipboard-final-clear.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-clipboard-final-clear.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @("tsf-notepad-smoke", "chromium-text-field-smoke")) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId evidence without post-capture clipboard cleanup proof, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without post-capture clipboard cleanup proof."
