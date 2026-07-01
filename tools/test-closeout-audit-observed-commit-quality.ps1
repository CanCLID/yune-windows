param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-observed-commit-quality-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null

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

$ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))

function New-TestPngBytes {
    Add-Type -AssemblyName System.Drawing
    $Bitmap = [System.Drawing.Bitmap]::new(640, 360)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $Stream = [System.IO.MemoryStream]::new()
    try {
        $Graphics.Clear([System.Drawing.Color]::White)
        $Bitmap.Save($Stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $Stream.ToArray()
    }
    finally {
        $Stream.Dispose()
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
}

$ValidPng = New-TestPngBytes

Write-EvidenceFile "m01\bootstrap\repo-state.md" "repo state"
Write-EvidenceFile "m01\bootstrap\reference-audit.md" "reference audit"
Write-EvidenceFile "m01\bootstrap\process-model.md" "process model"
Write-EvidenceFile "m01\bootstrap\first-smoke-target.md" "first smoke"
Write-EvidenceFile "m01\yune-host\result.json" '{"status": {"schema_id": "jyut6ping3"}}'
Write-EvidenceFile "m01\tsf-smoke\server-ipc-smoke.md" "server ipc smoke"
Write-EvidenceFile "m01\candidate-window\build-preflight.md" "candidate preflight"
Write-EvidenceFile "m01\settings\diagnostics-export.md" "diagnostics preflight"
Write-EvidenceFile "m01\settings\webview2-spike.md" 'Decision: `defer-settings`'
Write-EvidenceFile "m01\tsf-smoke\machine-state-gates.md" "approval gates"
Write-EvidenceFile "m01\installer\live-preflight.json" '{"machine_state_changed": false}'
Write-EvidenceFile "m01\installer\install-preflight.json" '{"machine_state_changed": false}'

foreach ($Name in @("notepad", "chromium")) {
    $Title = if ($Name -eq "notepad") { "Notepad Smoke" } else { "Chromium Smoke" }
    $ResultFile = if ($Name -eq "notepad") { "notepad-smoke-result.md" } else { "chromium-smoke-result.md" }
    Write-EvidenceFile "m01\tsf-smoke\$ResultFile" @"
# $Title

Expected committed text:

````text
$ExpectedCommit
````

Observed clipboard text after select-all/copy:

````text
wrong-non-raw-text
````

Pass: True

Raw ASCII observed: False

Matches expected Yune commit: True
"@
}
Write-EvidenceBytes "m01\tsf-smoke\candidate-display-notepad.png" $ValidPng
Write-EvidenceBytes "m01\tsf-smoke\notepad-commit.png" $ValidPng
Write-EvidenceBytes "m01\tsf-smoke\candidate-display-chromium.png" $ValidPng
Write-EvidenceBytes "m01\tsf-smoke\chromium-commit.png" $ValidPng

$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
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
        throw "audit should reject $GateId evidence when observed clipboard text is not the expected Yune commit, got $($Gate.status)"
    }
}

Write-Host "Closeout audit rejects text-smoke evidence when observed text is not the expected Yune commit."
