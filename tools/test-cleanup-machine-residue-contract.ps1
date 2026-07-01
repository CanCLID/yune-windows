param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

$CleanState = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = '{"registered":false,"active":false}'
    profile_state_verified = $true
    server_processes = @()
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
}

$CleanResult = Test-YuneWindowsCleanupState `
    -Snapshot $CleanState `
    -RequireProfileState `
    -RequireMachineResidueCheck
if ($CleanResult.pass -ne $true) {
    throw "expected clean synthetic machine-residue state to pass cleanup validation"
}

$MissingMachineCheck = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = '{"registered":false,"active":false}'
    profile_state_verified = $true
    server_processes = @()
}
$MissingMachineCheckResult = Test-YuneWindowsCleanupState `
    -Snapshot $MissingMachineCheck `
    -RequireProfileState `
    -RequireMachineResidueCheck
if ($MissingMachineCheckResult.pass -ne $false -or
    ($MissingMachineCheckResult.issues -notcontains "Machine-state residue check was not verified")) {
    throw "cleanup validation must fail when machine-state residue was not checked"
}

$DirtyMachineState = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = '{"registered":false,"active":false}'
    profile_state_verified = $true
    server_processes = @()
    machine_state_checked = $true
    machine_state_issues = @("COM CLSID registry key remains")
    filesystem_leftovers = @()
}
$DirtyMachineResult = Test-YuneWindowsCleanupState `
    -Snapshot $DirtyMachineState `
    -RequireProfileState `
    -RequireMachineResidueCheck
if ($DirtyMachineResult.pass -ne $false -or
    ($DirtyMachineResult.issues -notcontains "Machine-state cleanup issue: COM CLSID registry key remains")) {
    throw "cleanup validation must fail on recorded machine-state residue"
}

$DirtyFilesystemState = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state = '{"registered":false,"active":false}'
    profile_state_verified = $true
    server_processes = @()
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
}
$DirtyFilesystemResult = Test-YuneWindowsCleanupState `
    -Snapshot $DirtyFilesystemState `
    -RequireProfileState `
    -RequireMachineResidueCheck
if ($DirtyFilesystemResult.pass -ne $false -or
    ($DirtyFilesystemResult.issues -notcontains "Filesystem cleanup leftover: C:\Windows\System32\YuneWindows.dll.old.0")) {
    throw "cleanup validation must fail on recorded filesystem leftovers"
}

$StringTypedCleanState = [pscustomobject]@{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = "false"
    profile_tool_exists = "false"
    profile_state = '{"registered":"false","active":"false"}'
    profile_state_verified = "true"
    server_processes = @()
    machine_state_checked = "true"
    machine_state_issues = @()
    filesystem_leftovers = @()
}
$StringTypedCleanResult = Test-YuneWindowsCleanupState `
    -Snapshot $StringTypedCleanState `
    -RequireProfileState `
    -RequireMachineResidueCheck
if ($StringTypedCleanResult.pass -ne $false) {
    throw "cleanup validation must fail when clean-looking state booleans are JSON strings"
}

$SupportSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\live-smoke-support.ps1")
foreach ($Required in @(
        "IncludeMachineResidue",
        "PendingFileRenameOperations",
        "RequireMachineResidueCheck")) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke support is missing machine-residue cleanup pattern: $Required"
    }
}

$RegistryKeys = @(Get-YuneWindowsMachineResidueRegistryKeys)
foreach ($RequiredRegistryKey in @(
        "Registry::HKEY_CLASSES_ROOT\CLSID\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\LanguageProfile\0x00000c04\{3AE69B8D-19B4-4267-8F21-E239666D6632}",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\LanguageProfile\0x00000c04\{3AE69B8D-19B4-4267-8F21-E239666D6632}")) {
    if ($RegistryKeys -notcontains $RequiredRegistryKey) {
        throw "live smoke support is missing machine-residue registry key: $RequiredRegistryKey"
    }
}

$LiveSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1")
foreach ($Required in @(
        "-IncludeMachineResidue",
        "-RequireMachineResidueCheck")) {
    if ($LiveSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke orchestrator is missing machine-residue cleanup pattern: $Required"
    }
}

Write-Host "Cleanup validation requires approved machine-state and filesystem residue checks."
