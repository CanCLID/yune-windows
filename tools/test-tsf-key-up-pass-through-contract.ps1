param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Method in @("OnTestKeyUp", "OnKeyUp")) {
    $Pattern = '(?s)STDMETHODIMP ' + $Method + '\(ITfContext\*, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?<body>.*?)\r?\n    \}'
    $Match = [regex]::Match($Source, $Pattern)
    if (-not $Match.Success) {
        throw "could not locate TSF $Method body"
    }

    $Body = $Match.Groups["body"].Value
    if ($Body -notmatch 'if \(!eaten\) \{\s+return E_INVALIDARG;\s+\}') {
        throw "$Method must reject null BOOL* eaten pointers before writing results."
    }

    if ($Body -match 'ShouldHandleKeyDown\(key\)') {
        throw "$Method must not reuse key-down composition handling for key-up events."
    }

    foreach ($Forbidden in @(
            'buffer_',
            'candidate_',
            'last_candidates_',
            'candidate_window_',
            'WriteStructuralEvent',
            'QueryServer',
            'CommitText'
        )) {
        if ($Body -match $Forbidden) {
            throw "$Method must not mutate composition, candidate, server, or structural-log state on key-up: $Forbidden."
        }
    }

    if ($Body -notmatch '\*eaten = FALSE;\s+return S_OK;') {
        throw "$Method must pass key-up events through after the null-output guard."
    }
}

Write-Host "TSF key-up handlers pass through without composition or evidence side effects."
