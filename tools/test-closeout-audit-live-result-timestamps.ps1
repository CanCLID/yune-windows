param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-live-result-timestamps-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"
$JsonPath = Join-Path $OutputDir "timestamp-audit.json"
$MarkdownPath = Join-Path $OutputDir "timestamp-audit.md"

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

function Set-ResultDate([string]$RelativePath, [string]$DateLine) {
    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    if ($Text -match '(?m)^Date:') {
        $Text = [regex]::Replace($Text, '(?m)^Date:.*$', $DateLine, 1)
    } else {
        $Text = "$DateLine`r`n`r`n$Text"
    }
    $Text | Out-File -LiteralPath $Path -Encoding utf8
}

function Set-StaleResultDate([string]$RelativePath) {
    Set-ResultDate $RelativePath "Date: 2026-06-25."
}

$Cases = @(
    @{
        path = "m01\tsf-smoke\notepad-smoke-result.md"
        gates = @("tsf-notepad-smoke", "candidate-display-live")
    },
    @{
        path = "m01\tsf-smoke\chromium-smoke-result.md"
        gates = @("chromium-text-field-smoke", "candidate-display-live")
    },
    @{
        path = "m01\installer\result.md"
        gates = @("fresh-install-registration-activation")
    },
    @{
        path = "m01\installer\cleanup-result.md"
        gates = @("uninstall-cleanup")
    }
)

foreach ($Case in $Cases) {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
    Set-StaleResultDate $Case.path
    $Audit = Invoke-Audit
    foreach ($GateId in $Case.gates) {
        Assert-GateStatus $Audit $GateId "invalid"
    }
}

foreach ($Case in $Cases) {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
    Set-ResultDate $Case.path "Date: 2026-06-25T08:59:59.0000000-07:00"
    $Audit = Invoke-Audit
    foreach ($GateId in $Case.gates) {
        Assert-GateStatus $Audit $GateId "invalid"
    }
}

Write-Host "Closeout audit rejects stale live-result timestamps."
