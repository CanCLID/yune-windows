param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-final-result-timestamps-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$JsonPath = Join-Path $OutputDir "audit-final-result-timestamps.json"
$MarkdownPath = Join-Path $OutputDir "audit-final-result-timestamps.md"

function Invoke-CompleteSynthetic {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
}

function Invoke-Audit {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Set-InstallerResultDate([string]$Date) {
    $EvidenceRoot = Join-Path $OutputDir "evidence"
    $ResultPath = Join-Path $EvidenceRoot "p2-win01-installer\result.md"
    $Text = Get-Content -Raw -LiteralPath $ResultPath
    if ($Text -notmatch "(?m)^Date:\s*\S+\s*$") {
        throw "synthetic result.md should contain a Date line"
    }
    $Text = $Text -replace "(?m)^Date:\s*\S+\s*$", "Date: $Date"
    $Text | Out-File -LiteralPath $ResultPath -Encoding utf8
}

Invoke-CompleteSynthetic
Set-InstallerResultDate "2026-06-25T09:00:09.9999999-07:00"
$Audit = Invoke-Audit
$InstallGate = $Audit.gates |
    Where-Object { $_.id -eq "fresh-install-registration-activation" } |
    Select-Object -First 1
if (-not $InstallGate) {
    throw "audit did not emit fresh-install-registration-activation gate"
}
if ($InstallGate.status -ne "invalid") {
    throw "audit should reject final result evidence dated before cleanup-result.md, got $($InstallGate.status)"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when final result evidence predates cleanup-result.md"
}

Write-Host "Closeout audit rejects final result timestamps before cleanup result evidence."
