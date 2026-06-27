param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$PackageDir = "",
    [string]$SharedDataDir = "",
    [string]$UserDataDir = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($PackageDir -eq "") {
    $PackageDir = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist"
}
$SourceSchemaDir = Join-Path $YuneRoot "apps\yune-web\public\schema"
$PrepareProductData = $false
if ($SharedDataDir -eq "") {
    $SharedDataDir = Join-Path $env:TEMP "yune-windows\p2-win01-yune-host\schema"
    $PrepareProductData = $true
}
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $RepoRoot "docs\evidence\p2-win01-yune-host"
}
if ($UserDataDir -eq "") {
    $UserDataDir = Join-Path $env:TEMP "yune-windows\p2-win01-yune-host\user"
}

$RimeDll = Join-Path $PackageDir "lib\rime.dll"
$IncludeDir = Join-Path $PackageDir "include"
$Source = Join-Path $RepoRoot "src\host\yune_host_smoke.cpp"
$BuildDir = Join-Path $env:TEMP "yune-windows\p2-win01-yune-host\build"
$Exe = Join-Path $BuildDir "yune_host_smoke.exe"
$Obj = Join-Path $BuildDir "yune_host_smoke.obj"
$ResultPath = Join-Path $OutputDir "result.json"
$CommandsPath = Join-Path $OutputDir "commands.txt"

if (-not (Test-Path -LiteralPath $RimeDll)) {
    throw "missing packaged rime.dll: $RimeDll"
}
if (-not (Test-Path -LiteralPath (Join-Path $IncludeDir "rime_yune_windows_profile_api.h"))) {
    throw "missing YuneWindows profile header in package include dir: $IncludeDir"
}
if ($PrepareProductData -and -not (Test-Path -LiteralPath $SourceSchemaDir)) {
    throw "missing source schema data dir: $SourceSchemaDir"
}
if (-not $PrepareProductData -and -not (Test-Path -LiteralPath $SharedDataDir)) {
    throw "missing shared schema data dir: $SharedDataDir"
}

function Find-VsDevCmd {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"),
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw "missing VsDevCmd.bat; install Visual Studio C++ tools"
}

if ($PrepareProductData) {
    & (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
        -SourceSchemaDir $SourceSchemaDir `
        -DestinationSchemaDir $SharedDataDir `
        -UserDataDir $UserDataDir
}

New-Item -ItemType Directory -Force $BuildDir, $OutputDir, (Join-Path $UserDataDir "build") | Out-Null
Remove-Item -LiteralPath $ResultPath -Force -ErrorAction SilentlyContinue

$VsDevCmd = Find-VsDevCmd
$Compile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /I `"$IncludeDir`" /Fo`"$Obj`" /Fe`"$Exe`" `"$Source`""
$CompileForLog = "cmd.exe /d /s /c '$Compile'"
cmd.exe /d /s /c "$Compile"
if ($LASTEXITCODE -ne 0) {
    throw "host compile failed with exit code $LASTEXITCODE"
}

$RunArgs = @(
    "--rime-dll", $RimeDll,
    "--shared-dir", $SharedDataDir,
    "--user-dir", $UserDataDir,
    "--output", $ResultPath,
    "--schema", "jyut6ping3",
    "--input", "ngohaig",
    "--sensitive"
)

& $Exe @RunArgs
if ($LASTEXITCODE -ne 0) {
    throw "host smoke executable failed with exit code $LASTEXITCODE"
}

$CommandLog = @(
    "# Yune Host Smoke Commands",
    "",
    "Date: $(Get-Date -Format o)",
    "",
    "No elevated command, TSF registration, installer, registry, AppVerifier, PageHeap, unregister, or cleanup command was run.",
    "",
    "Repo root: $RepoRoot",
    "Yune root: $YuneRoot",
    "Package dir: $PackageDir",
    "Shared data dir: $SharedDataDir",
    "User data dir: $UserDataDir",
    "Result: $ResultPath",
    "",
    "Build:",
    $CompileForLog,
    "",
    "Run:",
    "$Exe $($RunArgs -join ' ')",
    ""
)
Set-Content -LiteralPath $CommandsPath -Encoding ASCII -Value $CommandLog

Write-Host "Yune host smoke result: $ResultPath"
