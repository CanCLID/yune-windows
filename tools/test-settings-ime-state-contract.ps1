param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
$SettingsSource = Join-Path $RepoRoot "src\tools\yune_windows_settings.cpp"

if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) {
    throw "missing build script: $BuildScript"
}
if (-not (Test-Path -LiteralPath $SettingsSource -PathType Leaf)) {
    throw "missing settings source: $SettingsSource"
}

$Build = Get-Content -Raw -LiteralPath $BuildScript
$Settings = Get-Content -Raw -LiteralPath $SettingsSource

foreach ($Required in @(
        'YuneWindowsSettings.exe',
        'yune_windows_settings.cpp',
        'SettingsToolCompile'
    )) {
    if ($Build -notmatch $Required) {
        throw "build script is missing settings target pattern: $Required"
    }
}

foreach ($Required in @(
        'op=get-state',
        'op=list-schemas',
        'op=set-option',
        'op=select-schema',
        'op=set-skin',
        'CreateWindowExW',
        'ascii_mode',
        'full_shape',
        'output_standard',
        'schema_id',
        'EnumerateInstalledSkins',
        'PaintLanguageBarPreview',
        'ui_strings::kExtendedCharsetComingSoon',
        'WS_DISABLED'
    )) {
    if ($Settings -notmatch $Required) {
        throw "settings exe must use server-owned IME state protocol: $Required"
    }
}

if ($Settings -match 'ime-state\.json') {
    throw "settings exe must not read or write the private server state file directly."
}

Write-Host "Settings target uses shared server IME state verbs only."
