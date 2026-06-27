param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-live-preflight-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$InstallDir = Join-Path $OutputDir "install-target"
$OrchestratorReport = Join-Path $OutputDir "live-preflight.json"
$InstallReport = Join-Path $OutputDir "install-preflight.json"
$CleanResiduePath = Join-Path $OutputDir "clean-current-residue.json"
$DirtyResiduePath = Join-Path $OutputDir "dirty-current-residue.json"

[ordered]@{
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $CleanResiduePath -Encoding utf8

[ordered]@{
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $DirtyResiduePath -Encoding utf8

& (Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1") `
    -InstallDir $InstallDir `
    -PreflightOnly `
    -PreflightPath $OrchestratorReport `
    -CurrentResiduePath $CleanResiduePath
if (-not (Test-Path -LiteralPath $OrchestratorReport)) {
    throw "live preflight did not write $OrchestratorReport"
}

& (Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1") `
    -InstallDir $InstallDir `
    -PreflightOnly `
    -PreflightPath $InstallReport `
    -CurrentResiduePath $CleanResiduePath
if (-not (Test-Path -LiteralPath $InstallReport)) {
    throw "install preflight did not write $InstallReport"
}

if (Test-Path -LiteralPath $InstallDir) {
    throw "preflight created the install directory: $InstallDir"
}

$Live = Get-Content -Raw -LiteralPath $OrchestratorReport | ConvertFrom-Json
$Install = Get-Content -Raw -LiteralPath $InstallReport | ConvertFrom-Json

foreach ($Report in @($Live, $Install)) {
    if ($Report.machine_state_changed -ne $false) {
        throw "preflight report must state machine_state_changed=false"
    }
    if ($Report.machine_state_checked -ne $true) {
        throw "preflight report must state machine_state_checked=true"
    }
    if ($Report.machine_residue_source -ne [System.IO.Path]::GetFullPath($CleanResiduePath)) {
        throw "preflight report must record supplied machine residue source"
    }
    if ($null -eq $Report.PSObject.Properties["machine_state_issues"]) {
        throw "preflight report must include machine_state_issues"
    }
    if (@($Report.machine_state_issues).Count -ne @($Report.machine_state_issues | Select-Object -Unique).Count) {
        throw "preflight report must not duplicate machine-state residue entries"
    }
    if ($null -eq $Report.PSObject.Properties["filesystem_leftovers"]) {
        throw "preflight report must include filesystem_leftovers"
    }
    if (@($Report.filesystem_leftovers).Count -ne @($Report.filesystem_leftovers | Select-Object -Unique).Count) {
        throw "preflight report must not duplicate filesystem leftover entries"
    }
    if ($Report.install_dir_exists -ne $false) {
        throw "preflight report must state install_dir_exists=false for a fresh target"
    }
    if ((@($Report.machine_state_issues).Count -gt 0 -or @($Report.filesystem_leftovers).Count -gt 0) -and
        $Report.ready_for_live_smoke -ne $false) {
        throw "preflight report must not be ready when machine-state or filesystem residue is present"
    }
    if ($null -eq $Report.server_process_count) {
        throw "preflight report must include server_process_count"
    }
    if ($Report.yune_runtime_exists -ne $true) {
        throw "preflight report must find packaged Yune runtime"
    }
    if ($Report.yune_schema_exists -ne $true) {
        throw "preflight report must find Yune schema data"
    }
    if ($null -eq $Report.is_administrator) {
        throw "preflight report must include is_administrator"
    }
}

$DirtyResidueReportPath = Join-Path $OutputDir "dirty-residue-live-preflight.json"
& (Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1") `
    -InstallDir $InstallDir `
    -PreflightOnly `
    -PreflightPath $DirtyResidueReportPath `
    -CurrentResiduePath $DirtyResiduePath
if (-not (Test-Path -LiteralPath $DirtyResidueReportPath)) {
    throw "dirty residue live preflight did not write $DirtyResidueReportPath"
}
$DirtyResidue = Get-Content -Raw -LiteralPath $DirtyResidueReportPath | ConvertFrom-Json
if ($DirtyResidue.ready_for_live_smoke -ne $false) {
    throw "preflight report must not be ready for live smoke when supplied residue evidence is dirty"
}
if (@($DirtyResidue.machine_state_issues).Count -ne 1 -or
    @($DirtyResidue.filesystem_leftovers).Count -ne 1) {
    throw "preflight report must copy supplied dirty residue arrays"
}

if ($null -eq $Live.is_sta) {
    throw "live preflight report must include is_sta"
}
if ($null -eq $Live.browser_available) {
    throw "live preflight report must include browser_available"
}

New-Item -ItemType Directory -Force $InstallDir | Out-Null
$DirtyReportPath = Join-Path $OutputDir "dirty-install-preflight.json"
& (Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1") `
    -InstallDir $InstallDir `
    -PreflightOnly `
    -PreflightPath $DirtyReportPath `
    -CurrentResiduePath $CleanResiduePath
if (-not (Test-Path -LiteralPath $DirtyReportPath)) {
    throw "dirty install preflight did not write $DirtyReportPath"
}
$DirtyInstall = Get-Content -Raw -LiteralPath $DirtyReportPath | ConvertFrom-Json
if ($DirtyInstall.machine_state_changed -ne $false) {
    throw "dirty install preflight must remain non-mutating"
}
if ($DirtyInstall.machine_state_checked -ne $true) {
    throw "dirty install preflight must still record machine-state residue checks"
}
if ($DirtyInstall.install_dir_exists -ne $true) {
    throw "preflight report must state install_dir_exists=true for an occupied target"
}
if ($DirtyInstall.ready_for_live_smoke -ne $false) {
    throw "preflight report must not be ready for live smoke when install target already exists"
}

Write-Host "Live smoke preflight reported readiness without machine-state changes."
