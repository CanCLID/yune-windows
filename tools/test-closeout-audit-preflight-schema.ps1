param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-preflight-schema-test"
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
$JsonPath = Join-Path $OutputDir "audit-preflight-schema.json"
$MarkdownPath = Join-Path $OutputDir "audit-preflight-schema.md"

function Invoke-CompleteSynthetic {
    & (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
        -OutputDir $OutputDir | Out-Null
}

function Invoke-Audit {
    & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Set-PreflightServerProcessCount {
    param(
        [string]$RelativePath,
        [object]$Value
    )

    $Path = Join-Path $EvidenceRoot $RelativePath
    $Report = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $Report.server_process_count = $Value
    $Report | ConvertTo-Json -Depth 8 |
        Out-File -LiteralPath $Path -Encoding utf8
}

function Assert-LivePreflightGateStatus([string]$ExpectedStatus, [string]$CaseName) {
    $Audit = Invoke-Audit
    $Gate = $Audit.gates | Where-Object { $_.id -eq "live-preflight" } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit live-preflight gate for $CaseName"
    }
    if ($Gate.status -ne $ExpectedStatus) {
        $Summary = ($Audit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
        throw "expected live-preflight=$ExpectedStatus for $CaseName, got $($Gate.status): $Summary"
    }
}

Invoke-CompleteSynthetic
Assert-LivePreflightGateStatus "complete" "baseline"
Set-PreflightServerProcessCount `
    -RelativePath "p2-win01-installer\live-preflight.json" `
    -Value "0"
Assert-LivePreflightGateStatus "invalid" "string live server_process_count"

Invoke-CompleteSynthetic
Assert-LivePreflightGateStatus "complete" "install baseline"
Set-PreflightServerProcessCount `
    -RelativePath "p2-win01-installer\install-preflight.json" `
    -Value "0"
Assert-LivePreflightGateStatus "invalid" "string install server_process_count"

Write-Host "Closeout audit rejects preflight server_process_count when it is not a JSON number."
