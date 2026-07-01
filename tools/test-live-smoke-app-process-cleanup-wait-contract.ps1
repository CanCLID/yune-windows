param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Require-Pattern {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Reason
    )

    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing file: $RelativePath"
    }
    $Source = Get-Content -Raw -LiteralPath $Path
    if ($Source -notmatch $Pattern) {
        throw "$RelativePath is missing $Reason"
    }
}

Require-Pattern `
    -RelativePath "tools\run-notepad-smoke.ps1" `
    -Pattern 'Stop-Process\s+-Id\s+\$Notepad\.Id\s+-Force(?s:.*?)Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$Notepad\.Id' `
    -Reason "wait after stopping Notepad"

Require-Pattern `
    -RelativePath "tools\run-notepad-smoke.ps1" `
    -Pattern 'foreach\s+\(\$InstalledServerProcess\s+in\s+@\(Get-YuneWindowsInstalledServerProcesses(?s:.*?)Stop-Process\s+-Id\s+\$InstalledServerProcess\.Id\s+-Force(?s:.*?)Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$InstalledServerProcess\.Id' `
    -Reason "wait after stopping installed product-owned server processes"

Require-Pattern `
    -RelativePath "tools\run-chromium-smoke.ps1" `
    -Pattern 'foreach\s+\(\$InstalledServerProcess\s+in\s+@\(Get-YuneWindowsInstalledServerProcesses(?s:.*?)Stop-Process\s+-Id\s+\$InstalledServerProcess\.Id\s+-Force(?s:.*?)Wait-YuneWindowsProcessExit\s+-ProcessId\s+\$InstalledServerProcess\.Id' `
    -Reason "wait after stopping installed product-owned server processes"

Write-Host "Live app smokes wait for Notepad and installed product-owned server process exit before post-smoke cleanup continues."
