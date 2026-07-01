param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-diagnostics-log-privacy-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
$JsonPath = Join-Path $OutputDir "diagnostics-log-privacy-audit.json"
$MarkdownPath = Join-Path $OutputDir "diagnostics-log-privacy-audit.md"
$DiagnosticsZip = Join-Path $EvidenceRoot "m01\settings\registered-session-diagnostics\synthetic.zip"
$ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))

function Invoke-CompleteSynthetic {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
}

function Invoke-Audit {
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Assert-GateStatus([object]$Audit, [string]$GateId, [string]$ExpectedStatus) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate $GateId"
    }
    if ($Gate.status -ne $ExpectedStatus) {
        throw "expected $GateId=$ExpectedStatus, got $($Gate.status)"
    }
}

function Add-DiagnosticsLeakLog([string]$Text) {
    $ExtractDir = Join-Path $OutputDir "diagnostics-log-privacy-edit"
    if (Test-Path -LiteralPath $ExtractDir) {
        Remove-Item -LiteralPath $ExtractDir -Recurse -Force
    }
    Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $ExtractDir -Force

    $LogDir = Join-Path $ExtractDir "logs"
    New-Item -ItemType Directory -Force $LogDir | Out-Null
    $Text | Out-File -LiteralPath (Join-Path $LogDir "leaked-content.log") -Encoding utf8

    Remove-Item -LiteralPath $DiagnosticsZip -Force
    Compress-Archive -Path (Join-Path $ExtractDir "*") -DestinationPath $DiagnosticsZip -Force
}

Invoke-CompleteSynthetic
$BaselineAudit = Invoke-Audit
Assert-GateStatus $BaselineAudit "diagnostics-export" "complete"

Add-DiagnosticsLeakLog "event=debug sequence=4 input=ngohaig"
$InputLeakAudit = Invoke-Audit
Assert-GateStatus $InputLeakAudit "diagnostics-export" "invalid"

Invoke-CompleteSynthetic
Add-DiagnosticsLeakLog "event=debug sequence=5 committed=$ExpectedCommit"
$CommitLeakAudit = Invoke-Audit
Assert-GateStatus $CommitLeakAudit "diagnostics-export" "invalid"

Invoke-CompleteSynthetic
Add-DiagnosticsLeakLog "event=debug sequence=6 preedit=secret"
$TypedFieldLeakAudit = Invoke-Audit
Assert-GateStatus $TypedFieldLeakAudit "diagnostics-export" "invalid"

Write-Host "Closeout audit rejects diagnostics bundles with typed-content log leakage."
