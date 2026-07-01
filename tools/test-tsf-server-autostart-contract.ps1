$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $TsfSource

$Required = @(
    'RequestSharedServerLaunch',
    'CreateProcessW',
    'YuneWindowsServer.exe',
    'rime.dll',
    'schema',
    'user-data',
    'WaitNamedPipeW',
    'ERROR_PIPE_BUSY',
    'ERROR_FILE_NOT_FOUND',
    'kServerPipeMissingRetrySleepMs',
    'kServerLaunchReadyWaitMs',
    'Sleep(kServerPipeMissingRetrySleepMs)',
    'server_query_pipe_busy',
    'server_launch_attempt',
    'server_launch_started',
    'server_launch_ready',
    'server_launch_pending',
    'server_launch_timeout',
    'server_launch_exited',
    'server_launch_failed',
    'server_launch_skipped_restricted_host'
)

foreach ($Pattern in $Required) {
    if ($Source -notmatch [regex]::Escape($Pattern)) {
        throw "TSF server autostart source is missing required pattern: $Pattern"
    }
}

$Forbidden = @(
    'ShellExecute',
    'powershell',
    'schtasks',
    'SERVICE_WIN32',
    'HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
)

foreach ($Pattern in $Forbidden) {
    if ($Source -match [regex]::Escape($Pattern)) {
        throw "TSF server autostart must not use persistent or shell-based launch path: $Pattern"
    }
}

Write-Host "TSF owns bounded on-demand YuneWindowsServer startup."
