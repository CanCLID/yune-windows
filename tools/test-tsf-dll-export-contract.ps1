param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-tsf-export-contract"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $OutputDir | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "TSF shell build failed with exit code $LASTEXITCODE"
}

$TsfDll = Join-Path $OutputDir "YuneWindowsTSF.dll"
if (-not (Test-Path -LiteralPath $TsfDll)) {
    throw "TSF shell build did not produce YuneWindowsTSF.dll"
}

function Find-VsDevCmd {
    $Candidates = @(
        (Join-Path $env:ProgramFiles "Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"),
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat")
    )
    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate)) {
            return $Candidate
        }
    }
    throw "missing VsDevCmd.bat; install Visual Studio C++ tools"
}

$VsDevCmd = Find-VsDevCmd
$Exports = cmd.exe /d /s /c "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && dumpbin.exe /exports `"$TsfDll`""
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin /exports failed with exit code $LASTEXITCODE"
}

foreach ($RequiredExport in @(
        "DllGetClassObject",
        "DllCanUnloadNow",
        "DllRegisterServer",
        "DllUnregisterServer"
    )) {
    if (-not ($Exports -match "(?m)\b$RequiredExport\b")) {
        throw "YuneWindowsTSF.dll export table is missing $RequiredExport"
    }
}

Write-Host "YuneWindows TSF DLL exports COM and registration entry points."
