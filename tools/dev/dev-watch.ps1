param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [switch]$AutoRun,
    [switch]$Once,
    [string]$SimulatePath = "",
    [int]$DebounceMs = 500
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "dev-support.ps1")

$ServerRoot = Resolve-YuneWindowsDevFullPath (Join-Path $RepoRoot "src\server")
$TsfRoot = Resolve-YuneWindowsDevFullPath (Join-Path $RepoRoot "src\tsf")
$CandidateRoot = Resolve-YuneWindowsDevFullPath (Join-Path $RepoRoot "src\candidate_window")
$SchemaRoot = Resolve-YuneWindowsDevFullPath (Join-Path $YuneRoot "apps\yune-web\public\schema")

function Format-YuneWindowsDevWatchCommand {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string[]]$Arguments = @()
    )

    $Parts = [System.Collections.Generic.List[string]]::new()
    $Parts.Add("powershell") | Out-Null
    $Parts.Add("-NoProfile") | Out-Null
    $Parts.Add("-ExecutionPolicy") | Out-Null
    $Parts.Add("Bypass") | Out-Null
    $Parts.Add("-File") | Out-Null
    $Parts.Add("tools\dev\$ScriptName") | Out-Null
    foreach ($Argument in $Arguments) {
        if ($Argument.StartsWith("-", [System.StringComparison]::Ordinal)) {
            $Parts.Add($Argument) | Out-Null
        }
        else {
            $Parts.Add("`"$Argument`"") | Out-Null
        }
    }
    return ($Parts -join " ")
}

function Test-YuneWindowsDevPathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $FullPath = Resolve-YuneWindowsDevFullPath $Path
    $FullRoot = Resolve-YuneWindowsDevFullPath $Root
    if (-not $FullRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $FullRoot = $FullRoot + [System.IO.Path]::DirectorySeparatorChar
    }
    return $FullPath.StartsWith($FullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-YuneWindowsDevWatchRoute {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-YuneWindowsDevPathUnderRoot -Path $Path -Root $SchemaRoot) {
        $Args = @("-YuneRoot", $YuneRoot, "-RefreshSchema")
        return [pscustomobject]@{
            name = "server"
            reason = "schema change"
            script = Join-Path $PSScriptRoot "dev-reload-server.ps1"
            args = @("-YuneRoot", $YuneRoot, "-RefreshSchema")
            command = Format-YuneWindowsDevWatchCommand -ScriptName "dev-reload-server.ps1" -Arguments $Args
        }
    }

    if (Test-YuneWindowsDevPathUnderRoot -Path $Path -Root $ServerRoot) {
        $Args = @("-YuneRoot", $YuneRoot)
        return [pscustomobject]@{
            name = "server"
            reason = "server change"
            script = Join-Path $PSScriptRoot "dev-reload-server.ps1"
            args = @("-YuneRoot", $YuneRoot)
            command = Format-YuneWindowsDevWatchCommand -ScriptName "dev-reload-server.ps1" -Arguments $Args
        }
    }

    if ((Test-YuneWindowsDevPathUnderRoot -Path $Path -Root $TsfRoot) -or
        (Test-YuneWindowsDevPathUnderRoot -Path $Path -Root $CandidateRoot)) {
        $Args = @("-YuneRoot", $YuneRoot)
        return [pscustomobject]@{
            name = "tsf"
            reason = "TSF or candidate-window change"
            script = Join-Path $PSScriptRoot "dev-reload-tsf.ps1"
            args = @("-YuneRoot", $YuneRoot)
            command = Format-YuneWindowsDevWatchCommand -ScriptName "dev-reload-tsf.ps1" -Arguments $Args
        }
    }

    return $null
}

function Invoke-YuneWindowsDevWatchRoute {
    param(
        [Parameter(Mandatory = $true)][string]$ChangedPath,
        [Parameter(Mandatory = $true)]$Route
    )

    Write-Host "change: $ChangedPath"
    Write-Host "route: $($Route.name)"
    Write-Host "reason: $($Route.reason)"
    Write-Host "command: $($Route.command)"

    if ($AutoRun) {
        & $Route.script @($Route.args)
    }
    else {
        Write-Host "dry_run: true"
    }
}

if (-not (Test-Path -LiteralPath $ServerRoot -PathType Container)) {
    throw "missing server source directory: $ServerRoot"
}
if (-not (Test-Path -LiteralPath $TsfRoot -PathType Container)) {
    throw "missing TSF source directory: $TsfRoot"
}
if (-not (Test-Path -LiteralPath $CandidateRoot -PathType Container)) {
    throw "missing candidate-window source directory: $CandidateRoot"
}
if (-not (Test-Path -LiteralPath $SchemaRoot -PathType Container)) {
    throw "missing Yune schema source directory: $SchemaRoot"
}

if (-not [string]::IsNullOrWhiteSpace($SimulatePath)) {
    $Route = Get-YuneWindowsDevWatchRoute -Path $SimulatePath
    if (-not $Route) {
        throw "no dev-watch route for simulated path: $SimulatePath"
    }
    Invoke-YuneWindowsDevWatchRoute -ChangedPath (Resolve-YuneWindowsDevFullPath $SimulatePath) -Route $Route
    return
}

$WatchRoots = @($ServerRoot, $TsfRoot, $CandidateRoot, $SchemaRoot)
$Watchers = @()
try {
    foreach ($Root in $WatchRoots) {
        $Watcher = [System.IO.FileSystemWatcher]::new($Root)
        $Watcher.IncludeSubdirectories = $true
        $Watcher.EnableRaisingEvents = $true
        $Watchers += $Watcher
        Write-Host "watching: $Root"
    }

    while ($true) {
        foreach ($Watcher in $Watchers) {
            $Change = $Watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 250)
            if (-not $Change.TimedOut) {
                Start-Sleep -Milliseconds $DebounceMs
                $ChangedPath = Join-Path $Watcher.Path $Change.Name
                $Route = Get-YuneWindowsDevWatchRoute -Path $ChangedPath
                if ($Route) {
                    Invoke-YuneWindowsDevWatchRoute -ChangedPath $ChangedPath -Route $Route
                    if ($Once) {
                        return
                    }
                }
            }
        }
    }
}
finally {
    foreach ($Watcher in $Watchers) {
        $Watcher.Dispose()
    }
}
