param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-server-readiness-$ProcessId"
}

$StartScript = Join-Path $RepoRoot "tools\start-yune-windows-server.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$OutputServer = Join-Path $OutputDir "YuneWindowsServer.exe"
$PipeName = "\\.\pipe\yune-windows-ime-$ProcessId"

function Stop-TestServerFromOutputDir {
    Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
        Where-Object {
            $Path = [string]$_.Path
            $Path.Equals($OutputServer, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        Stop-Process -Force
}

Stop-TestServerFromOutputDir

$StartSource = Get-Content -Raw -LiteralPath $StartScript
foreach ($Required in @(
        '\[switch\]\$WaitForReady',
        '\[int\]\$ReadyTimeoutMs',
        '\[int\]\$ReadyTimeoutMs = 180000',
        'function Wait-YuneWindowsServerReady',
        'NamedPipeClientStream',
        'input=ngohaig',
        'commit=0',
        'schema_id',
        'jyut6ping3',
        'ExpectedCommitText',
        'FirstCandidateText',
        'candidate_count',
        'ReadAsync',
        'ReadTask\.Wait',
        'Stop-Process -Id \$Process.Id -Force'
    )) {
    if ($StartSource -notmatch $Required) {
        throw "start server script is missing readiness contract pattern: $Required"
    }
}
if ($StartSource -match '\$Client\.Read\(') {
    throw "start server script must use a bounded async pipe read during readiness checks."
}

foreach ($SmokeScript in @($NotepadSmoke, $ChromiumSmoke)) {
    $SmokeSource = Get-Content -Raw -LiteralPath $SmokeScript
    if ($SmokeSource -notmatch 'start-yune-windows-server\.ps1(?s:.*?)`[\r\n]\s+-WaitForReady') {
        throw "$(Split-Path -Leaf $SmokeScript) must start the server with -WaitForReady before typing."
    }
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$Process = $null
try {
    $Process = & $StartScript `
        -InstallDir $OutputDir `
        -PipeName $PipeName `
        -WaitForReady `
        -ReadyTimeoutMs 180000 `
        -PassThru
    if (-not $Process -or $Process.HasExited) {
        throw "server readiness start did not return a running process"
    }
}
finally {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
    }
    Stop-TestServerFromOutputDir
}

Write-Host "YuneWindows server start waits for a ready Yune named-pipe response."
