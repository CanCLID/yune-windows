param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-output-dir-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $OutputDir "evidence"))
$JsonPath = Join-Path $OutputDir "audit.json"
$MarkdownPath = Join-Path $OutputDir "audit.md"
$CommandsPath = Join-Path $EvidenceRoot "p2-win01-installer\commands.txt"

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$Commands = Get-Content -Raw -LiteralPath $CommandsPath
$Commands = $Commands -replace "\s-OutputDir\s+'[^']*registered-session-diagnostics'", ""
$Commands | Out-File -LiteralPath $CommandsPath -Encoding utf8

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
    throw "audit should reject registered-session diagnostics unless the export transcript records the output directory, got $($DiagnosticsGate.status)"
}

Write-Host "Closeout audit rejects registered-session diagnostics without an output-directory transcript."
