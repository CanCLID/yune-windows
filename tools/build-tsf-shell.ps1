param(
    [string]$OutputDir = "",
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-tsf-$ProcessId"
}

$PackageDir = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist"
$IncludeDir = Join-Path $PackageDir "include"
$ServerSource = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$ProfileToolSource = Join-Path $RepoRoot "src\tools\yune_windows_profile_tool.cpp"
$SettingsToolSource = Join-Path $RepoRoot "src\tools\yune_windows_settings.cpp"
$CandidateWindowSource = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.cpp"
$CandidateWindowSmokeSource = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window_smoke.cpp"
$ServerExe = Join-Path $OutputDir "YuneWindowsServer.exe"
$TsfDll = Join-Path $OutputDir "YuneWindowsTSF.dll"
$ProfileToolExe = Join-Path $OutputDir "YuneWindowsProfileTool.exe"
$SettingsToolExe = Join-Path $OutputDir "YuneWindowsSettings.exe"
$CandidateWindowSmokeExe = Join-Path $OutputDir "YuneWindowsCandidateWindowSmoke.exe"
$ServerObj = Join-Path $OutputDir "yune_windows_server.obj"
$TsfObj = Join-Path $OutputDir "yune_windows_tsf.obj"
$ProfileToolObj = Join-Path $OutputDir "yune_windows_profile_tool.obj"
$SettingsToolObj = Join-Path $OutputDir "yune_windows_settings.obj"
$CandidateWindowObj = Join-Path $OutputDir "yune_windows_candidate_window.obj"
$CandidateWindowSmokeObj = Join-Path $OutputDir "yune_windows_candidate_window_smoke.obj"

if (-not (Test-Path -LiteralPath (Join-Path $IncludeDir "rime_yune_windows_profile_api.h"))) {
    throw "missing packaged Yune headers: $IncludeDir"
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

New-Item -ItemType Directory -Force $OutputDir | Out-Null
$VsDevCmd = Find-VsDevCmd

$ServerCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /I `"$IncludeDir`" /Fo`"$ServerObj`" /Fe`"$ServerExe`" `"$ServerSource`""
cmd.exe /d /s /c "$ServerCompile"
if ($LASTEXITCODE -ne 0) {
    throw "server build failed with exit code $LASTEXITCODE"
}

$CandidateWindowCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$CandidateWindowObj`" /c `"$CandidateWindowSource`""
cmd.exe /d /s /c "$CandidateWindowCompile"
if ($LASTEXITCODE -ne 0) {
    throw "candidate window build failed with exit code $LASTEXITCODE"
}

$TsfCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /LD /Fo`"$TsfObj`" /Fe`"$TsfDll`" `"$TsfSource`" `"$CandidateWindowObj`" /link ole32.lib uuid.lib advapi32.lib user32.lib gdi32.lib /EXPORT:DllGetClassObject,PRIVATE /EXPORT:DllCanUnloadNow,PRIVATE /EXPORT:DllRegisterServer,PRIVATE /EXPORT:DllUnregisterServer,PRIVATE"
cmd.exe /d /s /c "$TsfCompile"
if ($LASTEXITCODE -ne 0) {
    throw "TSF DLL build failed with exit code $LASTEXITCODE"
}

$CandidateWindowSmokeCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$CandidateWindowSmokeObj`" /Fe`"$CandidateWindowSmokeExe`" `"$CandidateWindowSmokeSource`" `"$CandidateWindowObj`" /link user32.lib gdi32.lib"
cmd.exe /d /s /c "$CandidateWindowSmokeCompile"
if ($LASTEXITCODE -ne 0) {
    throw "candidate window smoke build failed with exit code $LASTEXITCODE"
}

$ProfileToolCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$ProfileToolObj`" /Fe`"$ProfileToolExe`" `"$ProfileToolSource`" /link ole32.lib uuid.lib"
cmd.exe /d /s /c "$ProfileToolCompile"
if ($LASTEXITCODE -ne 0) {
    throw "profile tool build failed with exit code $LASTEXITCODE"
}

$SettingsToolCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$SettingsToolObj`" /Fe`"$SettingsToolExe`" `"$SettingsToolSource`" /link ole32.lib user32.lib"
cmd.exe /d /s /c "$SettingsToolCompile"
if ($LASTEXITCODE -ne 0) {
    throw "settings tool build failed with exit code $LASTEXITCODE"
}

Write-Host "Built TSF shell artifacts:"
Write-Host "  $TsfDll"
Write-Host "  $ServerExe"
Write-Host "  $ProfileToolExe"
Write-Host "  $SettingsToolExe"
Write-Host "  $CandidateWindowSmokeExe"
