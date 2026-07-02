param(
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [string]$InstallDir = "",
    [string]$OutputDir = "",
    [int]$Tail = 160
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($InstallDir -eq "") {
    $InstallDir = Join-Path $env:LOCALAPPDATA "Yune\WindowsIme"
}
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $RepoRoot "docs\evidence\m06\logs"
}

$SafeLabel = ($Label -replace '[^A-Za-z0-9._-]', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($SafeLabel)) {
    throw "label must contain at least one filename-safe character"
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$LogPath = Join-Path $InstallDir "logs\tsf-events.log"
$OutputPath = Join-Path $OutputDir "$SafeLabel-tsf-events.md"

$Lines = @()
if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
    $Lines = [string[]]@(Get-Content -LiteralPath $LogPath -Tail $Tail |
        ForEach-Object { [string]$_ })
}

New-Item -ItemType Directory -Force $OutputDir | Out-Null
$CapturedAt = (Get-Date).ToString("o")
$FullLogPath = [System.IO.Path]::GetFullPath($LogPath)
$LogExists = Test-Path -LiteralPath $LogPath -PathType Leaf
@(
    "# M06 TSF Events Window - $Label",
    "",
    "- Captured at: $CapturedAt",
    "- Source log: $FullLogPath",
    "- Source exists: $LogExists",
    "- Tail lines: $(@($Lines).Count)",
    "",
    '```text'
) + $Lines + @(
    '```'
) | Out-File -LiteralPath $OutputPath -Encoding utf8

Write-Output $OutputPath
