param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme"
)

# Swap the installed YuneWindowsTSF.dll on disk without the full holder-free
# dance. A loaded DLL image is opened share-delete, so it can be renamed aside
# (allowed while mapped into running apps); the new DLL then drops into the
# registered path. Apps that already have the old DLL loaded keep it until they
# RESTART -- so after this, restart the apps you want to test (Chrome, Telegram,
# Zed, Explorer) to pick up the new DLL. No reboot; same COM registration/path.

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

Write-Host "=== building ==="
$BuildDir = Join-Path $env:TEMP ("yune-windows\swap-tsf-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $BuildDir -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) { throw "build failed with exit code $LASTEXITCODE" }
$NewDll = Join-Path $BuildDir "YuneWindowsTSF.dll"
$NewSkins = Join-Path $BuildDir "skins"
$Dest = Join-Path $InstallDir "YuneWindowsTSF.dll"

if (-not (Test-Path -LiteralPath $Dest -PathType Leaf)) {
    throw "installed TSF DLL not found at $Dest -- is Yune Windows installed?"
}

$NewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $NewDll).Hash
$OldHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dest).Hash
if ($NewHash -eq $OldHash) {
    Write-Host "Installed DLL already matches the fresh build (SHA $NewHash); nothing to swap."
    return
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Write-Host "=== swapping DLL (rename-aside) ==="
try {
    Copy-Item -LiteralPath $NewDll -Destination $Dest -Force
}
catch {
    $Aside = "$Dest.swap-$Timestamp"
    Move-Item -LiteralPath $Dest -Destination $Aside -Force
    Copy-Item -LiteralPath $NewDll -Destination $Dest -Force
    Write-Host "  (renamed the loaded DLL aside: $Aside)"
}

$InstalledHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dest).Hash
if ($InstalledHash -ne $NewHash) {
    throw "DLL swap did not take: installed SHA $InstalledHash != built SHA $NewHash"
}

if (Test-Path -LiteralPath (Join-Path $NewSkins "default\theme.json") -PathType Leaf) {
    $SkinDest = Join-Path $InstallDir "skins"
    if (Test-Path -LiteralPath $SkinDest) {
        Remove-Item -LiteralPath $SkinDest -Recurse -Force
    }
    Copy-Item -LiteralPath $NewSkins -Destination $SkinDest -Recurse -Force
    Write-Host "Copied toolbar skins into $SkinDest"
}

# Best-effort cleanup of previously renamed-aside DLLs (locked ones stay until
# the holding app exits).
Get-ChildItem -LiteralPath $InstallDir -Filter "YuneWindowsTSF.dll.swap-*" -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {}
}

Write-Host "SUCCESS: installed YuneWindowsTSF.dll is now the fresh build (SHA $NewHash)."
Write-Host "NEXT: restart the apps you want to test (Chrome, Telegram, Zed, Explorer)"
Write-Host "      so they load the new DLL, then check the 中/英 Shift toggle."
