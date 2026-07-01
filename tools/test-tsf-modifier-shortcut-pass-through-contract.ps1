param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Required in @(
        'Reset-TextSmokeClipboard',
        'SendWait\("\^a"\)',
        'SendWait\("\^c"\)'
    )) {
    $SmokeSource = (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-notepad-smoke.ps1")) +
        (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"))
    if ($SmokeSource -notmatch $Required) {
        throw "live text-smoke clipboard capture must keep using target-app shortcuts: $Required"
    }
}

if ($Source -notmatch 'bool IsShortcutModifierDown\(\)') {
    throw "TSF key handling must define a shortcut-modifier gate before eating letter keys."
}

foreach ($Required in @('VK_CONTROL', 'VK_MENU', 'VK_LWIN', 'VK_RWIN', 'GetKeyState')) {
    if ($Source -notmatch $Required) {
        throw "TSF shortcut-modifier gate is missing required key-state check: $Required"
    }
}

$ShouldHandleMatch = [regex]::Match(
    $Source,
    'bool ShouldHandleKeyDown\(WPARAM key\) const \{(?<body>[\s\S]*?)\r?\n    \}')
if (-not $ShouldHandleMatch.Success) {
    throw "could not locate TSF ShouldHandleKeyDown body."
}
$ShouldHandleBody = $ShouldHandleMatch.Groups["body"].Value
$ModifierIndex = $ShouldHandleBody.IndexOf("if (IsShortcutModifierDown())", [System.StringComparison]::Ordinal)
$LetterIndex = $ShouldHandleBody.IndexOf("if ((key >= L'A' && key <= L'Z')", [System.StringComparison]::Ordinal)
if ($ModifierIndex -lt 0 -or $LetterIndex -lt 0 -or $ModifierIndex -gt $LetterIndex) {
    throw "TSF key-test path must pass Ctrl/Alt/Windows letter shortcuts through before starting composition."
}

Write-Host "TSF key handling lets modified letter shortcuts pass through for clipboard evidence capture."
