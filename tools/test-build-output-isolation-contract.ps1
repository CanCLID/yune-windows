param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$BuildSmokeScripts = @(
    "tools\build-tsf-shell.ps1",
    "tools\test-candidate-window-smoke.ps1",
    "tools\test-start-server-readiness-contract.ps1",
    "tools\test-tsf-shell-build.ps1",
    "tools\test-tsf-candidate-window-integration.ps1",
    "tools\test-yune-server-ipc-smoke.ps1"
)

foreach ($RelativePath in $BuildSmokeScripts) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing build-smoke script: $RelativePath"
    }
    $Source = Get-Content -Raw -LiteralPath $Path
    if ($Source -match 'Join-Path\s+\$env:TEMP\s+"yune-windows\\m01-(tsf|server-readiness)"') {
        throw "$RelativePath must not default to a shared m01 build directory."
    }
    if ($Source -notmatch 'GetCurrentProcess\(\)\.Id') {
        throw "$RelativePath must include the current process id in its default build output directory."
    }
}

$ReadinessSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\test-start-server-readiness-contract.ps1")
if ($ReadinessSource -notmatch '\$PipeName\s*=\s*"\\\\\.\\pipe\\yune-windows-ime-\$ProcessId"') {
    throw "tools\test-start-server-readiness-contract.ps1 must use a process-specific readiness pipe name."
}
if ($ReadinessSource -notmatch '-PipeName\s+\$PipeName') {
    throw "tools\test-start-server-readiness-contract.ps1 must pass its process-specific pipe name to start-yune-windows-server.ps1."
}

$IpcSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\test-yune-server-ipc-smoke.ps1")
if ($IpcSource -notmatch '\$PipeLeaf\s*=\s*"yune-windows-ime-\$ProcessId"') {
    throw "tools\test-yune-server-ipc-smoke.ps1 must use a process-specific IPC pipe name."
}

Write-Host "Build-smoke scripts use isolated default output directories and test pipe names."
