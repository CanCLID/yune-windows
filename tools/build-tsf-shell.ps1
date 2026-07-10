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
$ReliabilitySmokeSource = Join-Path $RepoRoot "src\tsf\yune_windows_reliability_smoke.cpp"
$ProfileToolSource = Join-Path $RepoRoot "src\tools\yune_windows_profile_tool.cpp"
$SettingsToolSource = Join-Path $RepoRoot "src\tools\yune_windows_settings.cpp"
$SettingsUiStringsSource = Join-Path $RepoRoot "src\tools\yune_windows_ui_strings.cpp"
$SettingsManifest = Join-Path $RepoRoot "src\tools\YuneWindowsSettings.exe.manifest"
$CandidateWindowSource = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window.cpp"
$CandidateWindowSmokeSource = Join-Path $RepoRoot "src\candidate_window\yune_windows_candidate_window_smoke.cpp"
$LanguageBarSmokeSource = Join-Path $RepoRoot "src\candidate_window\yune_windows_language_bar_smoke.cpp"
$SkinSourceDir = Join-Path $RepoRoot "skins"
$ServerExe = Join-Path $OutputDir "YuneWindowsServer.exe"
$TsfDll = Join-Path $OutputDir "YuneWindowsTSF.dll"
$ReliabilitySmokeExe = Join-Path $OutputDir "YuneWindowsReliabilitySmoke.exe"
$ProfileToolExe = Join-Path $OutputDir "YuneWindowsProfileTool.exe"
$SettingsToolExe = Join-Path $OutputDir "YuneWindowsSettings.exe"
$CandidateWindowSmokeExe = Join-Path $OutputDir "YuneWindowsCandidateWindowSmoke.exe"
$LanguageBarSmokeExe = Join-Path $OutputDir "YuneWindowsLanguageBarSmoke.exe"
$ServerObj = Join-Path $OutputDir "yune_windows_server.obj"
$TsfObj = Join-Path $OutputDir "yune_windows_tsf.obj"
$ReliabilitySmokeObj = Join-Path $OutputDir "yune_windows_reliability_smoke.obj"
$ProfileToolObj = Join-Path $OutputDir "yune_windows_profile_tool.obj"
$SettingsToolObj = Join-Path $OutputDir "yune_windows_settings.obj"
$SettingsUiStringsObj = Join-Path $OutputDir "yune_windows_ui_strings.obj"
$CandidateWindowObj = Join-Path $OutputDir "yune_windows_candidate_window.obj"
$LanguageBarCandidateWindowObj = Join-Path $OutputDir "yune_windows_candidate_window_language_bar_smoke.obj"
$CandidateWindowSmokeObj = Join-Path $OutputDir "yune_windows_candidate_window_smoke.obj"
$LanguageBarSmokeObj = Join-Path $OutputDir "yune_windows_language_bar_smoke.obj"

if (-not (Test-Path -LiteralPath (Join-Path $IncludeDir "rime_yune_windows_profile_api.h"))) {
    throw "missing packaged Yune headers: $IncludeDir"
}
if (-not (Test-Path -LiteralPath (Join-Path $SkinSourceDir "default\theme.json") -PathType Leaf)) {
    throw "missing default toolbar skin manifest: $SkinSourceDir\default\theme.json"
}
if (-not (Test-Path -LiteralPath $SettingsManifest -PathType Leaf)) {
    throw "missing settings manifest: $SettingsManifest"
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

$LanguageBarCandidateWindowCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /DYUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS /Fo`"$LanguageBarCandidateWindowObj`" /c `"$CandidateWindowSource`""
cmd.exe /d /s /c "$LanguageBarCandidateWindowCompile"
if ($LASTEXITCODE -ne 0) {
    throw "language-bar candidate window smoke build failed with exit code $LASTEXITCODE"
}

$TsfCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /LD /Fo`"$TsfObj`" /Fe`"$TsfDll`" `"$TsfSource`" `"$CandidateWindowObj`" /link ole32.lib uuid.lib advapi32.lib user32.lib gdi32.lib dwmapi.lib d2d1.lib dwrite.lib d3d11.lib dxgi.lib dcomp.lib /EXPORT:DllGetClassObject,PRIVATE /EXPORT:DllCanUnloadNow,PRIVATE /EXPORT:DllRegisterServer,PRIVATE /EXPORT:DllUnregisterServer,PRIVATE"
cmd.exe /d /s /c "$TsfCompile"
if ($LASTEXITCODE -ne 0) {
    throw "TSF DLL build failed with exit code $LASTEXITCODE"
}

$ReliabilitySmokeCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /Fo`"$ReliabilitySmokeObj`" /Fe`"$ReliabilitySmokeExe`" `"$ReliabilitySmokeSource`""
cmd.exe /d /s /c "$ReliabilitySmokeCompile"
if ($LASTEXITCODE -ne 0) {
    throw "M11D reliability smoke build failed with exit code $LASTEXITCODE"
}

$CandidateWindowSmokeCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$CandidateWindowSmokeObj`" /Fe`"$CandidateWindowSmokeExe`" `"$CandidateWindowSmokeSource`" `"$CandidateWindowObj`" /link user32.lib gdi32.lib ole32.lib dwmapi.lib d2d1.lib dwrite.lib d3d11.lib dxgi.lib dcomp.lib"
cmd.exe /d /s /c "$CandidateWindowSmokeCompile"
if ($LASTEXITCODE -ne 0) {
    throw "candidate window smoke build failed with exit code $LASTEXITCODE"
}

$LanguageBarSmokeCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /DYUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS /Fo`"$LanguageBarSmokeObj`" /Fe`"$LanguageBarSmokeExe`" `"$LanguageBarSmokeSource`" `"$LanguageBarCandidateWindowObj`" /link user32.lib gdi32.lib ole32.lib dwmapi.lib d2d1.lib dwrite.lib d3d11.lib dxgi.lib dcomp.lib"
cmd.exe /d /s /c "$LanguageBarSmokeCompile"
if ($LASTEXITCODE -ne 0) {
    throw "language bar smoke build failed with exit code $LASTEXITCODE"
}

$ProfileToolCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$ProfileToolObj`" /Fe`"$ProfileToolExe`" `"$ProfileToolSource`" /link ole32.lib uuid.lib"
cmd.exe /d /s /c "$ProfileToolCompile"
if ($LASTEXITCODE -ne 0) {
    throw "profile tool build failed with exit code $LASTEXITCODE"
}

$SettingsUiStringsCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$SettingsUiStringsObj`" /c `"$SettingsUiStringsSource`""
cmd.exe /d /s /c "$SettingsUiStringsCompile"
if ($LASTEXITCODE -ne 0) {
    throw "settings UI strings build failed with exit code $LASTEXITCODE"
}

$SettingsToolCompile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$SettingsToolObj`" /Fe`"$SettingsToolExe`" `"$SettingsToolSource`" `"$SettingsUiStringsObj`" `"$CandidateWindowObj`" /link ole32.lib user32.lib gdi32.lib comctl32.lib dwmapi.lib advapi32.lib d2d1.lib dwrite.lib d3d11.lib dxgi.lib dcomp.lib /SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup /MANIFEST:EMBED /MANIFESTINPUT:`"$SettingsManifest`""
cmd.exe /d /s /c "$SettingsToolCompile"
if ($LASTEXITCODE -ne 0) {
    throw "settings tool build failed with exit code $LASTEXITCODE"
}

$SkinDestDir = Join-Path $OutputDir "skins"
if (Test-Path -LiteralPath $SkinDestDir) {
    Remove-Item -LiteralPath $SkinDestDir -Recurse -Force
}
Copy-Item -LiteralPath $SkinSourceDir -Destination $SkinDestDir -Recurse -Force

Write-Host "Built TSF shell artifacts:"
Write-Host "  $TsfDll"
Write-Host "  $ReliabilitySmokeExe"
Write-Host "  $ServerExe"
Write-Host "  $ProfileToolExe"
Write-Host "  $SettingsToolExe"
Write-Host "  $CandidateWindowSmokeExe"
Write-Host "  $LanguageBarSmokeExe"
Write-Host "  $(Join-Path $SkinDestDir "default\theme.json")"
