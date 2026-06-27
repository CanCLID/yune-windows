param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-tsf-$ProcessId"
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$SmokeExe = Join-Path $OutputDir "YuneWindowsCandidateWindowSmoke.exe"
if (-not (Test-Path -LiteralPath $SmokeExe)) {
    throw "missing candidate-window smoke executable: $SmokeExe"
}

$Output = & $SmokeExe --self-test 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "candidate-window smoke failed with exit code $LASTEXITCODE. Output: $Output"
}

$Text = $Output | Out-String
if ($Text -notmatch "candidate window smoke passed") {
    throw "candidate-window smoke did not report success. Output: $Text"
}

Write-Host $Text.Trim()
