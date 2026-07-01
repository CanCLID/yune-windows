param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-diagnostics-timestamps-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
$JsonPath = Join-Path $OutputDir "diagnostics-timestamps-audit.json"
$MarkdownPath = Join-Path $OutputDir "diagnostics-timestamps-audit.md"
$DiagnosticsZip = Join-Path $EvidenceRoot "m01\settings\registered-session-diagnostics\synthetic.zip"

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

function Set-DiagnosticsManifestGeneratedAt {
    param(
        [string]$GeneratedAt,
        [switch]$Remove
    )

    $ExtractDir = Join-Path $OutputDir "diagnostics-timestamp-edit"
    if (Test-Path -LiteralPath $ExtractDir) {
        Remove-Item -LiteralPath $ExtractDir -Recurse -Force
    }
    Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $ExtractDir -Force

    $ManifestPath = Join-Path $ExtractDir "manifest.json"
    $Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    if ($Remove) {
        $Manifest.PSObject.Properties.Remove("generated_at")
    } elseif ($Manifest.PSObject.Properties.Name -contains "generated_at") {
        $Manifest.generated_at = $GeneratedAt
    } else {
        $Manifest | Add-Member -NotePropertyName "generated_at" -NotePropertyValue $GeneratedAt
    }

    $Manifest | ConvertTo-Json -Depth 6 |
        Out-File -LiteralPath $ManifestPath -Encoding utf8
    Remove-Item -LiteralPath $DiagnosticsZip -Force
    Compress-Archive -Path (Join-Path $ExtractDir "*") -DestinationPath $DiagnosticsZip -Force
}

Invoke-CompleteSynthetic
$BaselineAudit = Invoke-Audit
Assert-GateStatus $BaselineAudit "diagnostics-export" "complete"

Set-DiagnosticsManifestGeneratedAt -Remove
$MissingTimestampAudit = Invoke-Audit
Assert-GateStatus $MissingTimestampAudit "diagnostics-export" "invalid"

Invoke-CompleteSynthetic
Set-DiagnosticsManifestGeneratedAt "2026-06-25T08:59:59.0000000-07:00"
$PreApprovalAudit = Invoke-Audit
Assert-GateStatus $PreApprovalAudit "diagnostics-export" "invalid"

Invoke-CompleteSynthetic
Set-DiagnosticsManifestGeneratedAt "2026-06-25."
$MalformedTimestampAudit = Invoke-Audit
Assert-GateStatus $MalformedTimestampAudit "diagnostics-export" "invalid"

Write-Host "Closeout audit rejects stale diagnostics bundle timestamps."
