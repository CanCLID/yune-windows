param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-text-smoke-result-line-quality-test"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP "yune-windows"))
if (-not $OutputDir.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to clean output directory outside $AllowedRoot"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"

function Replace-ExactTextSmokeLine {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Line
    )

    $Path = Join-Path $EvidenceRoot $RelativePath
    $Text = Get-Content -Raw -LiteralPath $Path
    $EscapedLine = [regex]::Escape($Line)
    $Mutated = $Text -replace "(?m)^$EscapedLine$", "Previous $Line"
    if ($Mutated -eq $Text) {
        throw "test fixture did not contain exact line '$Line' in $RelativePath"
    }
    $Mutated | Out-File -LiteralPath $Path -Encoding utf8
}

function Assert-TextSmokeGateRejectsWeakLine {
    param(
        [Parameter(Mandatory = $true)][string]$GateId,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Line
    )

    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
    Replace-ExactTextSmokeLine -RelativePath $RelativePath -Line $Line

    $SafeGateId = $GateId -replace '[^A-Za-z0-9_-]', '-'
    $JsonPath = Join-Path $OutputDir "audit-text-smoke-result-line-quality-$SafeGateId.json"
    $MarkdownPath = Join-Path $OutputDir "audit-text-smoke-result-line-quality-$SafeGateId.md"
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
        throw "audit should reject $RelativePath without exact line '$Line', got $($Gate.status)"
    }
    if ($Audit.status -eq "complete") {
        throw "audit must not report complete when $RelativePath lacks exact text-smoke result proof"
    }
}

Assert-TextSmokeGateRejectsWeakLine `
    -GateId "tsf-notepad-smoke" `
    -RelativePath "m01\tsf-smoke\notepad-smoke-result.md" `
    -Line "Foreground target verified before typing: True"

Assert-TextSmokeGateRejectsWeakLine `
    -GateId "chromium-text-field-smoke" `
    -RelativePath "m01\tsf-smoke\chromium-smoke-result.md" `
    -Line "Chromium textarea focus verified before typing: True"

Assert-TextSmokeGateRejectsWeakLine `
    -GateId "chromium-text-field-smoke" `
    -RelativePath "m01\tsf-smoke\chromium-smoke-result.md" `
    -Line "Chromium text-field click verified before typing: True"

Assert-TextSmokeGateRejectsWeakLine `
    -GateId "chromium-text-field-smoke" `
    -RelativePath "m01\tsf-smoke\chromium-smoke-result.md" `
    -Line "Structural event matcher: exact event tokens"

Write-Host "Closeout audit rejects weak text-smoke result-line evidence."
