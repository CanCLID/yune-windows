param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\m09-settings-smoke-$ProcessId"
}

$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
& $BuildScript -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "TSF shell build failed with exit code $LASTEXITCODE"
}

$SettingsExe = Join-Path $OutputDir "YuneWindowsSettings.exe"
if (-not (Test-Path -LiteralPath $SettingsExe -PathType Leaf)) {
    throw "missing built settings executable: $SettingsExe"
}

$Process = Start-Process -FilePath $SettingsExe `
    -ArgumentList "--self-test" `
    -WindowStyle Hidden `
    -PassThru
if (-not $Process.WaitForExit(5000)) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    throw "settings self-test did not exit promptly."
}
if ($Process.ExitCode -ne 0) {
    throw "settings self-test failed with exit code $($Process.ExitCode)."
}

Write-Host "Settings window self-test smoke passed."
