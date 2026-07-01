$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")

foreach ($Pattern in @(
        'CreateMutexW',
        'YuneWindowsServerSingleInstance',
        'ServerInstanceMutexName',
        'args.pipe_name',
        'ERROR_ALREADY_EXISTS',
        'YuneWindowsServer failed'
    )) {
    if ($ServerSource -notmatch [regex]::Escape($Pattern)) {
        throw "Shared server is missing single-instance guard pattern: $Pattern"
    }
}

Write-Host "Shared server exits cleanly when a per-user instance already exists."
