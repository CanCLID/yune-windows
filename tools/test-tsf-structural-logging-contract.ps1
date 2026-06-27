param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Required in @(
        'WriteStructuralEvent',
        'tsf-events\.log',
        'event=',
        'sequence=',
        'buffer_length=',
        'candidate_count=',
        'key_down',
        'candidate_update',
        'commit_request',
        'commit_text',
        'focus_lost',
        'profile_deactivate'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF source is missing structural logging pattern: $Required"
    }
}

foreach ($Forbidden in @(
        'tsf-events\.log(?s:.*)<<\s*buffer_(?!length)',
        'tsf-events\.log(?s:.*)<<\s*candidate_(?!count)'
    )) {
    if ($Source -match $Forbidden) {
        throw "TSF structural logging must not write private composition or candidate text: $Forbidden"
    }
}

Write-Host "TSF structural logging records event names and counts without typed content."
