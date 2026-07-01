param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-status-line-quality-test"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP "yune-windows"))
if (-not $OutputDir.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to clean output directory outside $AllowedRoot"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"

function Replace-ExactPassedStatusLine {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $Mutated = $Text -replace '(?m)^Status: passed$', 'Previous Status: passed'
    if ($Mutated -eq $Text) {
        throw "test fixture did not contain an exact Status: passed line: $RelativePath"
    }
    $Mutated | Out-File -LiteralPath $Path -Encoding utf8
}

function Assert-GateRejectsWeakStatusLine {
    param(
        [Parameter(Mandatory = $true)][string]$GateId,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
    Replace-ExactPassedStatusLine -RelativePath $RelativePath

    $SafeGateId = $GateId -replace '[^A-Za-z0-9_-]', '-'
    $JsonPath = Join-Path $OutputDir "audit-status-line-quality-$SafeGateId.json"
    $MarkdownPath = Join-Path $OutputDir "audit-status-line-quality-$SafeGateId.md"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null

    $Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $RelativePath without an exact Status: passed line, got $($Gate.status)"
    }
    if ($Audit.status -eq "complete") {
        throw "audit must not report complete when $RelativePath lacks an exact Status: passed line"
    }
}

Assert-GateRejectsWeakStatusLine `
    -GateId "tsf-notepad-smoke" `
    -RelativePath "m01\tsf-smoke\notepad-smoke-result.md"
Assert-GateRejectsWeakStatusLine `
    -GateId "chromium-text-field-smoke" `
    -RelativePath "m01\tsf-smoke\chromium-smoke-result.md"
Assert-GateRejectsWeakStatusLine `
    -GateId "fresh-install-registration-activation" `
    -RelativePath "m01\installer\result.md"
Assert-GateRejectsWeakStatusLine `
    -GateId "uninstall-cleanup" `
    -RelativePath "m01\installer\cleanup-result.md"

Write-Host "Closeout audit rejects weak result status-line evidence."
