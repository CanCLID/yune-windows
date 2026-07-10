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
        'WS_EX_NOREDIRECTIONBITMAP',
        'ID2D1DeviceContext',
        'D2D1CreateFactory',
        'DWriteCreateFactory',
        'DCompositionCreateDevice',
        'CreateTargetForHwnd',
        'CreateBitmapFromDxgiSurface',
        'D2D1_BITMAP_OPTIONS_CANNOT_DRAW',
        'D2DERR_RECREATE_TARGET',
        'DXGI_ERROR_DEVICE_REMOVED',
        'WM_DPICHANGED',
        'TrackMouseEvent',
        'TME_LEAVE',
        'SetCapture',
        'ReleaseCapture',
        'kLanguageBarDragThreshold',
        'ToolbarSegmentLabelForState',
        'skin\.segment_labels',
        'SWP_NOACTIVATE'
    )) {
    Require-Text $WindowSource $Required "language-bar source is missing M08 D2D/drag pattern: $Required"
}

foreach ($Forbidden in @('WS_EX_LAYERED', 'UpdateLayeredWindow')) {
    if ($WindowSource -match $Forbidden) {
        throw "M08 toolbar current source must use the DComp presentation model, not ULW/layered: $Forbidden"
    }
}

if ($WindowSource -match 'LanguageBarLabel\(segments\[i\], state\)') {
    throw "M08 toolbar render path parses manifest segment labels but still draws hardcoded state-only labels."
}

if ($WindowSource -match 'IWICImagingFactory' -or $WindowSource -match 'CLSID_WICImagingFactory') {
    throw "M08 toolbar glyph render path must not require WIC; raster/vector image assets are deferred."
}

if ($WindowSource -match 'HTCAPTION') {
    throw "M08 no-activate drag must not use HTCAPTION."
}

# Ghost-trail fix: SetWindowPos is the single position authority. The toolbar
# content must be a DComp surface so window moves do not stamp stale ULW frames.
Require-Text $WindowSource 'SetWindowPos\(hwnd_, nullptr, clamped\.left, clamped\.top' `
    "language-bar drag must still move the no-activate popup with SetWindowPos."
$ContinueBody = [regex]::Match(
    $WindowSource,
    '(?s)void LanguageBarWindow::ContinuePointerInteraction\(POINT client_point\) \{(?<body>.*?)\r?\n\}\r?\n\r?\nvoid LanguageBarWindow::EndPointerInteraction').Groups['body'].Value
if ($ContinueBody -eq '') {
    throw "unable to locate LanguageBarWindow::ContinuePointerInteraction body."
}
Require-Text $ContinueBody 'SetWindowPos' `
    "language-bar drag must move the persistent composition window."
foreach ($Forbidden in @('(?m)^\s*Render\s*\(', 'PresentLanguageBar', 'BeginDraw', 'Commit\s*\(')) {
    if ($ContinueBody -match $Forbidden) {
        throw "language-bar drag movement must not render/commit DComp frames: $Forbidden"
    }
}
Require-Text $WindowSource 'pointer_captured_ \|\| finishing_pointer_interaction_' `
    "language-bar Update must defer state/layout rendering while capture finalizes."
Require-Text $WindowSource 'QueueRender\(true, false\)' `
    "language-bar Update must queue one post-capture state/layout render."

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
        'd3d11\.lib',
        'dxgi\.lib',
        'dcomp\.lib',
        'YuneWindowsLanguageBarSmoke\.exe',
        'skins'
    )) {
    Require-Text $BuildScript $Required "build-tsf-shell.ps1 is missing M08 build/deploy pattern: $Required"
}

if ($BuildScript -match 'windowscodecs\.lib') {
    throw "M08 toolbar build must not link WIC when the shipped default skin has no rendered image assets."
}

foreach ($Entry in @(
        @{ name = "install script"; text = $InstallScript },
        @{ name = "dev reload TSF"; text = $DevReloadTsf },
        @{ name = "dev swap TSF"; text = $DevSwapTsf }
    )) {
    Require-Text ([string]$Entry.text) 'skins' "$($Entry.name) must copy skins/default into the runtime root."
}

# Deploy-gap fix: the dev swap must also redeploy the on-demand client exe the
# toolbar gear launches, or a stale console-subsystem YuneWindowsSettings.exe
# keeps opening a terminal window even after a swap.
Require-Text $DevSwapTsf 'YuneWindowsSettings\.exe' `
    "dev swap TSF must redeploy YuneWindowsSettings.exe (settings-exe deploy gap left the stale console build installed)."

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
if ($Skin.PSObject.Properties.Name -contains "assets") {
    throw "M08 default skin must not declare image assets until the renderer consumes them."
}

$SkinAssetsDir = Join-Path $RepoRoot "skins\default\assets"
if (Test-Path -LiteralPath $SkinAssetsDir) {
    $DeadAssets = Get-ChildItem -LiteralPath $SkinAssetsDir -Recurse -File -ErrorAction SilentlyContinue
    if ($DeadAssets.Count -gt 0) {
        throw "M08 must not ship inert skin image assets: $($DeadAssets[0].FullName)"
    }
}

$Evidence = Join-Path $RepoRoot "docs\evidence\m08\summary.md"
if (-not (Test-Path -LiteralPath $Evidence -PathType Leaf)) {
    throw "missing M08 evidence summary: docs\evidence\m08\summary.md"
}
$EvidenceText = Get-Content -Raw -LiteralPath $Evidence
Require-Text $EvidenceText 'live dogfood visual' "M08 evidence must call out the pending live dogfood visual/interactive check."
Require-Text $EvidenceText 'SVG asset rendering is deferred' "M08 evidence must not imply shipped SVG assets affect the toolbar."

$RoadmapText = Read-RepoFile "docs\roadmap.md"
Require-Text $RoadmapText 'live visual pending' "roadmap must keep M08 non-elevated status distinct from pending live visual proof."

Write-Host "M08 modern toolbar static contract passed."
