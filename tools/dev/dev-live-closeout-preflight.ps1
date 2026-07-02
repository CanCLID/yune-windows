param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [switch]$RestartExplorerPlanned,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dev-support.ps1")

$Paths = Get-YuneWindowsDevInstallPaths -InstallDir $InstallDir
Test-YuneWindowsDevPath -Path $Paths.install_dir -Description "Yune Windows install directory" -PathType Container
Test-YuneWindowsDevPath -Path $Paths.tsf_dll -Description "installed YuneWindowsTSF.dll" -PathType Leaf

$Holders = @(Get-YuneWindowsDevProcessesUsingModule -ModulePath $Paths.tsf_dll)
$BlockingHolders = if ($RestartExplorerPlanned) {
    @($Holders | Where-Object { [string]$_.process_name -ne "explorer" })
}
else {
    @($Holders)
}

$Result = [pscustomobject]@{
    install_dir = $Paths.install_dir
    tsf_dll = $Paths.tsf_dll
    restart_explorer_planned = [bool]$RestartExplorerPlanned
    holder_count = $Holders.Count
    holders = @($Holders)
    blocking_holder_count = $BlockingHolders.Count
    blocking_holders = @($BlockingHolders)
    ready_for_tsf_swap = ($BlockingHolders.Count -eq 0)
}

if ($Json) {
    $Result | ConvertTo-Json -Depth 5
}
else {
    Write-Host "Installed TSF DLL: $($Paths.tsf_dll)"
    Write-Host "All holders: $(Format-YuneWindowsDevProcessSummary -Processes $Holders)"
    if ($RestartExplorerPlanned) {
        Write-Host "Explorer holders are allowed because -RestartExplorerPlanned was supplied."
    }
    Write-Host "Blocking holders: $(Format-YuneWindowsDevProcessSummary -Processes $BlockingHolders)"
}

if ($BlockingHolders.Count -gt 0) {
    throw "TSF DLL holder(s) remain; close them before live reload: $(Format-YuneWindowsDevProcessSummary -Processes $BlockingHolders)"
}

if (-not $Json) {
    Write-Host "M06/M07 live closeout preflight passed: installed TSF DLL is ready for the holder-free dev reload."
}
