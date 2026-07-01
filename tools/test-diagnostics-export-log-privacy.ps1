param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-diagnostics-log-privacy-test"
}

$ExportScript = Join-Path $RepoRoot "tools\export-yune-windows-diagnostics.ps1"
$ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))

function Invoke-LeakCase {
    param(
        [string]$Name,
        [string]$LeakText
    )

    $CaseRoot = Join-Path $OutputDir $Name
    if (Test-Path -LiteralPath $CaseRoot) {
        Remove-Item -LiteralPath $CaseRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force $CaseRoot | Out-Null

    $InstallDir = Join-Path $CaseRoot "install"
    $LogDir = Join-Path $InstallDir "logs"
    New-Item -ItemType Directory -Force $LogDir | Out-Null
    @(
        "event=key_down sequence=1 buffer_length=1 candidate_count=0",
        "event=candidate_update sequence=2 buffer_length=7 candidate_count=5",
        "event=commit_text sequence=3 buffer_length=7 candidate_count=5"
    ) | Out-File -LiteralPath (Join-Path $LogDir "tsf-events.log") -Encoding utf8
    $LeakText | Out-File -LiteralPath (Join-Path $LogDir "debug.log") -Encoding utf8

    $Failed = $false
    try {
        & $ExportScript -OutputDir $CaseRoot -InstallDir $InstallDir | Out-Null
    }
    catch {
        $Failed = $true
        if ($_.Exception.Message -notmatch "typed content") {
            throw "diagnostics exporter rejected leaked log with an unclear message: $($_.Exception.Message)"
        }
    }

    if (-not $Failed) {
        throw "diagnostics exporter should reject bundled logs that contain typed content: $Name"
    }

    $Bundles = @(Get-ChildItem -LiteralPath $CaseRoot -Filter "*.zip" -File -ErrorAction SilentlyContinue)
    if ($Bundles.Count -ne 0) {
        throw "diagnostics exporter should not create a bundle after typed-content log rejection: $Name"
    }

    $BundleDirs = @(Get-ChildItem -LiteralPath $CaseRoot -Filter "yune-windows-diagnostics-*" -Directory -ErrorAction SilentlyContinue)
    if ($BundleDirs.Count -ne 0) {
        throw "diagnostics exporter should not create a bundle directory after typed-content log rejection: $Name"
    }
}

Invoke-LeakCase -Name "input-leak" -LeakText "event=debug sequence=4 input=ngohaig"
Invoke-LeakCase -Name "commit-leak" -LeakText "event=debug sequence=5 committed=$ExpectedCommit"
Invoke-LeakCase -Name "preedit-field-leak" -LeakText "event=debug sequence=6 preedit=secret"
Invoke-LeakCase -Name "typed-text-field-leak" -LeakText "event=debug sequence=7 typed_text=private"
Invoke-LeakCase -Name "candidate-text-field-leak" -LeakText "event=debug sequence=8 candidate_text=private"

Write-Host "Diagnostics exporter rejects typed-content log leakage."
