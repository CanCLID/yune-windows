param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile([string]$RelativePath) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M11 contract input: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8
}

function Require-Text([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Text-FromCodePoints([int[]]$CodePoints) {
    return -join ($CodePoints | ForEach-Object { [string][char]$_ })
}

$SettingsSource = Read-RepoFile "src\tools\yune_windows_settings.cpp"
$UiStringsHeader = Read-RepoFile "src\tools\yune_windows_ui_strings.h"
$UiStringsSource = Read-RepoFile "src\tools\yune_windows_ui_strings.cpp"
$SettingsManifest = Read-RepoFile "src\tools\YuneWindowsSettings.exe.manifest"
$BuildScript = Read-RepoFile "tools\build-tsf-shell.ps1"
$Header = Read-RepoFile "src\candidate_window\yune_windows_candidate_window.h"
$WindowSource = Read-RepoFile "src\candidate_window\yune_windows_candidate_window.cpp"
$SkinManifestText = Read-RepoFile "skins\default\theme.json"
$Evidence = Read-RepoFile "docs\evidence\m11\summary.md"
$Roadmap = Read-RepoFile "docs\roadmap.md"
$M11DPlan = Read-RepoFile "docs\plans\active\m11d-ime-activation-toolbar-visibility.md"

foreach ($Forbidden in @("WebView2", "Electron", "<html", "IWebBrowser", "msedgewebview2")) {
    if ($SettingsSource -match $Forbidden -or $WindowSource -match $Forbidden) {
        throw "M11 native UI path must not introduce a web UI/runtime dependency: $Forbidden"
    }
}

foreach ($Required in @(
        'Microsoft.Windows.Common-Controls',
        '6.0.0.0',
        '<dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>'
    )) {
    Require-Text $SettingsManifest ([regex]::Escape($Required)) "settings manifest is missing: $Required"
}
if ($SettingsManifest -match '<dpiAware(\s|>)') {
    throw "settings manifest must use the modern dpiAwareness element, not dpiAware."
}
foreach ($Required in @(
        'YuneWindowsSettings\.exe\.manifest',
        '/MANIFEST:EMBED',
        '/MANIFESTINPUT:'
    )) {
    Require-Text $BuildScript $Required "build script must embed the settings manifest: $Required"
}

foreach ($Required in @(
        'yune_windows_ui_strings\.h',
        'ui_strings::kSettingsWindowTitle',
        'Microsoft JhengHei UI',
        'CreateFontW',
        'WM_SETFONT',
        'WM_DPICHANGED',
        'LayoutEntry',
        'ApplyUIFontToControls',
        'InitCommonControlsEx',
        'ApplyDwmPolish',
        'DwmSetWindowAttribute',
        'DWMWA_SYSTEMBACKDROP_TYPE',
        'DWMWA_WINDOW_CORNER_PREFERENCE',
        'DWMWA_USE_IMMERSIVE_DARK_MODE',
        'WindowsBuildNumber',
        '22621',
        '22000',
        'fallback_dark_mode_attribute = 19'
    )) {
    Require-Text $SettingsSource $Required "settings source is missing M11 theming/DPI/DWM pattern: $Required"
}

foreach ($Required in @(
        'struct ComboItem',
        'CB_SETITEMDATA',
        'CB_GETITEMDATA',
        'SelectedComboValue',
        'SelectComboValue',
        'OutputStandardDisplayLabel',
        'SchemaDisplayLabel',
        'SkinDisplayLabel'
    )) {
    Require-Text $SettingsSource $Required "settings source is missing combo label/value split pattern: $Required"
}

foreach ($Forbidden in @(
        'Native settings panel',
        'Yune Windows Settings',
        'Yune Windows server is not available',
        'Unable to update Yune Windows',
        'Input / session',
        'Appearance',
        'Engine',
        'Dictionary',
        'Schemas',
        'Output standard',
        'Schema switch',
        'Skin',
        'coming soon',
        'Toolbar preview unavailable',
        'State: ',
        'connected',
        'offline',
        'Unknown'
    )) {
    $LiteralPattern = 'L"[^"]*' + [regex]::Escape($Forbidden) + '[^"]*"'
    if ($SettingsSource -cmatch $LiteralPattern) {
        throw "settings source still contains old user-facing English literal: $Forbidden"
    }
}

$RequiredCantonese = @(
    (Text-FromCodePoints @(0x65b0, 0x97fb, 0x8f38, 0x5165, 0x6cd5, 0x8a2d, 0x5b9a)),
    (Text-FromCodePoints @(0x8f38, 0x5165, 0x6cd5, 0x8a2d, 0x5b9a)),
    (Text-FromCodePoints @(0x72c0, 0x614b, 0xff1a)),
    (Text-FromCodePoints @(0x5df2, 0x9023, 0x7dda)),
    (Text-FromCodePoints @(0x96e2, 0x7dda)),
    (Text-FromCodePoints @(0x4e3b, 0x984c, 0xff1a)),
    (Text-FromCodePoints @(0x9810, 0x8a2d)),
    (Text-FromCodePoints @(0x50b3, 0x7d71, 0x6f22, 0x5b57)),
    (Text-FromCodePoints @(0x9999, 0x6e2f, 0x5b57, 0x5f62)),
    (Text-FromCodePoints @(0x53f0, 0x7063, 0x5b57, 0x5f62)),
    (Text-FromCodePoints @(0x7cb5, 0x8a9e, 0x62fc, 0x97f3)),
    (Text-FromCodePoints @(0x6719, 0x6708, 0x62fc, 0x97f3)),
    (Text-FromCodePoints @(0x5de5, 0x5177, 0x5217, 0x9810, 0x89bd, 0x7121, 0x6cd5, 0x986f, 0x793a)),
    (Text-FromCodePoints @(0x65b0, 0x97fb, 0x8f38, 0x5165, 0x6cd5, 0x4f3a, 0x670d, 0x5668, 0x672a, 0x555f, 0x7528, 0x3002)),
    (Text-FromCodePoints @(0x7121, 0x6cd5, 0x66f4, 0x65b0, 0x4e3b, 0x984c, 0x3002))
)
foreach ($Required in $RequiredCantonese) {
    Require-Text $UiStringsSource ([regex]::Escape($Required)) "ui_strings source missing Cantonese text: $Required"
}

foreach ($Match in [regex]::Matches($UiStringsSource, 'L"([^"]*[A-Za-z][^"]*)"')) {
    throw "ui_strings user-visible literal contains ASCII letters: $($Match.Value)"
}

foreach ($Forbidden in @('L"EN"', '\\x62fc', '\\x7e41', '\\x81fa', 'value\.substr\(0, 1\)')) {
    if ($WindowSource -match $Forbidden) {
        throw "toolbar source still has pre-M11 English/old-glyph/fallthrough pattern: $Forbidden"
    }
}
foreach ($Required in @(
        'luna_pinyin_octagram',
        'L"\\x82f1"',
        'L"\\x50b3"',
        'L"\\x53f0"',
        'L"\\x6719"'
    )) {
    Require-Text $WindowSource $Required "toolbar source missing M11 glyph mapping: $Required"
}

# The glass backend must be present in SOURCE (header or window source) -- NOT
# satisfied by an evidence-doc or comment-only mention. M11 Slice C intentionally
# uses native DComp + Direct2D over DWM Desktop Acrylic, not WinRT host backdrop
# and not the old layered/ULW renderer.
foreach ($Required in @(
        'class GlassSurface',
        'ToolbarGlassMechanism',
        'glass_mechanism',
        'glass_fallback',
        'WS_EX_NOREDIRECTIONBITMAP',
        'DCompositionCreateDevice',
        'CreateTargetForHwnd',
        'CreateBitmapFromDxgiSurface',
        'D2D1_BITMAP_OPTIONS_CANNOT_DRAW',
        'DwmExtendFrameIntoClientArea',
        'DWMWA_WINDOW_CORNER_PREFERENCE',
        'DWMSBT_TRANSIENTWINDOW',
        'DWMSBT_NONE',
        'EffectiveWindowsBuildNumber\(\) < 22621',
        'ApplyToolbarGlassBackdrop',
        'acrylic_backdrop_active',
        'FAILED\(ExtendToolbarFrame\(hwnd, sheet\)\)',
        'DXGI_ERROR_DEVICE_REMOVED'
    )) {
    if ($Header -match $Required -or $WindowSource -match $Required) {
        continue
    }
    throw "M11 glass backend is missing from source (header/window): $Required"
}

foreach ($Forbidden in @('WS_EX_LAYERED', 'UpdateLayeredWindow', 'SetWindowCompositionAttribute', 'CreateHostBackdropBrush')) {
    if ($WindowSource -match $Forbidden) {
        throw "M11 glass backend must stay on the native DComp/DWM path, not the old/stub path: $Forbidden"
    }
}

$Skin = $SkinManifestText | ConvertFrom-Json
foreach ($RequiredProperty in @("glass_mechanism", "glass_fallback")) {
    if ($Skin.PSObject.Properties.Name -notcontains $RequiredProperty) {
        throw "default skin manifest is missing M11 glass property: $RequiredProperty"
    }
}
if ($Skin.glass_fallback -ne "static_tint") {
    throw "default skin glass_fallback must remain static_tint."
}
foreach ($RemovedProperty in @("glass_tint", "glass_tint_opacity", "blur_amount", "highlight_intensity")) {
    if ($Skin.PSObject.Properties.Name -contains $RemovedProperty -or
        $Header -match $RemovedProperty -or
        $WindowSource -match $RemovedProperty) {
        throw "removed inert v1 glass field is still present: $RemovedProperty"
    }
}
$GlyphAscii = Text-FromCodePoints @(0x4e2d)
$GlyphTraditional = Text-FromCodePoints @(0x50b3)
$GlyphLuna = Text-FromCodePoints @(0x6719)
if ($Skin.segments.ascii -ne $GlyphAscii -or
    $Skin.segments.standard -ne $GlyphTraditional -or
    $Skin.segments.schema -ne $GlyphLuna) {
    throw "default skin segment glyphs must align with M11 Cantonese glyphs."
}

foreach ($Required in @(
        'M11 UI Modernization \+ Cantonese Localization',
        'non-elevated',
        'installed clone/drag proof passed',
        'M11D',
        'combo label/value\s+(split|separation)',
        'Cantonese',
        'DirectComposition',
        '(DWM|acrylic)'
    )) {
    Require-Text $Evidence $Required "M11 evidence summary is missing: $Required"
}
Require-Text $Roadmap 'M11 .*installed clone/drag proof passed; M11D pending' `
    "roadmap must separate the passed M11 clone gate from the open M11D reliability gate."
foreach ($Required in @(
        'M11D - IME Activation, Toggle, and Toolbar Visibility Reliability',
        'exactly one acknowledged',
        '50 lone-Shift',
        'M10 remains blocked',
        'No Yune engine ABI change'
    )) {
    Require-Text $M11DPlan $Required "M11D reliability plan is missing: $Required"
}

Write-Host "M11 UI modernization/Cantonese localization static contract passed."
