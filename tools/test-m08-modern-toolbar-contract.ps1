param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile([string]$RelativePath) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M08 contract input: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $Path
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$Header = Read-RepoFile "src\candidate_window\yune_windows_candidate_window.h"
$WindowSource = Read-RepoFile "src\candidate_window\yune_windows_candidate_window.cpp"
$TsfSource = Read-RepoFile "src\tsf\yune_windows_tsf.cpp"
$ServerSource = Read-RepoFile "src\server\yune_windows_server.cpp"
$BuildScript = Read-RepoFile "tools\build-tsf-shell.ps1"
$InstallScript = Read-RepoFile "tools\install-yune-windows-ime.ps1"
$DevReloadTsf = Read-RepoFile "tools\dev\dev-reload-tsf.ps1"
$DevSwapTsf = Read-RepoFile "tools\dev\dev-swap-tsf-dll.ps1"
$TsfBuildTest = Read-RepoFile "tools\test-tsf-shell-build.ps1"

foreach ($Forbidden in @("WebView2", "Electron", "<html", "IWebBrowser", "msedgewebview2")) {
    if ($TsfSource -match $Forbidden -or $WindowSource -match $Forbidden) {
        throw "M08 toolbar must not introduce WebView2/Electron/HTML into the TSF DLL path: $Forbidden"
    }
}

foreach ($Required in @(
        'struct ToolbarPosition',
        'struct ToolbarSkin',
        'class D2DSurface',
        'LoadToolbarSkin',
        'ComputeToolbarWindowRect',
        'ClampToolbarRectToVisibleMonitor',
        'LanguageBarPositionChangedHandler',
        'SetPositionChangedHandler'
    )) {
    Require-Text $Header $Required "candidate-window header is missing shared M08 API: $Required"
}

foreach ($Required in @(
        'WS_EX_LAYERED',
        'UpdateLayeredWindow',
        'ID2D1DCRenderTarget',
        'D2D1CreateFactory',
        'DWriteCreateFactory',
        'IWICImagingFactory',
        'D2DERR_RECREATE_TARGET',
        'WM_DPICHANGED',
        'SetCapture',
        'ReleaseCapture',
        'kLanguageBarDragThreshold',
        'SWP_NOACTIVATE'
    )) {
    Require-Text $WindowSource $Required "language-bar source is missing M08 D2D/drag pattern: $Required"
}

if ($WindowSource -match 'HTCAPTION') {
    throw "M08 no-activate drag must not use HTCAPTION."
}

foreach ($Required in @(
        'set-toolbar-position',
        'set-skin',
        'toolbar',
        'toolbar_position',
        'toolbar_skin',
        'state\\ime-state\.json'
    )) {
    Require-Text $ServerSource $Required "server source is missing toolbar state/protocol pattern: $Required"
}

foreach ($Required in @(
        'toolbar_position',
        'toolbar_skin',
        'JsonIntValue',
        'SetPositionChangedHandler',
        'HandleLanguageBarPositionChanged',
        'op=set-toolbar-position'
    )) {
    Require-Text $TsfSource $Required "TSF source is missing server-owned toolbar state wiring: $Required"
}

if ($TsfSource -match 'ime-state\.json') {
    throw "TSF DLL must not write or read ime-state.json directly for toolbar UI state."
}

foreach ($Required in @(
        'd2d1\.lib',
        'dwrite\.lib',
        'windowscodecs\.lib',
        'YuneWindowsLanguageBarSmoke\.exe',
        'skins'
    )) {
    Require-Text $BuildScript $Required "build-tsf-shell.ps1 is missing M08 build/deploy pattern: $Required"
}

foreach ($Entry in @(
        @{ name = "install script"; text = $InstallScript },
        @{ name = "dev reload TSF"; text = $DevReloadTsf },
        @{ name = "dev swap TSF"; text = $DevSwapTsf }
    )) {
    Require-Text ([string]$Entry.text) 'skins' "$($Entry.name) must copy skins/default into the runtime root."
}

Require-Text $TsfBuildTest 'YuneWindowsLanguageBarSmoke\.exe' "TSF build contract must require the language-bar smoke executable."
Require-Text $TsfBuildTest 'skins\\default\\theme\.json' "TSF build contract must require the default skin manifest."

$SkinManifest = Join-Path $RepoRoot "skins\default\theme.json"
if (-not (Test-Path -LiteralPath $SkinManifest -PathType Leaf)) {
    throw "missing default skin manifest: skins\default\theme.json"
}

$Skin = Get-Content -Raw -LiteralPath $SkinManifest | ConvertFrom-Json
foreach ($RequiredProperty in @("name", "geometry", "colors", "font", "segments")) {
    if ($Skin.PSObject.Properties.Name -notcontains $RequiredProperty) {
        throw "default skin manifest is missing property: $RequiredProperty"
    }
}

$Evidence = Join-Path $RepoRoot "docs\evidence\m08\summary.md"
if (-not (Test-Path -LiteralPath $Evidence -PathType Leaf)) {
    throw "missing M08 evidence summary: docs\evidence\m08\summary.md"
}

Write-Host "M08 modern toolbar static contract passed."
