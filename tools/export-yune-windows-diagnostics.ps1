param(
    [string]$OutputDir = "",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\diagnostics"
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$StructuralLogDir = Join-Path $InstallDir "logs"
$StructuralLogs = @()
if (Test-Path -LiteralPath $StructuralLogDir) {
    $StructuralLogs = @(Get-ChildItem -LiteralPath $StructuralLogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object Name)
    $ApprovedSmokeInput = "ngohaig"
    $ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))
    $TypedContentFieldPattern = '(?i)(^|\s)(input|raw_input|preedit|typed_text|commit|committed|committed_text|candidate_text|text)=[^\s]+'
    foreach ($LogFile in $StructuralLogs) {
        $LogText = Get-Content -Raw -LiteralPath $LogFile.FullName
        if (($LogText -match [regex]::Escape($ApprovedSmokeInput)) -or
            ($LogText -match [regex]::Escape($ExpectedCommit)) -or
            ($LogText -match $TypedContentFieldPattern)) {
            throw "Refusing diagnostics export because log file contains typed content: $($LogFile.Name)"
        }
    }
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BundleRoot = Join-Path $OutputDir "yune-windows-diagnostics-$Stamp"
$ZipPath = Join-Path $OutputDir "yune-windows-diagnostics-$Stamp.zip"
if (Test-Path -LiteralPath $BundleRoot) {
    Remove-Item -LiteralPath $BundleRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $BundleRoot | Out-Null

function Invoke-GitText([string[]]$Args) {
    try {
        $Output = & git @Args 2>&1
        return ($Output | Out-String).Trim()
    }
    catch {
        return "git command failed: $($_.Exception.Message)"
    }
}

function Relative-Path([string]$Path) {
    $root = [System.IO.Path]::GetFullPath($RepoRoot.Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart("\")
    }
    return $full
}

$EvidenceRoot = Join-Path $RepoRoot "docs\evidence"
$EvidenceFiles = @()
if (Test-Path -LiteralPath $EvidenceRoot) {
    $EvidenceFiles = Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object { Relative-Path $_.FullName }
}
$EvidenceFiles | Out-File -LiteralPath (Join-Path $BundleRoot "evidence-files.txt") -Encoding utf8

Invoke-GitText @("status", "--short", "--branch") |
    Out-File -LiteralPath (Join-Path $BundleRoot "git-status.txt") -Encoding utf8
Invoke-GitText @("rev-parse", "HEAD") |
    Out-File -LiteralPath (Join-Path $BundleRoot "git-head.txt") -Encoding utf8

$ProcessSnapshot = Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, Path, StartTime
$ProcessSnapshot | ConvertTo-Json -Depth 4 |
    Out-File -LiteralPath (Join-Path $BundleRoot "processes.json") -Encoding utf8

$InstallInfoPath = Join-Path $InstallDir "install-info.json"
$InstallInfoPresent = Test-Path -LiteralPath $InstallInfoPath
if ($InstallInfoPresent) {
    Copy-Item -LiteralPath $InstallInfoPath -Destination (Join-Path $BundleRoot "install-info.json") -Force
}

if ($StructuralLogs.Count -gt 0) {
    $BundleLogDir = Join-Path $BundleRoot "logs"
    New-Item -ItemType Directory -Force $BundleLogDir | Out-Null
    foreach ($LogFile in $StructuralLogs) {
        Copy-Item -LiteralPath $LogFile.FullName -Destination (Join-Path $BundleLogDir $LogFile.Name) -Force
    }
}

@(
    "Yune Windows diagnostics export.",
    "Typed-content logs are disabled for this M01 preflight.",
    "Structural TSF logs, when present, contain event names and counts only.",
    "Registry state is not collected by this non-elevated exporter.",
    "Approved install/register cleanup evidence must be captured separately."
) | Out-File -LiteralPath (Join-Path $BundleRoot "notes.txt") -Encoding utf8

$Manifest = [ordered]@{
    product = "Yune Windows"
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    repo = [ordered]@{
        root = $RepoRoot.Path
        head = (Invoke-GitText @("rev-parse", "HEAD"))
        status_file = "git-status.txt"
    }
    evidence = [ordered]@{
        file_count = @($EvidenceFiles).Count
        index_file = "evidence-files.txt"
    }
    machine_state = [ordered]@{
        registry_collected = $false
        install_info_present = $InstallInfoPresent
        process_snapshot_file = "processes.json"
    }
    diagnostics_logs = [ordered]@{
        included = @($StructuralLogs).Count -gt 0
        file_count = @($StructuralLogs).Count
        directory = "logs"
        typed_content_logs = $false
        structural_events_only = $true
    }
    sensitive_context = [ordered]@{
        typed_content_logs = $false
        ai_staging = $false
        learning = $false
    }
}
$Manifest | ConvertTo-Json -Depth 6 |
    Out-File -LiteralPath (Join-Path $BundleRoot "manifest.json") -Encoding utf8

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Compress-Archive -Path (Join-Path $BundleRoot "*") -DestinationPath $ZipPath -Force
Write-Output $ZipPath
