param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorPath = Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1"

. $SupportPath

$TempRoot = Join-Path $env:TEMP "yune-windows\m01-state-snapshot-timestamp-contract"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $TempRoot | Out-Null

$ValidCapturedAt = "2026-06-26T18:40:00.0000000-07:00"
$InvalidCapturedAt = "not-a-timestamp"

function Write-SnapshotJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$Snapshot,
        [switch]$OmitCapturedAt,
        [string]$CapturedAt = $ValidCapturedAt
    )

    $Path = Join-Path $TempRoot $Name
    $OrderedSnapshot = [ordered]@{}
    if (-not $OmitCapturedAt) {
        $OrderedSnapshot.captured_at = $CapturedAt
    }
    foreach ($Entry in $Snapshot.GetEnumerator()) {
        $OrderedSnapshot[$Entry.Key] = $Entry.Value
    }
    $OrderedSnapshot | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
    return $Path
}

function Expect-ThrowingValidatorFailure {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Script,
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $Failed = $false
    try {
        & $Script
    }
    catch {
        $Failed = $true
        if ($_.Exception.Message -notmatch "captured_at") {
            throw "$Reason failed for the wrong reason: $($_.Exception.Message)"
        }
    }
    if (-not $Failed) {
        throw "$Reason accepted a snapshot without parseable captured_at"
    }
}

$ActiveInstalled = @{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $true
    profile_tool_exists = $true
    profile_state_verified = $true
    profile_state = '{"registered":true,"active":true}'
    server_processes = @()
}
$RegisteredInstalled = @{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $true
    profile_tool_exists = $true
    profile_state_verified = $true
    profile_state = '{"registered":true,"active":false}'
    server_processes = @()
    machine_registration_checked = $true
    machine_registration_verified = $true
    machine_registration_registered = $true
    machine_registration_dll_path_matches = $true
    machine_registration_required_keys = @(
        "Registry::HKEY_CLASSES_ROOT\CLSID\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}",
        "Registry::HKEY_CLASSES_ROOT\CLSID\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\InprocServer32",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\LanguageProfile\0x00000c04\{3AE69B8D-19B4-4267-8F21-E239666D6632}"
    )
    machine_registration_missing_keys = @()
    machine_registration_registry_check_errors = @()
    machine_registration_expected_dll_path = "C:\Users\example\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll"
    machine_registration_dll_path = "C:\Users\example\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll"
}
$CleanState = @{
    install_dir = "C:\Users\example\AppData\Local\Yune\WindowsIme"
    install_dir_exists = $false
    profile_tool_exists = $false
    profile_state_verified = $true
    profile_state = '{"registered":false,"active":false}'
    server_processes = @()
    machine_state_checked = $true
    machine_state_issues = @()
    filesystem_leftovers = @()
}

$ActiveValid = Write-SnapshotJson "active-valid.json" $ActiveInstalled
Assert-YuneWindowsActiveInstalledSnapshot -Path $ActiveValid -Context "active valid timestamp"
Expect-ThrowingValidatorFailure `
    -Reason "active validator" `
    -Script {
        $Path = Write-SnapshotJson "active-missing-captured-at.json" $ActiveInstalled -OmitCapturedAt
        Assert-YuneWindowsActiveInstalledSnapshot -Path $Path -Context "active missing timestamp"
    }
Expect-ThrowingValidatorFailure `
    -Reason "active validator" `
    -Script {
        $Path = Write-SnapshotJson "active-invalid-captured-at.json" $ActiveInstalled -CapturedAt $InvalidCapturedAt
        Assert-YuneWindowsActiveInstalledSnapshot -Path $Path -Context "active invalid timestamp"
    }

$RegisteredValid = Write-SnapshotJson "registered-valid.json" $RegisteredInstalled
Assert-YuneWindowsRegisteredInstalledSnapshot -Path $RegisteredValid -Context "registered valid timestamp"
Expect-ThrowingValidatorFailure `
    -Reason "registered validator" `
    -Script {
        $Path = Write-SnapshotJson "registered-missing-captured-at.json" $RegisteredInstalled -OmitCapturedAt
        Assert-YuneWindowsRegisteredInstalledSnapshot -Path $Path -Context "registered missing timestamp"
    }
Expect-ThrowingValidatorFailure `
    -Reason "registered validator" `
    -Script {
        $Path = Write-SnapshotJson "registered-invalid-captured-at.json" $RegisteredInstalled -CapturedAt $InvalidCapturedAt
        Assert-YuneWindowsRegisteredInstalledSnapshot -Path $Path -Context "registered invalid timestamp"
    }

$CleanValid = Write-SnapshotJson "clean-valid.json" $CleanState
Assert-YuneWindowsCleanPreInstallSnapshot -Path $CleanValid -Context "clean valid timestamp"
Expect-ThrowingValidatorFailure `
    -Reason "clean pre-install validator" `
    -Script {
        $Path = Write-SnapshotJson "clean-missing-captured-at.json" $CleanState -OmitCapturedAt
        Assert-YuneWindowsCleanPreInstallSnapshot -Path $Path -Context "clean missing timestamp"
    }
Expect-ThrowingValidatorFailure `
    -Reason "clean pre-install validator" `
    -Script {
        $Path = Write-SnapshotJson "clean-invalid-captured-at.json" $CleanState -CapturedAt $InvalidCapturedAt
        Assert-YuneWindowsCleanPreInstallSnapshot -Path $Path -Context "clean invalid timestamp"
    }

$CleanupValidState = Get-Content -Raw -LiteralPath $CleanValid | ConvertFrom-Json
$CleanupValidResult = Test-YuneWindowsCleanupState `
    -Snapshot $CleanupValidState `
    -RequireProfileState `
    -RequireMachineResidueCheck `
    -RequireCapturedAt
if ($CleanupValidResult.pass -ne $true) {
    throw "cleanup validator should accept clean state with parseable captured_at"
}

$CleanupMissingTimestamp = Get-Content -Raw -LiteralPath (Write-SnapshotJson "cleanup-missing-captured-at.json" $CleanState -OmitCapturedAt) | ConvertFrom-Json
$CleanupMissingResult = Test-YuneWindowsCleanupState `
    -Snapshot $CleanupMissingTimestamp `
    -RequireProfileState `
    -RequireMachineResidueCheck `
    -RequireCapturedAt
if ($CleanupMissingResult.pass -ne $false -or
    -not (($CleanupMissingResult.issues -join "`n") -match "captured_at")) {
    throw "cleanup validator should reject missing captured_at when required"
}

$CleanupInvalidTimestamp = Get-Content -Raw -LiteralPath (Write-SnapshotJson "cleanup-invalid-captured-at.json" $CleanState -CapturedAt $InvalidCapturedAt) | ConvertFrom-Json
$CleanupInvalidResult = Test-YuneWindowsCleanupState `
    -Snapshot $CleanupInvalidTimestamp `
    -RequireProfileState `
    -RequireMachineResidueCheck `
    -RequireCapturedAt
if ($CleanupInvalidResult.pass -ne $false -or
    -not (($CleanupInvalidResult.issues -join "`n") -match "captured_at")) {
    throw "cleanup validator should reject malformed captured_at when required"
}

$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
$CleanupPattern = 'Test-YuneWindowsCleanupState(?s:.*?)-RequireProfileState(?s:.*?)-RequireMachineResidueCheck(?s:.*?)-RequireCapturedAt'
if ($OrchestratorSource -notmatch $CleanupPattern) {
    throw "run-m01-live-smoke.ps1 must require captured_at when validating post-cleanup state."
}

Write-Host "Live state snapshot validators require parseable captured_at timestamps."
