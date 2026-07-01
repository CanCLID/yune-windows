param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-failed-app-smoke-result-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

function Set-FailedAppSmokeResult {
    param(
        [string]$EvidenceRoot,
        [string]$RelativePath
    )

    $Path = Join-Path $EvidenceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing app-smoke result fixture: $RelativePath"
    }

    $Text = Get-Content -Raw -LiteralPath $Path
    if ($Text -notmatch "Pass:\s*True") {
        throw "app-smoke fixture must start with pass markers so this test isolates Status: failed"
    }
    $Text = $Text -replace "(Date:\s*\d{4}-\d{2}-\d{2}T\S+\s*)", "`$1`r`nStatus: failed`r`n`r`nFailure stage: cleanup`r`n"
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

function Invoke-FailedAppSmokeCase {
    param(
        [string]$Name,
        [string]$RelativeResultPath,
        [string]$GateId
    )

    $CaseDir = Join-Path $OutputDir $Name
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $CaseDir

    $EvidenceRoot = Join-Path $CaseDir "evidence"
    Set-FailedAppSmokeResult `
        -EvidenceRoot $EvidenceRoot `
        -RelativePath $RelativeResultPath

    $JsonPath = Join-Path $CaseDir "audit-failed-app-smoke.json"
    $MarkdownPath = Join-Path $CaseDir "audit-failed-app-smoke.md"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath

    $Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit gate: $GateId"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $RelativeResultPath with Status: failed, got $($Gate.status)"
    }
    if ($Audit.status -eq "complete") {
        throw "audit must not report complete when $RelativeResultPath has Status: failed"
    }
}

Invoke-FailedAppSmokeCase `
    -Name "notepad" `
    -RelativeResultPath "m01\tsf-smoke\notepad-smoke-result.md" `
    -GateId "tsf-notepad-smoke"

Invoke-FailedAppSmokeCase `
    -Name "chromium" `
    -RelativeResultPath "m01\tsf-smoke\chromium-smoke-result.md" `
    -GateId "chromium-text-field-smoke"

Write-Host "Closeout audit rejects failed app-smoke result evidence even when pass markers remain."
