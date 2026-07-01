$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallScript = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$Source = Get-Content -Raw -LiteralPath $UninstallScript

$Required = @(
    '[string]$ResultPath',
    'module_holders_before_remove',
    'module_holders_after_remove',
    'safe_module_hosts_stopped',
    'install_dir_removed',
    'machine_registration_absent',
    'pending_delete_scheduled',
    'pending_delete_paths',
    'requires_reboot',
    'MoveFileEx',
    'MOVEFILE_DELAY_UNTIL_REBOOT',
    'ConvertTo-Json'
)

foreach ($Pattern in $Required) {
    if ($Source -notmatch [regex]::Escape($Pattern)) {
        throw "Uninstaller structured cleanup result is missing required pattern: $Pattern"
    }
}

if ($Source -notmatch 'pass\s*=') {
    throw "Uninstaller result must include a boolean pass field."
}

Write-Host "Uninstaller writes structured cleanup result evidence."
