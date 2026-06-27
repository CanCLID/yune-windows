param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-text-smoke-profile-state-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null
Add-Type -AssemblyName System.Drawing

function Write-EvidenceFile([string]$RelativePath, [string]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Content | Out-File -LiteralPath $Path -Encoding utf8
}

function Write-EvidenceBytes([string]$RelativePath, [byte[]]$Content) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllBytes($Path, $Content)
}

function New-TestPngBytes([System.Drawing.Color]$Color) {
    $Bitmap = [System.Drawing.Bitmap]::new(640, 360)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $Stream = [System.IO.MemoryStream]::new()
    try {
        $Graphics.Clear($Color)
        $Bitmap.Save($Stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $Stream.ToArray()
    }
    finally {
        $Stream.Dispose()
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
}

function Write-PassingTextSmoke([string]$Name, [string]$Title) {
    $ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))
    Write-EvidenceFile "p2-win01-tsf-smoke\$Name-smoke-result.md" @"
# $Title

Observed clipboard text after select-all/copy:

````text
$ExpectedCommit
````

Pass: True
Raw ASCII observed: False
Matches expected Yune commit: True
"@
}

$CandidatePng = New-TestPngBytes ([System.Drawing.Color]::White)
$CommitPng = New-TestPngBytes ([System.Drawing.Color]::LightGray)

Write-PassingTextSmoke "notepad" "Notepad Smoke"
Write-PassingTextSmoke "chromium" "Chromium Smoke"
Write-EvidenceBytes "p2-win01-tsf-smoke\candidate-display-notepad.png" $CandidatePng
Write-EvidenceBytes "p2-win01-tsf-smoke\notepad-commit.png" $CommitPng
Write-EvidenceBytes "p2-win01-tsf-smoke\candidate-display-chromium.png" $CandidatePng
Write-EvidenceBytes "p2-win01-tsf-smoke\chromium-commit.png" $CommitPng

Write-EvidenceFile "p2-win01-tsf-smoke\chromium-post-state.json" @"
{
  "install_dir": "C:\\Users\\example\\AppData\\Local\\YuneWindows\\WindowsIme",
  "install_dir_exists": true,
  "profile_tool_exists": true,
  "profile_state_verified": true,
  "profile_state": "{\"registered\":true,\"active\":false}",
  "server_processes": []
}
"@

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$ExpectedInvalid = @(
    "tsf-notepad-smoke",
    "chromium-text-field-smoke"
)
foreach ($GateId in $ExpectedInvalid) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId without that app's active installed profile state, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without app-specific active profile state."

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

$NotepadPostStatePath = Join-Path $EvidenceRoot "p2-win01-tsf-smoke\notepad-post-state.json"
$ChromiumPostStatePath = Join-Path $EvidenceRoot "p2-win01-tsf-smoke\chromium-post-state.json"
$NotepadPostState = Get-Content -Raw -LiteralPath $NotepadPostStatePath | ConvertFrom-Json
$ChromiumPostState = Get-Content -Raw -LiteralPath $ChromiumPostStatePath | ConvertFrom-Json
$NotepadPostState.captured_at = "2026-06-25T09:11:00.0000000-07:00"
$ChromiumPostState.captured_at = "2026-06-25T09:11:00.0000000-07:00"
$NotepadPostState | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $NotepadPostStatePath -Encoding utf8
$ChromiumPostState | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $ChromiumPostStatePath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-with-post-state-after-result.json"
$MarkdownPath = Join-Path $OutputDir "audit-with-post-state-after-result.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @("tsf-notepad-smoke", "chromium-text-field-smoke")) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId when app post-state is captured after the smoke result, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence when app post-state is newer than the smoke result."

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir

foreach ($RelativePath in @(
        "p2-win01-tsf-smoke\notepad-smoke-result.md",
        "p2-win01-tsf-smoke\chromium-smoke-result.md"
    )) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $Text = $Text -replace "(?m)^Active profile verified before typing:\s*True\s*\r?\n?", ""
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

$JsonPath = Join-Path $OutputDir "audit-without-active-profile-result-proof.json"
$MarkdownPath = Join-Path $OutputDir "audit-without-active-profile-result-proof.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
foreach ($GateId in @("tsf-notepad-smoke", "chromium-text-field-smoke")) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId without active-profile result proof, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence without active-profile result proof."
