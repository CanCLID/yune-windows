param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Get-SourceSlice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$StartText,
        [Parameter(Mandatory = $true)]
        [string]$EndText,
        [string]$Context = "source"
    )

    $Start = $Source.IndexOf($StartText)
    if ($Start -lt 0) {
        throw "$Context is missing block start: $StartText"
    }
    $End = $Source.IndexOf($EndText, $Start)
    if ($End -lt $Start) {
        throw "$Context is missing block end: $EndText"
    }
    return $Source.Substring($Start, ($End + $EndText.Length) - $Start)
}

foreach ($Smoke in @(
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $Smoke
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing smoke script: $Smoke"
    }

    $Source = Get-Content -Raw -LiteralPath $Path
    foreach ($Required in @(
            '$StructuralLogBaselineCaptured = $false',
            'function Update-StructuralSmokeEvidence',
            'if (-not $script:StructuralLogBaselineCaptured)',
            '$script:NewStructuralLogLines = @(Get-NewStructuralLogLines',
            'Test-StructuralEventLine -Line $_ -EventName "candidate_window_failed"'
        )) {
        if (-not $Source.Contains($Required)) {
            throw "$Smoke must support refreshing structural evidence on failure: $Required"
        }
    }

    if ($Source -notmatch '\$StructuralLogStartLineCount\s*=\s*Get-StructuralLogLineCount(?s:.*?)\$StructuralLogBaselineCaptured\s*=\s*\$true') {
        throw "$Smoke must mark the structural-log baseline immediately after capturing its starting line count."
    }

    $GenericFailureBlock = Get-SourceSlice `
        -Source $Source `
        -StartText 'if (-not $ResultWritten)' `
        -EndText 'Write-TextSmokeResult' `
        -Context "$Smoke generic failure"
    if ($GenericFailureBlock -notmatch 'Update-StructuralSmokeEvidence') {
        throw "$Smoke generic failure path must refresh structural log evidence before writing failed result evidence."
    }

    $CleanupFailureBlock = Get-SourceSlice `
        -Source $Source `
        -StartText 'if ($CleanupErrors.Count -gt 0)' `
        -EndText 'Write-TextSmokeResult' `
        -Context "$Smoke cleanup failure"
    if ($CleanupFailureBlock -notmatch 'Update-StructuralSmokeEvidence') {
        throw "$Smoke cleanup failure path must refresh structural log evidence before rewriting failed cleanup evidence."
    }
}

Write-Host "Live app-smoke failure paths refresh structural TSF evidence before writing failed results."
