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

function Get-PeSubsystem([string]$Path) {
    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -lt 256) {
        throw "PE image is too small: $Path"
    }
    $PeOffset = [BitConverter]::ToInt32($Bytes, 0x3c)
    if ($PeOffset -lt 0 -or $PeOffset + 0x5a -ge $Bytes.Length) {
        throw "PE header offset is invalid: $Path"
    }
    if ($Bytes[$PeOffset] -ne 0x50 -or $Bytes[$PeOffset + 1] -ne 0x45 -or
        $Bytes[$PeOffset + 2] -ne 0 -or $Bytes[$PeOffset + 3] -ne 0) {
        throw "PE signature is invalid: $Path"
    }
    $OptionalHeaderOffset = $PeOffset + 24
    return [BitConverter]::ToUInt16($Bytes, $OptionalHeaderOffset + 0x44)
}

$Subsystem = Get-PeSubsystem $SettingsExe
if ($Subsystem -ne 2) {
    throw "settings executable PE subsystem is $Subsystem, expected 2 (Windows GUI)."
}

foreach ($Arguments in @(
        @("--self-test"),
        @("--layout-smoke-dpi", "96"),
        @("--layout-smoke-dpi", "120"),
        @("--layout-smoke-dpi", "144"),
        @("--layout-smoke-dpi", "192")
    )) {
    $Mode = $Arguments -join " "
    $Process = Start-Process -FilePath $SettingsExe `
        -ArgumentList $Arguments `
        -WindowStyle Hidden `
        -PassThru
    if (-not $Process.WaitForExit(5000)) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        throw "settings $Mode did not exit promptly."
    }
    if ($Process.ExitCode -ne 0) {
        throw "settings $Mode failed with exit code $($Process.ExitCode)."
    }
}

$InvalidDpi = Start-Process -FilePath $SettingsExe `
    -ArgumentList @("--layout-smoke-dpi", "97") `
    -WindowStyle Hidden `
    -PassThru
if (-not $InvalidDpi.WaitForExit(5000)) {
    $InvalidDpi.Kill()
    throw "settings layout smoke accepted unsupported DPI or hung"
}
if ($InvalidDpi.ExitCode -ne 2) {
    throw "settings layout smoke accepted unsupported DPI 97"
}

Write-Host "Settings self-test and 100/125/150/200% layout smokes passed."
