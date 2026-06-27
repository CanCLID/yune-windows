param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerSourcePath = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
if (-not (Test-Path -LiteralPath $ServerSourcePath)) {
    throw "missing shared server source: $ServerSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $ServerSourcePath

foreach ($Required in @(
        'RimeStatus status = \{\};',
        'bool status_active = false',
        'status_active = true',
        'if \(status_active\)',
        'api_->free_status\(&status\);',
        'RimeContext context = \{\};',
        'bool context_active = false',
        'context_active = true',
        'if \(context_active\)',
        'api_->free_context\(&context\);'
    )) {
    if ($Source -notmatch $Required) {
        throw "shared server request path is missing Rime status/context cleanup guard pattern: $Required"
    }
}

Write-Host "Shared server request path frees Rime status/context buffers on success and exception paths."
