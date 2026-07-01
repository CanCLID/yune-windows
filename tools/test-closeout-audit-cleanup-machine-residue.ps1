param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-cleanup-machine-residue-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = Join-Path $FixtureDir "evidence"
$PostCleanupStatePath = Join-Path $EvidenceRoot "m01\installer\post-cleanup-state.json"
$PostCleanupState = Get-Content -Raw -LiteralPath $PostCleanupStatePath | ConvertFrom-Json
$PostCleanupState | Add-Member -NotePropertyName machine_state_checked -NotePropertyValue $true -Force
$PostCleanupState | Add-Member -NotePropertyName machine_state_issues -NotePropertyValue @("COM CLSID registry key remains") -Force
$PostCleanupState | Add-Member -NotePropertyName filesystem_leftovers -NotePropertyValue @() -Force
$PostCleanupState | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $PostCleanupStatePath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-dirty-machine.json"
$MarkdownPath = Join-Path $OutputDir "audit-dirty-machine.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$CleanupGate = $Audit.gates | Where-Object { $_.id -eq "uninstall-cleanup" } | Select-Object -First 1
if ($CleanupGate.status -ne "invalid") {
    throw "audit should reject cleanup evidence with recorded machine-state residue, got $($CleanupGate.status)"
}

$PostCleanupState.machine_state_issues = @()
$PostCleanupState.filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
$PostCleanupState | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $PostCleanupStatePath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-dirty-filesystem.json"
$MarkdownPath = Join-Path $OutputDir "audit-dirty-filesystem.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$CleanupGate = $Audit.gates | Where-Object { $_.id -eq "uninstall-cleanup" } | Select-Object -First 1
if ($CleanupGate.status -ne "invalid") {
    throw "audit should reject cleanup evidence with recorded filesystem leftovers, got $($CleanupGate.status)"
}

Write-Host "Closeout audit rejects cleanup evidence with machine-state or filesystem residue."
