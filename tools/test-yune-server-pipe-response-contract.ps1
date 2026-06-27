param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerSourcePath = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
if (-not (Test-Path -LiteralPath $ServerSourcePath)) {
    throw "missing shared server source: $ServerSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $ServerSourcePath
$ServeOnceMatch = [regex]::Match($Source, '(?s)void ServeOnce\(const Args& args, YuneRuntime& runtime\)\s*\{(?<body>.*?)\n\}\s*// namespace')
if (-not $ServeOnceMatch.Success) {
    throw "shared server source is missing ServeOnce"
}

$ServeOnce = $ServeOnceMatch.Groups["body"].Value
foreach ($Required in @(
        'try\s*\{',
        'catch \(\.\.\.\)',
        'DisconnectNamedPipe\(pipe\);',
        'CloseHandle\(pipe\);',
        'pipe = INVALID_HANDLE_VALUE;',
        'bytes_written == response\.size\(\)',
        'incomplete pipe response write',
        'FlushFileBuffers\(pipe\) == TRUE'
    )) {
    if ($ServeOnce -notmatch $Required) {
        throw "shared server ServeOnce is missing pipe/response lifecycle pattern: $Required"
    }
}

Write-Host "Shared server pipe lifecycle closes handles on failures and rejects partial response writes."
