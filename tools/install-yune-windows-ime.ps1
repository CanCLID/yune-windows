param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = "",
    [switch]$PreflightOnly,
    [string]$PreflightPath = "",
    [string]$CurrentResiduePath = "",
    [switch]$RefreshCurrentResidue,
    [string]$BrowserPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

if ($PreflightOnly) {
    if ($RefreshCurrentResidue.IsPresent) {
        Require-LiveSmokeApprovalNote `
            -ApprovalNote $ApprovalNote
    }
    if ($PreflightPath -eq "") {
        $PreflightPath = Join-Path $env:TEMP "yune-windows\p2-win01-install-preflight.json"
    }
    Write-P2Win01PreflightReport `
        -Path $PreflightPath `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -BrowserPath $BrowserPath `
        -RequireBrowser $false `
        -CurrentResiduePath $CurrentResiduePath `
        -ApprovalNote $ApprovalNote `
        -RefreshCurrentResidue:$($RefreshCurrentResidue.IsPresent) | Out-Null
    Write-Output $PreflightPath
    return
}

function Require-Approval {
    if (-not $ApprovedMachineStateChange) {
        throw "Refusing to install/register the IME without explicit approval. Rerun with -ApprovedMachineStateChange only after approval in the current session."
    }
}

function Require-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw "IME registration requires an elevated PowerShell session after approval."
    }
}

function Resolve-SafeInstallDir([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    $allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Yune"))
    if (-not $full.StartsWith($allowedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe install directory outside LocalAppData\Yune: $full"
    }
    return $full
}

function Assert-YuneWindowsProfileRegistered([string]$ProfileToolPath) {
    $ProfileStateText = (Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $ProfileToolPath `
            -Arguments @("--state") `
            -Operation "profile state check").Trim()
    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "profile state check returned invalid JSON: $ProfileStateText"
    }

    try {
        Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $true -Context "profile state check"
    }
    catch {
        throw "profile registration did not verify after regsvr32: $ProfileStateText ($($_.Exception.Message))"
    }
}

function Assert-YuneWindowsFreshInstallTarget([string]$InstallRoot) {
    if (Test-Path -LiteralPath $InstallRoot) {
        throw "install directory already exists. Refusing to install over existing YuneWindows files: $InstallRoot"
    }
}

function Assert-YuneWindowsProfileUnregisteredForRollback([string]$ProfileToolPath) {
    if (-not (Test-Path -LiteralPath $ProfileToolPath)) {
        return
    }

    $ProfileStateText = (Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $ProfileToolPath `
            -Arguments @("--state") `
            -Operation "rollback profile state check").Trim()
    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "rollback profile state check returned invalid JSON: $ProfileStateText"
    }

    try {
        Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $false -Context "rollback profile state check"
        Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false -Context "rollback profile state check"
    }
    catch {
        throw "rollback profile unregistration did not verify: $ProfileStateText ($($_.Exception.Message))"
    }
}

function Invoke-YuneWindowsInstallRollback([string]$InstallRoot, [string]$TsfDllPath, [string]$ProfileToolPath) {
    $RollbackErrors = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath $TsfDllPath) {
        try {
            Invoke-YuneWindowsRegsvr32 `
                -Arguments @("/u", "/s", $TsfDllPath) `
                -Operation "regsvr32 rollback unregistration" | Out-Null
            Assert-YuneWindowsProfileUnregisteredForRollback -ProfileToolPath $ProfileToolPath
        }
        catch {
            $RollbackErrors.Add($_.Exception.Message)
        }
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        try {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        }
        catch {
            $RollbackErrors.Add($_.Exception.Message)
        }
    }

    return [ordered]@{
        completed = $RollbackErrors.Count -eq 0
        errors = @($RollbackErrors)
    }
}

Require-Approval
Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
Require-Administrator

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallRoot = Resolve-SafeInstallDir $InstallDir
$BuildDir = Join-Path $env:TEMP "yune-windows\p2-win01-install-build"
$PackageDir = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist"
$RimeDll = Join-Path $PackageDir "lib\rime.dll"
$SchemaSource = Join-Path $YuneRoot "apps\yune-web\public\schema"

Assert-YuneWindowsFreshInstallTarget -InstallRoot $InstallRoot

if (-not (Test-Path -LiteralPath $RimeDll)) {
    throw "missing packaged Yune runtime: $RimeDll"
}
if (-not (Test-Path -LiteralPath $SchemaSource)) {
    throw "missing Yune schema data: $SchemaSource"
}

& (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") -OutputDir $BuildDir -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$TsfDll = Join-Path $InstallRoot "YuneWindowsTSF.dll"
$ProfileTool = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"
$InstallStarted = $false

try {
    New-Item -ItemType Directory -Force $InstallRoot | Out-Null
    $InstallStarted = $true
    Copy-Item -LiteralPath (Join-Path $BuildDir "YuneWindowsTSF.dll") -Destination $InstallRoot -Force
    Copy-Item -LiteralPath (Join-Path $BuildDir "YuneWindowsServer.exe") -Destination $InstallRoot -Force
    Copy-Item -LiteralPath (Join-Path $BuildDir "YuneWindowsProfileTool.exe") -Destination $InstallRoot -Force
    Copy-Item -LiteralPath $RimeDll -Destination $InstallRoot -Force

    $SchemaDest = Join-Path $InstallRoot "schema"
    $UserDataDest = Join-Path $InstallRoot "user-data"
    & (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
        -SourceSchemaDir $SchemaSource `
        -DestinationSchemaDir $SchemaDest `
        -UserDataDir $UserDataDest

    $InstallInfo = [ordered]@{
        install_dir = $InstallRoot
        yune_root = (Resolve-Path $YuneRoot).Path
        rime_dll = (Join-Path $InstallRoot "rime.dll")
        shared_data_dir = $SchemaDest
        user_data_dir = $UserDataDest
        pipe = "\\.\pipe\yune-windows-ime"
        tsf_clsid = "{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}"
        profile_guid = "{3AE69B8D-19B4-4267-8F21-E239666D6632}"
    }
    $InstallInfo | ConvertTo-Json | Out-File -LiteralPath (Join-Path $InstallRoot "install-info.json") -Encoding utf8

    Invoke-YuneWindowsRegsvr32 `
        -Arguments @("/s", $TsfDll) `
        -Operation "regsvr32 registration" | Out-Null

    Assert-YuneWindowsMachineRegistration -InstallDir $InstallRoot | Out-Null
}
catch {
    $InstallFailure = $_.Exception.Message
    if ($InstallStarted) {
        $Rollback = Invoke-YuneWindowsInstallRollback `
            -InstallRoot $InstallRoot `
            -TsfDllPath $TsfDll `
            -ProfileToolPath $ProfileTool
        if ($Rollback.completed -ne $true) {
            throw "install failed: $InstallFailure; rollback failed: $($Rollback.errors -join '; ')"
        }
        throw "install failed: $InstallFailure; rollback completed"
    }
    throw
}

Write-Host "Installed and registered Yune Windows IME at $InstallRoot"
