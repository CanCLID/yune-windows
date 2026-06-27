param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerSourcePath = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
if (-not (Test-Path -LiteralPath $ServerSourcePath)) {
    throw "missing shared server source: $ServerSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $ServerSourcePath

foreach ($Required in @(
        'bool session_active = true',
        'catch \(\.\.\.\)',
        'if \(session_active\)',
        'api_->destroy_session\(session\);',
        'session_active = false'
    )) {
    if ($Source -notmatch $Required) {
        throw "shared server request path is missing Yune session cleanup guard pattern: $Required"
    }
}

Write-Host "Shared server request path destroys Yune sessions on success and exception paths."
