param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Read-RepoFile([string]$RelativePath) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing M09 contract input: $RelativePath"
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
$SettingsSource = Read-RepoFile "src\tools\yune_windows_settings.cpp"
$BuildScript = Read-RepoFile "tools\build-tsf-shell.ps1"

foreach ($Forbidden in @("WebView2", "Electron", "<html", "IWebBrowser", "msedgewebview2")) {
    if ($TsfSource -match $Forbidden -or
        $WindowSource -match $Forbidden -or
        $SettingsSource -match $Forbidden) {
        throw "M09 native settings path must not introduce web UI/runtime dependency: $Forbidden"
    }
}

foreach ($Required in @(
        'enum class LanguageBarSegment(?s:.*?)Settings',
        'std::array<std::wstring, 5>',
        'PaintLanguageBarPreview'
    )) {
    Require-Text $Header $Required "candidate-window header is missing M09 toolbar/settings API: $Required"
}

foreach ($Required in @(
        'constexpr int kToolbarSegmentCount = 5',
        '"settings"',
        'LanguageBarSegment::Settings',
        'IsPointInSettingsSegment',
        'click_allowed_',
        'PaintLanguageBarPreview',
        'ToolbarSegmentLabelForState'
    )) {
    Require-Text $WindowSource $Required "language-bar source is missing M09 settings segment/render pattern: $Required"
}

foreach ($Required in @(
        'LaunchOrFocusSettings',
        'YuneWindowsSettings.exe',
        'FindWindowW',
        'CreateProcessW',
        'LanguageBarSegment::Settings'
    )) {
    Require-Text $TsfSource $Required "TSF source is missing settings launch/focus wiring: $Required"
}

foreach ($Required in @(
        'Native settings panel',
        'Input / session',
        'Appearance',
        'Engine',
        'Dictionary',
        'Schemas',
        'coming soon',
        'op=set-skin',
        'EnumerateInstalledSkins',
        'D2DSurface',
        'PaintLanguageBarPreview',
        'CBS_DROPDOWNLIST',
        'WS_DISABLED',
        '--self-test'
    )) {
    Require-Text $SettingsSource $Required "settings source is missing M09 native panel pattern: $Required"
}

foreach ($Required in @(
        'CandidateWindowObj',
        'YuneWindowsSettings.exe',
        'd2d1\.lib',
        'dwrite\.lib'
    )) {
    Require-Text $BuildScript $Required "build script is missing M09 settings preview link pattern: $Required"
}

$SkinManifest = Join-Path $RepoRoot "skins\default\theme.json"
if (-not (Test-Path -LiteralPath $SkinManifest -PathType Leaf)) {
    throw "missing default skin manifest: skins\default\theme.json"
}
$Skin = Get-Content -Raw -LiteralPath $SkinManifest | ConvertFrom-Json
if (-not $Skin.segments -or
    $Skin.segments.PSObject.Properties.Name -notcontains "settings") {
    throw "default skin manifest must declare a settings segment label."
}

$Evidence = Join-Path $RepoRoot "docs\evidence\m09\summary.md"
if (-not (Test-Path -LiteralPath $Evidence -PathType Leaf)) {
    throw "missing M09 evidence summary: docs\evidence\m09\summary.md"
}
$EvidenceText = Get-Content -Raw -LiteralPath $Evidence
Require-Text $EvidenceText 'native Win32' "M09 evidence must state the settings panel is native Win32."
Require-Text $EvidenceText 'live-machine steps were not run' "M09 evidence must preserve the live-machine approval boundary."

Write-Host "M09 native settings panel static contract passed."
