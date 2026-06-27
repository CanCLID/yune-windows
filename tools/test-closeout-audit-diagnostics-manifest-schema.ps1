param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-manifest-schema-test"
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
$DiagnosticsZip = Join-Path $EvidenceRoot "p2-win01-settings\registered-session-diagnostics\synthetic.zip"
$JsonPath = Join-Path $OutputDir "audit-diagnostics-manifest-schema.json"
$MarkdownPath = Join-Path $OutputDir "audit-diagnostics-manifest-schema.md"

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

function Set-DiagnosticsManifestProperty {
    param(
        [string[]]$Path,
        [object]$Value
    )

    $ExtractDir = Join-Path $OutputDir "diagnostics-manifest-schema-edit"
    if (Test-Path -LiteralPath $ExtractDir) {
        Remove-Item -LiteralPath $ExtractDir -Recurse -Force
    }
    Expand-Archive -LiteralPath $DiagnosticsZip -DestinationPath $ExtractDir -Force

    $ManifestPath = Join-Path $ExtractDir "manifest.json"
    $Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    $Target = $Manifest
    for ($Index = 0; $Index -lt ($Path.Count - 1); $Index++) {
        $Target = $Target.($Path[$Index])
    }
    $Target.($Path[-1]) = $Value

    $Manifest | ConvertTo-Json -Depth 8 |
        Out-File -LiteralPath $ManifestPath -Encoding utf8
    Remove-Item -LiteralPath $DiagnosticsZip -Force
    Compress-Archive -Path (Join-Path $ExtractDir "*") -DestinationPath $DiagnosticsZip -Force
}

function Assert-DiagnosticsGateStatus([string]$ExpectedStatus, [string]$CaseName) {
    $Audit = Invoke-Audit
    $DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" } | Select-Object -First 1
    if (-not $DiagnosticsGate) {
        throw "audit did not emit diagnostics-export gate for $CaseName"
    }
    if ($DiagnosticsGate.status -ne $ExpectedStatus) {
        $Summary = ($Audit.gates | ForEach-Object { "$($_.id)=$($_.status)" }) -join ", "
        throw "expected diagnostics-export=$ExpectedStatus for $CaseName, got $($DiagnosticsGate.status): $Summary"
    }
}

$SchemaCases = @(
    @{
        name = "string diagnostics log count"
        path = @("diagnostics_logs", "file_count")
        value = "1"
    },
    @{
        name = "string diagnostics included flag"
        path = @("diagnostics_logs", "included")
        value = "true"
    },
    @{
        name = "string diagnostics typed-content flag"
        path = @("diagnostics_logs", "typed_content_logs")
        value = "false"
    },
    @{
        name = "string diagnostics structural-only flag"
        path = @("diagnostics_logs", "structural_events_only")
        value = "true"
    },
    @{
        name = "string sensitive typed-content flag"
        path = @("sensitive_context", "typed_content_logs")
        value = "false"
    },
    @{
        name = "string sensitive AI staging flag"
        path = @("sensitive_context", "ai_staging")
        value = "false"
    },
    @{
        name = "string machine registry-collected flag"
        path = @("machine_state", "registry_collected")
        value = "false"
    }
)

foreach ($Case in $SchemaCases) {
    Invoke-CompleteSynthetic
    Assert-DiagnosticsGateStatus "complete" "$($Case.name) baseline"
    Set-DiagnosticsManifestProperty -Path $Case.path -Value $Case.value
    Assert-DiagnosticsGateStatus "invalid" $Case.name
}

Write-Host "Closeout audit rejects loosely typed diagnostics manifest schema fields."
