param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-tsf-$ProcessId"
}

$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
if (-not (Test-Path -LiteralPath $BuildScript)) {
    throw "missing TSF build script: $BuildScript"
}

& $BuildScript -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "TSF build failed with exit code $LASTEXITCODE"
}

$Dll = Join-Path $OutputDir "YuneWindowsTSF.dll"
if (-not (Test-Path -LiteralPath $Dll)) {
    throw "missing built TSF DLL: $Dll"
}

$Server = Join-Path $OutputDir "YuneWindowsServer.exe"
if (-not (Test-Path -LiteralPath $Server)) {
    throw "missing built shared server: $Server"
}

$ProfileTool = Join-Path $OutputDir "YuneWindowsProfileTool.exe"
if (-not (Test-Path -LiteralPath $ProfileTool)) {
    throw "missing built profile tool: $ProfileTool"
}

$CandidateSmoke = Join-Path $OutputDir "YuneWindowsCandidateWindowSmoke.exe"
if (-not (Test-Path -LiteralPath $CandidateSmoke)) {
    throw "missing built candidate-window smoke executable: $CandidateSmoke"
}

Write-Host "TSF shell build produced $Dll, $Server, $ProfileTool, and $CandidateSmoke"
