param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$ScratchRoot = "",
    [switch]$RefreshSchema,
    [int]$MaxCopyAttempts = 5,
    [int]$RetryDelayMs = 500,
    [int]$ReadyTimeoutMs = 180000,
    [int]$BackupRetentionCount = 3
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "dev-support.ps1")

function Restore-YuneWindowsDevServerBackup {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [int]$MaxCopyAttempts = 5,
        [int]$RetryDelayMs = 500
    )

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        return
    }

    for ($Attempt = 1; $Attempt -le $MaxCopyAttempts; $Attempt += 1) {
        try {
            Stop-YuneWindowsDevProcessesByPath `
                -Path $ServerPath `
                -ProcessName "YuneWindowsServer" `
                -TimeoutMs 10000 | Out-Null
            Copy-Item -LiteralPath $BackupPath -Destination $ServerPath -Force
            Write-Host "Restored installed server backup: $BackupPath"
            return
        }
        catch {
            if ($Attempt -eq $MaxCopyAttempts) {
                throw "failed to restore installed server backup after $Attempt attempt(s): $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds $RetryDelayMs
        }
    }
}

if ($MaxCopyAttempts -lt 1) {
    throw "-MaxCopyAttempts must be at least 1"
}

$Package = Get-YuneWindowsDevPackage -YuneRoot $YuneRoot
$Paths = Get-YuneWindowsDevInstallPaths -InstallDir $InstallDir
Test-YuneWindowsDevPath -Path $Paths.install_dir -Description "Yune Windows install directory" -PathType Container
Test-YuneWindowsDevPath -Path $Paths.server_exe -Description "installed YuneWindowsServer.exe" -PathType Leaf

$ScratchRoot = New-YuneWindowsDevScratchRoot -Purpose "dev-reload-server" -ScratchRoot $ScratchRoot
$BuildDir = Join-Path $ScratchRoot "build"
New-Item -Path $BuildDir -ItemType Directory -Force | Out-Null

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") `
    -OutputDir $BuildDir `
    -YuneRoot $Package.yune_root

$ScratchServer = Join-Path $BuildDir "YuneWindowsServer.exe"
Test-YuneWindowsDevPath -Path $ScratchServer -Description "scratch YuneWindowsServer.exe" -PathType Leaf

$Timestamp = New-YuneWindowsDevTimestamp
$Backup = $null
$BackupPath = ""
$SchemaBackup = $null
$UserDataBackup = $null

if ($RefreshSchema) {
    $SchemaBackup = Backup-YuneWindowsDevPath -Path $Paths.schema_dir -Label "schema" -Timestamp $Timestamp
    $UserDataBackup = Backup-YuneWindowsDevPath -Path $Paths.user_data_dir -Label "user-data" -Timestamp $Timestamp
    & (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
        -SourceSchemaDir $Package.schema_source_dir `
        -DestinationSchemaDir $Paths.schema_dir `
        -UserDataDir $Paths.user_data_dir
}

$StartedProcess = $null

try {
    $Backup = Backup-YuneWindowsDevPath -Path $Paths.server_exe -Label "server" -Timestamp $Timestamp
    $BackupPath = [string]$Backup.backup_path
    Write-Host "Backed up installed server: $BackupPath"

    $LastCopyError = ""
    for ($Attempt = 1; $Attempt -le $MaxCopyAttempts; $Attempt += 1) {
        try {
            $Stopped = @(Stop-YuneWindowsDevProcessesByPath `
                    -Path $Paths.server_exe `
                    -ProcessName "YuneWindowsServer" `
                    -TimeoutMs 10000)
            if ($Stopped.Count -gt 0) {
                Write-Host "Stopped installed server process(es): $(Format-YuneWindowsDevProcessSummary -Processes $Stopped)"
            }

            Copy-Item -LiteralPath $ScratchServer -Destination $Paths.server_exe -Force
            Write-Host "Copied scratch YuneWindowsServer.exe into $($Paths.install_dir)"
            $LastCopyError = ""
            break
        }
        catch {
            $LastCopyError = $_.Exception.Message
            if ($Attempt -eq $MaxCopyAttempts) {
                throw "failed to copy scratch server after $Attempt attempt(s): $LastCopyError"
            }
            Write-Warning "server copy attempt $Attempt failed; retrying after stopping any relaunched installed server. $LastCopyError"
            Start-Sleep -Milliseconds $RetryDelayMs
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LastCopyError)) {
        throw "server copy did not complete: $LastCopyError"
    }

    $ExistingInstalledServers = @(Get-YuneWindowsDevProcessesByPath `
            -Path $Paths.server_exe `
            -ProcessName "YuneWindowsServer")
    foreach ($Existing in $ExistingInstalledServers) {
        $ExistingProcess = Get-Process -Id ([int]$Existing.process_id) -ErrorAction SilentlyContinue
        if ($ExistingProcess -and (Test-YuneWindowsDevServerReady -Process $ExistingProcess -TimeoutMs $ReadyTimeoutMs)) {
            $StartedProcess = $ExistingProcess
            Write-Host "Using already-running installed server PID $($StartedProcess.Id); readiness passed."
            break
        }
    }

    if (-not $StartedProcess) {
        if ($ExistingInstalledServers.Count -gt 0) {
            Write-Host "Stopping already-running installed server process(es) that were not ready: $(Format-YuneWindowsDevProcessSummary -Processes $ExistingInstalledServers)"
            Stop-YuneWindowsDevProcessesByPath `
                -Path $Paths.server_exe `
                -ProcessName "YuneWindowsServer" `
                -TimeoutMs 10000 | Out-Null
        }

        # A foreground keystroke can auto-relaunch the installed server between
        # the path check and explicit start. Keep that as a bounded readiness
        # failure instead of broadening process ownership.
        $StartedProcess = & (Join-Path $RepoRoot "tools\start-yune-windows-server.ps1") `
            -YuneRoot $Package.yune_root `
            -InstallDir $Paths.install_dir `
            -WaitForReady `
            -ReadyTimeoutMs $ReadyTimeoutMs `
            -PassThru
    }
    if (-not $StartedProcess -or $StartedProcess.HasExited) {
        throw "installed server restart did not return a running process"
    }

    Write-Host "Reloaded installed server PID $($StartedProcess.Id); readiness passed."
    Write-Host "Backup retained: $BackupPath"

    Remove-YuneWindowsDevOldBackups -Directory $Paths.install_dir -Filter "YuneWindowsServer.exe.dev-backup-*" -RetainCount $BackupRetentionCount | Out-Null
    Remove-YuneWindowsDevOldBackups -Directory $Paths.install_dir -Filter "schema.dev-backup-*" -RetainCount $BackupRetentionCount | Out-Null
    Remove-YuneWindowsDevOldBackups -Directory $Paths.install_dir -Filter "user-data.dev-backup-*" -RetainCount $BackupRetentionCount | Out-Null
}
catch {
    $ReloadError = $_.Exception.Message
    try {
        if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
            Restore-YuneWindowsDevServerBackup `
                -BackupPath $BackupPath `
                -ServerPath $Paths.server_exe `
                -MaxCopyAttempts $MaxCopyAttempts `
                -RetryDelayMs $RetryDelayMs
        }
        if ($RefreshSchema) {
            if ($SchemaBackup -and $SchemaBackup.existed) {
                Restore-YuneWindowsDevPathBackup -BackupPath $SchemaBackup.backup_path -Path $Paths.schema_dir
            }
            elseif ($SchemaBackup -and (Test-Path -LiteralPath $Paths.schema_dir)) {
                Remove-Item -LiteralPath $Paths.schema_dir -Recurse -Force
            }
            if ($UserDataBackup -and $UserDataBackup.existed) {
                Restore-YuneWindowsDevPathBackup -BackupPath $UserDataBackup.backup_path -Path $Paths.user_data_dir
            }
            elseif ($UserDataBackup -and (Test-Path -LiteralPath $Paths.user_data_dir)) {
                Remove-Item -LiteralPath $Paths.user_data_dir -Recurse -Force
            }
        }
    }
    catch {
        throw "server reload failed: $ReloadError. Backup restore also failed: $($_.Exception.Message)"
    }
    throw "server reload failed and installed server backup was restored: $ReloadError"
}
