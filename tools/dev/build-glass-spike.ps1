param()

# Builds the throwaway M11 Slice C glass spike (src/tools/yune_windows_glass_spike.cpp)
# into a temp dir. Not part of the product build; never shipped.

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Source = Join-Path $RepoRoot "src\tools\yune_windows_glass_spike.cpp"
$OutDir = Join-Path $env:TEMP "yune-windows\glass-spike"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Exe = Join-Path $OutDir "YuneWindowsGlassSpike.exe"
$Obj = Join-Path $OutDir "yune_windows_glass_spike.obj"

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

$VsDevCmd = Find-VsDevCmd
$Compile = "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /permissive- /utf-8 /DUNICODE /D_UNICODE /Fo`"$Obj`" /Fe`"$Exe`" `"$Source`" /link user32.lib gdi32.lib dwmapi.lib /SUBSYSTEM:WINDOWS /ENTRY:wWinMainCRTStartup"
cmd.exe /d /s /c "$Compile"
if ($LASTEXITCODE -ne 0) { throw "glass spike build failed with exit code $LASTEXITCODE" }

Write-Host "Built glass spike:"
Write-Host "  $Exe"
Write-Host "Run it, drag it over an editor / colored window, press 1-4 to switch material, screenshot each, Esc to quit."
