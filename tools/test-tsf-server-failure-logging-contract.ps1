param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Required in @(
        'bool ok = false;',
        'result\.ok = true;',
        'server_query_failed',
        'WriteStructuralEvent\("server_query_failed",\s*static_cast<int>\(input\.size\(\)\)'
    )) {
    if ($Source -notmatch $Required) {
        throw "TSF source is missing server-failure logging pattern: $Required"
    }
}

$FailureEventLines = @(Select-String -LiteralPath $TsfSource -Pattern 'server_query_failed' |
        ForEach-Object { $_.Line.Trim() })
foreach ($Line in $FailureEventLines) {
    if ($Line -match 'Narrow|request|commit_text|candidate') {
        throw "TSF server-failure logging must not write approved typed input: $Line"
    }
}

Write-Host "TSF server IPC failures are logged structurally without typed content."
