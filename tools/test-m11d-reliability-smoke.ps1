param(
    [string]$OutputDir = "",
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\m11d-reliability-$ProcessId"
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") `
    -OutputDir $OutputDir `
    -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) {
    throw "TSF shell build failed with exit code $LASTEXITCODE"
}

$Smoke = Join-Path $OutputDir "YuneWindowsReliabilitySmoke.exe"
if (-not (Test-Path -LiteralPath $Smoke -PathType Leaf)) {
    throw "missing M11D reliability smoke executable: $Smoke"
}

& $Smoke
if ($LASTEXITCODE -ne 0) {
    throw "M11D reliability smoke failed with exit code $LASTEXITCODE"
}

Write-Host "M11D token and parity reliability smoke passed."
