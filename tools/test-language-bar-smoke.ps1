param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\m08-language-bar-smoke-$ProcessId"
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "TSF shell build failed with exit code $LASTEXITCODE"
}

$SmokeExe = Join-Path $OutputDir "YuneWindowsLanguageBarSmoke.exe"
if (-not (Test-Path -LiteralPath $SmokeExe -PathType Leaf)) {
    throw "missing language-bar smoke executable: $SmokeExe"
}

& $SmokeExe --self-test
if ($LASTEXITCODE -ne 0) {
    throw "language-bar smoke failed with exit code $LASTEXITCODE"
}

Write-Host "Language-bar D2D/no-activate smoke passed."
