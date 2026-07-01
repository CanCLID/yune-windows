param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-tsf-$ProcessId"
}

$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Select-String -Path $TsfSource -Pattern "NativeCandidateWindow" -Quiet)) {
    throw "TSF shell is not wired to the native candidate window"
}
if (-not (Select-String -Path $TsfSource -Pattern "ShowCandidates" -Quiet)) {
    throw "TSF shell does not update the candidate window from server candidates"
}
if (-not (Select-String -Path $TsfSource -Pattern "OnSetFocus\(BOOL focused\)" -Quiet)) {
    throw "TSF shell does not name and handle focus transitions for the candidate window"
}
if (-not (Select-String -Path $TsfSource -Pattern "!focused" -Quiet)) {
    throw "TSF shell does not hide the candidate window on focus loss"
}
if (-not (Select-String -Path $TsfSource -Pattern "key >= L'1' && key <= L'9'" -Quiet)) {
    throw "TSF shell does not handle number-key candidate selection"
}
if (-not (Select-String -Path $TsfSource -Pattern "last_candidates_" -Quiet)) {
    throw "TSF shell does not retain candidate rows for number-key selection"
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

Write-Host "TSF shell is wired to the native candidate window and still builds."
