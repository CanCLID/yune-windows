param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportPath
if ($SupportSource -notmatch 'function\s+Assert-P2Win01PreflightReady') {
    throw "live-smoke-support.ps1 is missing Assert-P2Win01PreflightReady."
}

. $SupportPath

$TempDir = Join-Path $env:TEMP "yune-windows\p2-win01-preflight-readiness-gate-test"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
$script:ExistingBrowserPath = Join-Path $TempDir "browser\msedge.exe"
New-Item -ItemType Directory -Force (Split-Path -Parent $script:ExistingBrowserPath) | Out-Null
$SyntheticBrowserBytes = [byte[]]::new(160)
$SyntheticBrowserBytes[0] = [byte][char]'M'
$SyntheticBrowserBytes[1] = [byte][char]'Z'
$SyntheticBrowserPeOffset = 0x80
[BitConverter]::GetBytes([int]$SyntheticBrowserPeOffset).CopyTo($SyntheticBrowserBytes, 0x3c)
$SyntheticBrowserBytes[$SyntheticBrowserPeOffset] = [byte][char]'P'
$SyntheticBrowserBytes[$SyntheticBrowserPeOffset + 1] = [byte][char]'E'
$SyntheticBrowserBytes[$SyntheticBrowserPeOffset + 2] = 0
$SyntheticBrowserBytes[$SyntheticBrowserPeOffset + 3] = 0
[BitConverter]::GetBytes([UInt16]0x8664).CopyTo($SyntheticBrowserBytes, $SyntheticBrowserPeOffset + 4)
[System.IO.File]::WriteAllBytes($script:ExistingBrowserPath, $SyntheticBrowserBytes)

function New-Report {
    param(
        [bool]$Ready = $true,
        [bool]$MachineStateChanged = $false,
        [bool]$MachineStateChecked = $true,
        [string[]]$MachineStateIssues = @(),
        [string[]]$FilesystemLeftovers = @(),
        [bool]$InstallDirExists = $false,
        [int]$ServerProcessCount = 0,
        [bool]$RuntimeExists = $true,
        [bool]$SchemaExists = $true,
        [bool]$TsfSourceExists = $true,
        [bool]$ServerSourceExists = $true,
        [bool]$BuildScriptExists = $true,
        [bool]$IsAdministrator = $true,
        [bool]$IsSta = $true,
        [bool]$BrowserAvailable = $true,
        [object]$BrowserPath = $script:ExistingBrowserPath
    )

    return [pscustomobject]@{
        ready_for_live_smoke = $Ready
        machine_state_changed = $MachineStateChanged
        machine_state_checked = $MachineStateChecked
        machine_state_issues = $MachineStateIssues
        filesystem_leftovers = $FilesystemLeftovers
        install_dir_exists = $InstallDirExists
        server_process_count = $ServerProcessCount
        yune_runtime_exists = $RuntimeExists
        yune_schema_exists = $SchemaExists
        tsf_source_exists = $TsfSourceExists
        server_source_exists = $ServerSourceExists
        build_script_exists = $BuildScriptExists
        is_administrator = $IsAdministrator
        is_sta = $IsSta
        browser_available = $BrowserAvailable
        browser_path = $BrowserPath
    }
}

function Expect-Failure {
    param(
        [object]$Report,
        [string]$Expected
    )

    $Message = ""
    try {
        Assert-P2Win01PreflightReady -Report $Report -Context "synthetic preflight"
    }
    catch {
        $Message = $_.Exception.Message
    }
    if ($Message -eq "") {
        throw "preflight readiness gate accepted dirty report; expected: $Expected"
    }
    if ($Message -notmatch [regex]::Escape($Expected)) {
        throw "preflight readiness gate did not report '$Expected'. Actual: $Message"
    }
}

function New-StringTypedReport {
    $Report = New-Report
    foreach ($Name in @(
            "ready_for_live_smoke",
            "machine_state_changed",
            "machine_state_checked",
            "install_dir_exists",
            "yune_runtime_exists",
            "yune_schema_exists",
            "tsf_source_exists",
            "server_source_exists",
            "build_script_exists",
            "is_administrator",
            "is_sta",
            "browser_available"
        )) {
        $Value = if ($Report.PSObject.Properties[$Name].Value -eq $true) { "true" } else { "false" }
        $Report | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    $Report | Add-Member -NotePropertyName "server_process_count" -NotePropertyValue "0" -Force
    return $Report
}

Assert-P2Win01PreflightReady -Report (New-Report) -Context "clean synthetic preflight"

Expect-Failure -Report (New-Report -Ready $false) -Expected "ready_for_live_smoke=false"
Expect-Failure -Report (New-Report -MachineStateChanged $true) -Expected "machine_state_changed=true"
Expect-Failure -Report (New-Report -MachineStateChecked $false) -Expected "machine_state_checked=false"
Expect-Failure -Report (New-Report -MachineStateIssues @("PendingFileRenameOperations contains YuneWindows residue")) -Expected "machine_state_issues present"
Expect-Failure -Report (New-Report -FilesystemLeftovers @("C:\Windows\System32\YuneWindows.dll.old.0")) -Expected "filesystem_leftovers present"
Expect-Failure -Report (New-Report -InstallDirExists $true) -Expected "install_dir_exists=true"
Expect-Failure -Report (New-Report -ServerProcessCount 1) -Expected "server_process_count=1"
Expect-Failure -Report (New-Report -RuntimeExists $false) -Expected "yune_runtime_exists=false"
Expect-Failure -Report (New-Report -SchemaExists $false) -Expected "yune_schema_exists=false"
Expect-Failure -Report (New-Report -TsfSourceExists $false) -Expected "tsf_source_exists=false"
Expect-Failure -Report (New-Report -ServerSourceExists $false) -Expected "server_source_exists=false"
Expect-Failure -Report (New-Report -BuildScriptExists $false) -Expected "build_script_exists=false"
Expect-Failure -Report (New-Report -IsAdministrator $false) -Expected "is_administrator=false"
Expect-Failure -Report (New-Report -IsSta $false) -Expected "is_sta=false"
Expect-Failure -Report (New-Report -BrowserAvailable $false) -Expected "browser_available=false"
Expect-Failure -Report (New-Report -BrowserPath "<auto-detect>") -Expected "browser_path must provide a concrete Chromium browser path"
Expect-Failure -Report (New-Report -BrowserPath $true) -Expected "browser_path must provide a concrete Chromium browser path"
$MissingBrowserExe = Join-Path $TempDir "missing-browser\msedge.exe"
Expect-Failure -Report (New-Report -BrowserPath $MissingBrowserExe) -Expected "browser_path must provide a concrete Chromium browser path"

$MissingServerProcessCount = New-Report
$MissingServerProcessCount.PSObject.Properties.Remove("server_process_count")
Expect-Failure -Report $MissingServerProcessCount -Expected "server_process_count missing"

$MissingBrowserPath = New-Report
$MissingBrowserPath.PSObject.Properties.Remove("browser_path")
Expect-Failure -Report $MissingBrowserPath -Expected "browser_path missing"

$MissingReadyFlag = New-Report
$MissingReadyFlag.PSObject.Properties.Remove("ready_for_live_smoke")
Expect-Failure -Report $MissingReadyFlag -Expected "ready_for_live_smoke missing"

Expect-Failure -Report (New-StringTypedReport) -Expected "ready_for_live_smoke must be a JSON boolean"

$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
foreach ($Required in @(
        '$CurrentStage = "live-preflight"',
        '$LivePreflightCommand = "tools\run-p2-win01-live-smoke.ps1 -PreflightOnly',
        'Record-Command $LivePreflightCommand',
        'Write-P2Win01PreflightReport',
        'Assert-P2Win01PreflightReady',
        'Record-CommandSuccess $LivePreflightCommand',
        'Record-CommandFailure $LivePreflightCommand',
        '-FailureStage $CurrentStage'
    )) {
    if ($OrchestratorSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke orchestrator is missing preflight readiness gate pattern: $Required"
    }
}

$LivePreflightIndex = $OrchestratorSource.IndexOf('$CurrentStage = "live-preflight"')
$ProfileBuildIndex = $OrchestratorSource.IndexOf('$CurrentStage = "profile-probe-build"')
$InstallIndex = $OrchestratorSource.IndexOf('$CurrentStage = "install"')
if ($LivePreflightIndex -lt 0 -or $ProfileBuildIndex -lt 0 -or $InstallIndex -lt 0) {
    throw "live smoke orchestrator is missing expected stage markers."
}
if ($LivePreflightIndex -gt $ProfileBuildIndex) {
    throw "live preflight readiness gate must run before profile-probe build."
}
if ($LivePreflightIndex -gt $InstallIndex) {
    throw "live preflight readiness gate must run before install."
}

$CommandIndex = $OrchestratorSource.IndexOf('$LivePreflightCommand = "tools\run-p2-win01-live-smoke.ps1 -PreflightOnly', $LivePreflightIndex)
$RecordIndex = $OrchestratorSource.IndexOf('Record-Command $LivePreflightCommand', $LivePreflightIndex)
$AssertIndex = $OrchestratorSource.IndexOf('Assert-P2Win01PreflightReady', $LivePreflightIndex)
$SuccessIndex = $OrchestratorSource.IndexOf('Record-CommandSuccess $LivePreflightCommand', $LivePreflightIndex)
$FailureIndex = $OrchestratorSource.IndexOf('Record-CommandFailure $LivePreflightCommand', $LivePreflightIndex)
if ($CommandIndex -lt 0 -or $RecordIndex -lt 0 -or $AssertIndex -lt 0 -or $SuccessIndex -lt 0 -or $FailureIndex -lt 0) {
    throw "live smoke orchestrator is missing expected live-preflight command transcript markers."
}
if (-not ($LivePreflightIndex -lt $CommandIndex -and $CommandIndex -lt $RecordIndex -and $RecordIndex -lt $AssertIndex -and $AssertIndex -lt $SuccessIndex)) {
    throw "live preflight command transcript must record start before assertion and PASS after assertion."
}
if ($FailureIndex -lt $RecordIndex) {
    throw "live preflight command transcript must record FAIL only after the start line can be written."
}

$Plan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\plans\active\p2-win01-plan-windows-product.md")
if ($Plan -notmatch [regex]::Escape("tools\test-live-smoke-preflight-readiness-gate.ps1")) {
    throw "active plan must mention the live preflight readiness gate contract."
}

Write-Host "Live smoke checks preflight readiness before build/install machine-state path."
