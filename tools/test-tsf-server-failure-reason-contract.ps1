$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $TsfSource

$RequiredEvents = @(
    'server_query_connect_failed',
    'server_query_pipe_busy',
    'server_query_call_failed',
    'server_query_write_failed',
    'server_query_read_timeout',
    'server_query_invalid_response'
)

foreach ($EventName in $RequiredEvents) {
    if ($Source -notmatch "WriteStructuralEvent\(`"$([regex]::Escape($EventName))`"") {
        throw "TSF query path must log structural event $EventName"
    }
}

foreach ($Forbidden in @(
        'WriteStructuralEvent\([^;]*Narrow\(input\)',
        'WriteStructuralEvent\([^;]*\brequest\b',
        'log << input',
        'log << Narrow\(input\)'
    )) {
    if ($Source -match $Forbidden) {
        throw "TSF structural logging must not write typed input content: $Forbidden"
    }
}

if ($Source -notmatch 'return ServerQueryFailure\(input\);') {
    throw "TSF query path must keep the universal server_query_failed return for existing timeout-ordering contracts."
}

if ($Source -notmatch 'error_code=') {
    throw "TSF structural logging must include an error_code field for generic Windows IPC failures."
}

Write-Host "TSF server query failures are reason-specific and structural."
