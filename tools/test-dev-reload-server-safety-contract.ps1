param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SupportScript = Join-Path $RepoRoot "tools\dev\dev-support.ps1"
$ReloadServerScript = Join-Path $RepoRoot "tools\dev\dev-reload-server.ps1"

foreach ($Path in @($SupportScript, $ReloadServerScript)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing script for dev server reload safety contract: $Path"
    }
}

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
$ReloadSource = Get-Content -Raw -LiteralPath $ReloadServerScript

foreach ($Required in @(
        'Backup-YuneWindowsDevPath',
        'Restore-YuneWindowsDevPathBackup',
        'Remove-YuneWindowsDevOldBackups'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "dev-support.ps1 must provide $Required for reload rollback/retention."
    }
}

foreach ($Required in @(
        '\[int\]\$BackupRetentionCount',
        'Backup-YuneWindowsDevPath(?s:.*)\$Paths\.schema_dir',
        'Backup-YuneWindowsDevPath(?s:.*)\$Paths\.user_data_dir',
        'Restore-YuneWindowsDevPathBackup(?s:.*)\$SchemaBackup',
        'Restore-YuneWindowsDevPathBackup(?s:.*)\$UserDataBackup',
        'Remove-YuneWindowsDevOldBackups',
        'Test-YuneWindowsDevServerReady',
        'already-running installed server',
        'start-yune-windows-server\.ps1'
    )) {
    if ($ReloadSource -notmatch $Required) {
        throw "dev-reload-server.ps1 is missing safety/race pattern: $Required"
    }
}

if ($ReloadSource -notmatch 'if \(\$RefreshSchema\) \{(?s:.*?)Stop-YuneWindowsDevProcessesByPath(?s:.*?)prepare-yune-product-data\.ps1') {
    throw "dev-reload-server.ps1 must stop the installed server before refreshing schema/user-data."
}

$TempRoot = Join-Path $env:TEMP ("yune-windows\dev-backup-contract-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N").Substring(0, 8))
$PathToProtect = Join-Path $TempRoot "schema"
$ChildPath = Join-Path $PathToProtect "file.txt"
New-Item -Path $PathToProtect -ItemType Directory -Force | Out-Null
Set-Content -LiteralPath $ChildPath -Encoding UTF8 -Value "before"

. $SupportScript
$Backup = Backup-YuneWindowsDevPath -Path $PathToProtect -Label "schema" -Timestamp "contract"
Set-Content -LiteralPath $ChildPath -Encoding UTF8 -Value "after"
Restore-YuneWindowsDevPathBackup -BackupPath $Backup.backup_path -Path $PathToProtect
$Restored = Get-Content -Raw -LiteralPath $ChildPath
if ($Restored.Trim() -ne "before") {
    throw "directory backup/restore helper did not restore original content."
}

Write-Host "Dev server reload safety contract covers schema rollback, ready existing server, and backup retention."
