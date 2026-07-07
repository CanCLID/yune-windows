param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile([string]$RelativePath) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M11C contract input: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$Header = Read-RepoFile "src\candidate_window\yune_windows_candidate_window.h"
$WindowSource = Read-RepoFile "src\candidate_window\yune_windows_candidate_window.cpp"
$SmokeSource = Read-RepoFile "src\candidate_window\yune_windows_language_bar_smoke.cpp"
$BuildScript = Read-RepoFile "tools\build-tsf-shell.ps1"
$SkinManifestText = Read-RepoFile "skins\default\theme.json"
$Evidence = Read-RepoFile "docs\evidence\m11c\summary.md"

foreach ($Forbidden in @("WebView2", "Electron", "<html", "IWebBrowser", "msedgewebview2")) {
    if ($Header -match $Forbidden -or $WindowSource -match $Forbidden) {
        throw "M11C toolbar path must stay native and must not introduce web UI/runtime dependency: $Forbidden"
    }
}

foreach ($Forbidden in @('WS_EX_LAYERED', 'UpdateLayeredWindow', 'SetWindowCompositionAttribute', 'CreateHostBackdropBrush')) {
    if ($WindowSource -match $Forbidden) {
        throw "M11C toolbar must use DComp + DWM Desktop Acrylic, not the old/stub glass path: $Forbidden"
    }
}

Require-Text $Header 'class GlassSurface' "M11C candidate-window header missing GlassSurface API."

foreach ($Required in @(
        '<d3d11\.h>',
        '<dxgi1_2\.h>',
        '<d2d1_1\.h>',
        '<dcomp\.h>',
        'ID3D11Device',
        'IDXGIDevice',
        'ID2D1Factory1',
        'ID2D1DeviceContext',
        'IDCompositionDevice',
        'IDCompositionTarget',
        'IDCompositionVisual',
        'IDCompositionSurface',
        'D3D11_CREATE_DEVICE_BGRA_SUPPORT',
        'D3D_DRIVER_TYPE_HARDWARE',
        'D3D_DRIVER_TYPE_WARP',
        'DCompositionCreateDevice',
        'CreateTargetForHwnd',
        'CreateVisual',
        'CreateSurface',
        'SetContent',
        'SetRoot',
        'Commit',
        'BeginDraw\(\s*nullptr, __uuidof\(IDXGISurface\)',
        'CreateBitmapFromDxgiSurface',
        'D2D1_BITMAP_OPTIONS_TARGET\s*\|\s*D2D1_BITMAP_OPTIONS_CANNOT_DRAW',
        'DXGI_FORMAT_B8G8R8A8_UNORM',
        'DXGI_ALPHA_MODE_PREMULTIPLIED',
        'SetDpi\(96\.0f, 96\.0f\)',
        'DwmExtendFrameIntoClientArea',
        'DWMWA_SYSTEMBACKDROP_TYPE',
        'DWMSBT_TRANSIENTWINDOW',
        'DWMWA_WINDOW_CORNER_PREFERENCE',
        'DWMWCP_ROUND',
        'D2DERR_RECREATE_TARGET',
        'DXGI_ERROR_DEVICE_REMOVED',
        'DXGI_ERROR_DEVICE_RESET',
        'DiscardDeviceResources'
    )) {
    Require-Text $WindowSource $Required "M11C DComp toolbar source missing pattern: $Required"
}

if ($WindowSource -match 'SetDpi\([^)]*state[_\.]dpi' -or
    $WindowSource -match 'SetDpi\([^)]*GetDpi') {
    throw "M11C composition render target must stay fixed at 96 DPI; DrawLanguageBarContent scales via state.dpi."
}

foreach ($Required in @(
        'WS_EX_NOACTIVATE',
        'WS_EX_TOOLWINDOW',
        'WS_EX_TOPMOST',
        'WS_EX_NOREDIRECTIONBITMAP'
    )) {
    Require-Text $WindowSource $Required "M11C language bar popup missing style: $Required"
    Require-Text $SmokeSource $Required "M11C language bar smoke missing style assertion: $Required"
}
if ($SmokeSource -match 'WS_EX_LAYERED') {
    throw "language-bar smoke must assert the DComp no-redirection style, not WS_EX_LAYERED."
}

$TsfLinkLine = [regex]::Match($BuildScript, '\$TsfCompile = ".*"').Value
foreach ($RequiredLib in @('d3d11\.lib', 'dxgi\.lib', 'dcomp\.lib')) {
    Require-Text $TsfLinkLine $RequiredLib "TSF DLL link line missing M11C DComp library: $RequiredLib"
}

$Skin = $SkinManifestText | ConvertFrom-Json
if ($Skin.glass_mechanism -ne "dwm_acrylic") {
    throw "default skin glass_mechanism must be dwm_acrylic for M11C."
}

foreach ($Required in @(
        'M11 Slice C',
        'DirectComposition',
        'Direct2D',
        'DWM Desktop Acrylic',
        'WS_EX_NOREDIRECTIONBITMAP',
        'D2D1_BITMAP_OPTIONS_CANNOT_DRAW',
        'SetDpi\(96,96\)',
        'live visual confirmation was not run'
    )) {
    Require-Text $Evidence $Required "M11C evidence summary missing: $Required"
}

Write-Host "M11C DComp glass-toolbar source-grep contract passed."
