param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$ScratchRoot = "",
    [string]$StatePath = "",
    [switch]$RestartExplorer,
    [int]$HolderTimeoutMs = 10000
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "dev-support.ps1")

function ConvertTo-YuneWindowsDevStateDateTime {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    try {
        return [DateTime]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        return $null
    }
}

function Get-YuneWindowsDevOwnedTestProcess {
    param([string]$StatePath)

    $State = Read-YuneWindowsDevJsonFile -Path $StatePath
    if (-not $State) {
        return $null
    }
    if ([string]$State.owner -ne "yune-windows-dev-test-window") {
        return $null
    }
    $ProcessId = [int]$State.process_id
    $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $Process) {
        return $null
    }
    if ([string]$Process.ProcessName -ne [string]$State.process_name) {
        return $null
    }

    $RecordedPath = [string]$State.process_path
    if (-not [string]::IsNullOrWhiteSpace($RecordedPath)) {
        $ActualPath = ""
        try {
            $ActualPath = [string]$Process.Path
        }
        catch {
        }
        if ([string]::IsNullOrWhiteSpace($ActualPath)) {
            return $null
        }
        $RecordedPath = Resolve-YuneWindowsDevFullPath $RecordedPath
        $ActualPath = Resolve-YuneWindowsDevFullPath $ActualPath
        if (-not [string]::Equals($RecordedPath, $ActualPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
    }

    $RecordedStartTime = ConvertTo-YuneWindowsDevStateDateTime -Value ([string]$State.process_start_time)
    if ($RecordedStartTime) {
        $StartDelta = New-TimeSpan -Start $RecordedStartTime -End $Process.StartTime
        if ([Math]::Abs($StartDelta.TotalSeconds) -gt 2) {
            return $null
        }
    }

    $LaunchedAt = ConvertTo-YuneWindowsDevStateDateTime -Value ([string]$State.launched_at)
    if ($LaunchedAt) {
        $LaunchDelta = New-TimeSpan -Start $Process.StartTime -End $LaunchedAt
        if ($LaunchDelta.TotalSeconds -lt -2) {
            return $null
        }
    }

    return [pscustomobject]@{
        process_id = $ProcessId
        process_name = [string]$Process.ProcessName
        process_path = $RecordedPath
        process_start_time = if ($RecordedStartTime) { $RecordedStartTime.ToString("o") } else { "" }
        launched_at = if ($LaunchedAt) { $LaunchedAt.ToString("o") } else { "" }
    }
}

function Stop-YuneWindowsDevOwnedTestProcess {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [int]$TimeoutMs = 10000
    )

    $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $Process) {
        return
    }

    try {
        if ($Process.MainWindowHandle -ne 0) {
            $null = $Process.CloseMainWindow()
        }
    }
    catch {
    }

    if (-not (Wait-YuneWindowsDevProcessExit -ProcessId $ProcessId -TimeoutMs $TimeoutMs)) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        Wait-YuneWindowsDevProcessExit -ProcessId $ProcessId -TimeoutMs $TimeoutMs -RequireExit | Out-Null
    }
}

function Restore-YuneWindowsDevTsfBackup {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$TsfPath
    )

    if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
        Copy-Item -LiteralPath $BackupPath -Destination $TsfPath -Force
        Write-Host "Restored TSF DLL backup: $BackupPath"
    }
}

function Assert-YuneWindowsDevNoUnsafeTsfHolders {
    param(
        [Parameter(Mandatory = $true)][string]$TsfPath,
        [int]$AllowedProcessId = 0,
        [switch]$RestartExplorer,
        [int]$TimeoutMs = 10000
    )

    $Holders = @(Get-YuneWindowsDevProcessesUsingModule -ModulePath $TsfPath)
    $Unsafe = @($Holders | Where-Object { [int]$_.process_id -ne $AllowedProcessId })

    $ExplorerHolders = @($Unsafe | Where-Object { [string]$_.process_name -eq "explorer" })
    $OtherUnsafe = @($Unsafe | Where-Object { [string]$_.process_name -ne "explorer" })

    if ($ExplorerHolders.Count -gt 0 -and $RestartExplorer -and $OtherUnsafe.Count -eq 0) {
        foreach ($Holder in $ExplorerHolders) {
            Stop-Process -Id ([int]$Holder.process_id) -Force -ErrorAction SilentlyContinue
            Wait-YuneWindowsDevProcessExit -ProcessId ([int]$Holder.process_id) -TimeoutMs $TimeoutMs -RequireExit | Out-Null
        }
        Start-Process -FilePath "explorer.exe" | Out-Null
        $Holders = @(Get-YuneWindowsDevProcessesUsingModule -ModulePath $TsfPath)
        $Unsafe = @($Holders | Where-Object { [int]$_.process_id -ne $AllowedProcessId })
    }

    if ($Unsafe.Count -gt 0) {
        throw "unsafe TSF DLL holder(s) remain; close them before reload: $(Format-YuneWindowsDevProcessSummary -Processes $Unsafe)"
    }
}

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = $script:YuneWindowsDevDefaultTestWindowStatePath
}

$Package = Get-YuneWindowsDevPackage -YuneRoot $YuneRoot
$Paths = Get-YuneWindowsDevInstallPaths -InstallDir $InstallDir
Test-YuneWindowsDevPath -Path $Paths.install_dir -Description "Yune Windows install directory" -PathType Container
Test-YuneWindowsDevPath -Path $Paths.tsf_dll -Description "installed YuneWindowsTSF.dll" -PathType Leaf

$ScratchRoot = New-YuneWindowsDevScratchRoot -Purpose "dev-reload-tsf" -ScratchRoot $ScratchRoot
$BuildDir = Join-Path $ScratchRoot "build"
New-Item -Path $BuildDir -ItemType Directory -Force | Out-Null

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") `
    -OutputDir $BuildDir `
    -YuneRoot $Package.yune_root

$ScratchTsfDll = Join-Path $BuildDir "YuneWindowsTSF.dll"
Test-YuneWindowsDevPath -Path $ScratchTsfDll -Description "scratch YuneWindowsTSF.dll" -PathType Leaf

$DevOwnedProcess = Get-YuneWindowsDevOwnedTestProcess -StatePath $StatePath
$AllowedProcessId = 0
if ($DevOwnedProcess) {
    $AllowedProcessId = [int]$DevOwnedProcess.process_id
}
Assert-YuneWindowsDevNoUnsafeTsfHolders `
    -TsfPath $Paths.tsf_dll `
    -AllowedProcessId $AllowedProcessId `
    -RestartExplorer:$RestartExplorer `
    -TimeoutMs $HolderTimeoutMs

if ($DevOwnedProcess) {
    Write-Host "Closing dev-owned test window PID $($DevOwnedProcess.process_id)."
    Stop-YuneWindowsDevOwnedTestProcess -ProcessId ([int]$DevOwnedProcess.process_id) -TimeoutMs $HolderTimeoutMs
}

$Deadline = [DateTime]::UtcNow.AddMilliseconds($HolderTimeoutMs)
while ([DateTime]::UtcNow -lt $Deadline) {
    $Remaining = @(Get-YuneWindowsDevProcessesUsingModule -ModulePath $Paths.tsf_dll)
    if ($Remaining.Count -eq 0) {
        break
    }
    Start-Sleep -Milliseconds 100
}

$RemainingAfterWait = @(Get-YuneWindowsDevProcessesUsingModule -ModulePath $Paths.tsf_dll)
if ($RemainingAfterWait.Count -gt 0) {
    throw "TSF DLL is still held after closing dev-owned test app: $(Format-YuneWindowsDevProcessSummary -Processes $RemainingAfterWait)"
}

$BackupPath = "$($Paths.tsf_dll).dev-backup-$(New-YuneWindowsDevTimestamp)"
Copy-Item -LiteralPath $Paths.tsf_dll -Destination $BackupPath -Force
Write-Host "Backed up installed TSF DLL: $BackupPath"

try {
    Copy-Item -LiteralPath $ScratchTsfDll -Destination $Paths.tsf_dll -Force
    Write-Host "Copied YuneWindowsTSF.dll into $($Paths.install_dir)"

    $ScratchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ScratchTsfDll).Hash
    $InstalledHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Paths.tsf_dll).Hash
    if ($ScratchHash -ne $InstalledHash) {
        throw "installed TSF DLL hash does not match scratch build"
    }

    Write-Host "TSF DLL swap validated."
}
catch {
    $SwapError = $_.Exception.Message
    Restore-YuneWindowsDevTsfBackup -BackupPath $BackupPath -TsfPath $Paths.tsf_dll
    throw "TSF DLL reload failed and rollback was attempted: $SwapError"
}

& (Join-Path $PSScriptRoot "dev-test-window.ps1") -StatePath $StatePath
