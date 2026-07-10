param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [Parameter(Mandatory = $true)][string]$ExpectedSourceCommit,
    [ValidateSet("DryRun", "StageOnly", "Deploy")]
    [string]$Mode = "DryRun",
    [string]$OutputDir = "",
    [string]$ResultPath = "",
    [string]$DurableManifestPath = "",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = "",
    [switch]$AllowLoadedTsfHolders
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "dev-support.ps1")

if ($ExpectedSourceCommit -notmatch '^[A-Fa-f0-9]{7,40}$') {
    throw "-ExpectedSourceCommit must be a 7-40 digit hexadecimal commit id"
}

function Invoke-M10GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $Text = (& git -C $RepoRoot @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $Text"
    }
    return $Text
}

function Get-M10FileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RelativePath = ""
    )

    Test-YuneWindowsDevPath -Path $Path -Description $Name -PathType Leaf
    $Item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        name = $Name
        relative_path = $RelativePath
        path = $Item.FullName
        length = [long]$Item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Item.FullName).Hash
    }
}

function Get-M10PeSizeOfImage {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    $Reader = [System.IO.BinaryReader]::new($Stream)
    try {
        if ($Stream.Length -lt 256 -or $Reader.ReadUInt16() -ne 0x5a4d) {
            throw "not a valid PE image: $Path"
        }
        $Stream.Position = 0x3c
        $PeOffset = $Reader.ReadInt32()
        if ($PeOffset -lt 0 -or ($PeOffset + 24 + 60) -gt $Stream.Length) {
            throw "invalid PE header offset: $Path"
        }
        $Stream.Position = $PeOffset
        if ($Reader.ReadUInt32() -ne 0x00004550) {
            throw "missing PE signature: $Path"
        }
        $OptionalHeader = $PeOffset + 24
        $Stream.Position = $OptionalHeader
        $Magic = $Reader.ReadUInt16()
        if ($Magic -ne 0x010b -and $Magic -ne 0x020b) {
            throw "unsupported PE optional header: $Path"
        }
        $Stream.Position = $OptionalHeader + 56
        $SizeOfImage = $Reader.ReadUInt32()
        if ($SizeOfImage -eq 0) {
            throw "PE SizeOfImage is zero: $Path"
        }
        return [long]$SizeOfImage
    }
    finally {
        $Reader.Dispose()
        $Stream.Dispose()
    }
}

function Get-M10TsfHolders {
    param([Parameter(Mandatory = $true)][string]$TsfPath)

    if (-not (Test-Path -LiteralPath $TsfPath -PathType Leaf)) {
        return @()
    }
    $ExpectedPath = Resolve-YuneWindowsDevFullPath $TsfPath
    $Holders = [System.Collections.Generic.List[object]]::new()
    foreach ($Process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            foreach ($Module in @($Process.Modules)) {
                if ([string]::IsNullOrWhiteSpace([string]$Module.FileName)) {
                    continue
                }
                $ModulePath = Resolve-YuneWindowsDevFullPath ([string]$Module.FileName)
                if (-not [string]::Equals(
                        $ModulePath,
                        $ExpectedPath,
                        [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $ProcessPath = ""
                $StartedAt = ""
                try { $ProcessPath = [string]$Process.Path } catch {}
                try { $StartedAt = $Process.StartTime.ToString("o") } catch {}
                $Holders.Add([pscustomobject][ordered]@{
                        process_id = [int]$Process.Id
                        process_name = [string]$Process.ProcessName
                        process_path = $ProcessPath
                        process_started_at = $StartedAt
                        module_path = $ModulePath
                        module_memory_size = [long]$Module.ModuleMemorySize
                    }) | Out-Null
                break
            }
        }
        catch {
        }
    }
    return @($Holders)
}

function ConvertTo-M10ProcessRecord {
    param([Parameter(Mandatory = $true)]$Process)

    $StartedAt = ""
    if ($Process.started_at) {
        try { $StartedAt = ([DateTime]$Process.started_at).ToString("o") } catch {}
    }
    return [pscustomobject][ordered]@{
        process_id = [int]$Process.process_id
        process_name = [string]$Process.process_name
        process_path = [string]$Process.process_path
        process_started_at = $StartedAt
    }
}

function Get-M10PendingDeleteState {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $MatchingEntries = [System.Collections.Generic.List[string]]::new()
    $ReadError = ""
    try {
        $SessionManager =
            "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager"
        $Value = (Get-ItemProperty `
                -LiteralPath $SessionManager `
                -Name PendingFileRenameOperations `
                -ErrorAction SilentlyContinue).PendingFileRenameOperations
        foreach ($Entry in @($Value)) {
            $Text = [string]$Entry
            $Comparable = $Text -replace '^\\\?\?\\', ''
            if ($Comparable.StartsWith(
                    $InstallRoot,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                $MatchingEntries.Add($Text) | Out-Null
            }
        }
    }
    catch {
        $ReadError = $_.Exception.Message
    }
    return [pscustomobject][ordered]@{
        read_succeeded = [string]::IsNullOrWhiteSpace($ReadError)
        read_error = $ReadError
        install_root_entry_count = $MatchingEntries.Count
        install_root_entries = @($MatchingEntries)
    }
}

function Get-M10InstalledPreflight {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$InstalledSettings,
        [Parameter(Mandatory = $true)][string]$InstalledProfile
    )

    $Holders = @(Get-M10TsfHolders -TsfPath $Paths.tsf_dll)
    $ServerProcesses = @(Get-YuneWindowsDevProcessesByPath `
            -Path $Paths.server_exe `
            -ProcessName "YuneWindowsServer" | ForEach-Object {
                ConvertTo-M10ProcessRecord -Process $_
            })
    $SettingsProcesses = @(Get-YuneWindowsDevProcessesByPath `
            -Path $InstalledSettings `
            -ProcessName "YuneWindowsSettings" | ForEach-Object {
                ConvertTo-M10ProcessRecord -Process $_
            })
    $ProfileProcesses = @(Get-YuneWindowsDevProcessesByPath `
            -Path $InstalledProfile `
            -ProcessName "YuneWindowsProfileTool" | ForEach-Object {
                ConvertTo-M10ProcessRecord -Process $_
            })
    return [pscustomobject][ordered]@{
        captured_at = [DateTimeOffset]::Now.ToString("o")
        pending_delete = Get-M10PendingDeleteState -InstallRoot $InstallRoot
        tsf_holders = @($Holders)
        server_processes = @($ServerProcesses)
        settings_processes = @($SettingsProcesses)
        profile_processes = @($ProfileProcesses)
    }
}

function Assert-M10SafeInstallRoot {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $AllowedRoot = Resolve-YuneWindowsDevFullPath (Join-Path $env:LOCALAPPDATA "Yune")
    if (-not $InstallRoot.StartsWith(
            $AllowedRoot.TrimEnd("\") + "\",
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing deployment outside LocalAppData\Yune: $InstallRoot"
    }
}

function Test-M10PathNested {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $Candidate = (Resolve-YuneWindowsDevFullPath $Candidate).TrimEnd("\")
    $Root = (Resolve-YuneWindowsDevFullPath $Root).TrimEnd("\")
    return [string]::Equals(
        $Candidate,
        $Root,
        [System.StringComparison]::OrdinalIgnoreCase) -or
        $Candidate.StartsWith(
            $Root + "\",
            [System.StringComparison]::OrdinalIgnoreCase)
}

function Write-M10AtomicResultFile {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent)) {
        New-Item -Path $Parent -ItemType Directory -Force | Out-Null
    }
    $Leaf = Split-Path -Leaf $Path
    $TemporaryPath = Join-Path $Parent (
        ".{0}.{1}.tmp" -f $Leaf, [Guid]::NewGuid().ToString("N"))
    $BackupPath = "$TemporaryPath.backup"
    try {
        $Json = $Result | ConvertTo-Json -Depth 12
        $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($TemporaryPath, $Json, $Utf8NoBom)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            # File.Replace performs one same-volume atomic refresh, so a
            # concurrent reader sees either the prior complete manifest or the
            # new complete manifest, never a truncated JSON document.
            [System.IO.File]::Replace(
                $TemporaryPath,
                $Path,
                $BackupPath,
                $true)
        }
        else {
            [System.IO.File]::Move($TemporaryPath, $Path)
        }
    }
    finally {
        if ([System.IO.File]::Exists($TemporaryPath)) {
            [System.IO.File]::Delete($TemporaryPath)
        }
        if ([System.IO.File]::Exists($BackupPath)) {
            [System.IO.File]::Delete($BackupPath)
        }
    }
}

function Write-M10Result {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [string]$Path,
        [string]$DurablePath = ""
    )

    $Written = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    # Refresh durable provenance first. A scratch-path failure may stop the
    # operation, but it cannot prevent the authoritative state from advancing.
    foreach ($CandidatePath in @($DurablePath, $Path)) {
        if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
            continue
        }
        $FullPath = Resolve-YuneWindowsDevFullPath $CandidatePath
        if ($Written.Add($FullPath)) {
            Write-M10AtomicResultFile -Result $Result -Path $FullPath
        }
    }
}

function New-M10AsidePath {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Tag,
        [string]$Kind = "old"
    )

    $Candidate = "$Destination.m10-$Kind-$Tag"
    if (Test-Path -LiteralPath $Candidate) {
        throw "refusing to overwrite existing M10 aside path: $Candidate"
    }
    return $Candidate
}

function Install-M10CandidateFile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)]$Operations
    )

    Test-YuneWindowsDevPath -Path $Source -Description "candidate $Name" -PathType Leaf
    Test-YuneWindowsDevPath -Path $Destination -Description "installed $Name" -PathType Leaf
    $Operation = [ordered]@{
        name = $Name
        kind = "file"
        source = $Source
        destination = $Destination
        aside_path = New-M10AsidePath -Destination $Destination -Tag $Tag
        aside_created = $false
        candidate_installed = $false
        installed_sha256 = ""
        rollback_attempted = $false
        rollback_succeeded = $false
        failed_candidate_path = ""
    }
    $Operations.Add($Operation) | Out-Null

    Move-Item -LiteralPath $Destination -Destination $Operation.aside_path
    $Operation.aside_created = $true
    Copy-Item -LiteralPath $Source -Destination $Destination
    $Operation.candidate_installed = $true
    $Operation.installed_sha256 =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
    if ($Operation.installed_sha256 -ne $ExpectedHash) {
        throw "installed $Name hash does not match the frozen candidate"
    }
    return $Operation
}

function Install-M10CandidateSkins {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedDefaultHash,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)]$Operations
    )

    Test-YuneWindowsDevPath -Path $Source -Description "candidate skins" -PathType Container
    Test-YuneWindowsDevPath -Path $Destination -Description "installed skins" -PathType Container
    $Operation = [ordered]@{
        name = "skins"
        kind = "directory"
        source = $Source
        destination = $Destination
        aside_path = New-M10AsidePath -Destination $Destination -Tag $Tag
        aside_created = $false
        candidate_installed = $false
        installed_sha256 = ""
        rollback_attempted = $false
        rollback_succeeded = $false
        failed_candidate_path = ""
    }
    $Operations.Add($Operation) | Out-Null

    Move-Item -LiteralPath $Destination -Destination $Operation.aside_path
    $Operation.aside_created = $true
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse
    $Operation.candidate_installed = $true
    $DefaultTheme = Join-Path $Destination "default\theme.json"
    Test-YuneWindowsDevPath `
        -Path $DefaultTheme `
        -Description "installed default skin" `
        -PathType Leaf
    $Operation.installed_sha256 =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $DefaultTheme).Hash
    if ($Operation.installed_sha256 -ne $ExpectedDefaultHash) {
        throw "installed default skin hash does not match the frozen candidate"
    }
    return $Operation
}

function Restore-M10DeploymentOperations {
    param(
        [Parameter(Mandatory = $true)]$Operations,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    for ($Index = $Operations.Count - 1; $Index -ge 0; $Index -= 1) {
        $Operation = $Operations[$Index]
        $Operation.rollback_attempted = $true
        try {
            # If the initial rename failed, the destination is still the
            # untouched original. Never displace it during rollback.
            if ($Operation.aside_created -and
                (Test-Path -LiteralPath $Operation.destination)) {
                $FailedPath = New-M10AsidePath `
                    -Destination $Operation.destination `
                    -Tag $Tag `
                    -Kind "failed"
                Move-Item -LiteralPath $Operation.destination -Destination $FailedPath
                $Operation.failed_candidate_path = $FailedPath
            }
            if ($Operation.aside_created -and
                (Test-Path -LiteralPath $Operation.aside_path)) {
                Move-Item `
                    -LiteralPath $Operation.aside_path `
                    -Destination $Operation.destination
            }
            $Operation.rollback_succeeded =
                -not $Operation.aside_created -or
                (Test-Path -LiteralPath $Operation.destination)
        }
        catch {
            $Operation.rollback_succeeded = $false
        }
    }
}

function Set-M10FailedDeploymentSessionState {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Operations
    )

    $SwapStarted = @($Operations | Where-Object {
            $_.aside_created -or $_.candidate_installed
        }).Count -gt 0
    if ($SwapStarted) {
        # A process may have mapped the briefly installed candidate even when
        # every filesystem rename is rolled back successfully. Only a full
        # session boundary can make the loaded-image set trustworthy again.
        $Result.deployment.session_restart_required = $true
        $Result.deployment.live_test_allowed_without_restart = $false
    }
    $Result.status = "deploy_failed"
}

$InstallRoot = Resolve-YuneWindowsDevFullPath $InstallDir
$ActualCommit = Invoke-M10GitText -Arguments @("rev-parse", "HEAD")
$ResolvedExpectedCommit = Invoke-M10GitText `
    -Arguments @("rev-parse", "--verify", "$ExpectedSourceCommit^{commit}")
if (-not [string]::Equals(
        $ActualCommit,
        $ResolvedExpectedCommit,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "source commit $ActualCommit does not match pinned commit $ResolvedExpectedCommit"
}
$Branch = Invoke-M10GitText -Arguments @("branch", "--show-current")
$StatusText = Invoke-M10GitText `
    -Arguments @("status", "--porcelain", "--untracked-files=all")
$SourceClean = [string]::IsNullOrWhiteSpace($StatusText)
$DirtyPaths = if ($SourceClean) {
    @()
}
else {
    @($StatusText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$Paths = Get-YuneWindowsDevInstallPaths -InstallDir $InstallRoot
$InstalledProfile = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"
$InstalledSettings = Join-Path $InstallRoot "YuneWindowsSettings.exe"
$InstalledSkins = Join-Path $InstallRoot "skins"
$Preflight = Get-M10InstalledPreflight `
    -InstallRoot $InstallRoot `
    -Paths $Paths `
    -InstalledSettings $InstalledSettings `
    -InstalledProfile $InstalledProfile
$Holders = @($Preflight.tsf_holders)
$ServerProcesses = @($Preflight.server_processes)
$SettingsProcesses = @($Preflight.settings_processes)
$ProfileProcesses = @($Preflight.profile_processes)
$PendingDelete = $Preflight.pending_delete

$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
$BuildScriptRecord = Get-M10FileRecord `
    -Name "build script" `
    -Path $BuildScript `
    -RelativePath "tools\build-tsf-shell.ps1"
$Package = Get-YuneWindowsDevPackage -YuneRoot $YuneRoot
$PackageRime = Get-M10FileRecord `
    -Name "packaged rime.dll" `
    -Path $Package.rime_dll `
    -RelativePath "lib\rime.dll"
$PackageHeader = Get-M10FileRecord `
    -Name "packaged profile header" `
    -Path $Package.profile_header `
    -RelativePath "include\rime_yune_windows_profile_api.h"

$DeploymentOrder = @("server", "tsf", "settings", "profile", "skins")
$Result = [ordered]@{
    schema_version = 1
    operation = "m10_frozen_candidate"
    mode = $Mode
    status = "preflight"
    generated_at = [DateTimeOffset]::Now.ToString("o")
    source = [ordered]@{
        repo_root = $RepoRoot
        expected_commit = $ResolvedExpectedCommit
        actual_commit = $ActualCommit
        branch = $Branch
        clean = $SourceClean
        dirty_entries = $DirtyPaths
        post_build_verified = $false
        build_script = $BuildScriptRecord
    }
    package = [ordered]@{
        yune_root = $Package.yune_root
        rime = $PackageRime
        profile_header = $PackageHeader
        post_build_verified = $false
    }
    install = [ordered]@{
        install_dir = $InstallRoot
        pending_delete = $PendingDelete
        tsf_holder_count = $Holders.Count
        tsf_holders = @($Holders)
        installed_server_processes = @($ServerProcesses)
        installed_settings_processes = @($SettingsProcesses)
        installed_profile_processes = @($ProfileProcesses)
        installed_rime_sha256 = ""
    }
    build = [ordered]@{
        performed = $false
        output_dir = ""
        command = "tools\build-tsf-shell.ps1 -OutputDir <build> -YuneRoot <yune>"
        invocation_count = 0
        artifacts = @()
        tsf_pe_size_of_image = 0
    }
    manifest = [ordered]@{
        scratch_path = ""
        durable_path = ""
        durable_outside_os_temp = $false
        atomic_refresh = $true
    }
    deployment = [ordered]@{
        approved = [bool]$ApprovedMachineStateChange
        approval_note_present = -not [string]::IsNullOrWhiteSpace($ApprovalNote)
        allow_loaded_tsf_holders = [bool]$AllowLoadedTsfHolders
        intended_order = $DeploymentOrder
        performed = $false
        started_at = ""
        completed_at = ""
        operations = @()
        session_restart_required = $false
        live_test_allowed_without_restart = $false
        rollback_attempted = $false
        rollback_complete = $false
        rollback_complete_scope = "filesystem_only"
        post_rollback_preflight = $null
        post_rollback_preflight_error = ""
        error = ""
    }
}

if ($Mode -eq "DryRun") {
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        throw "DryRun is read-only; do not supply -ResultPath"
    }
    $Result.status = if ($SourceClean) { "dry_run_ready" } else { "dry_run_source_dirty" }
    $Result.deployment.session_restart_required =
        $Holders.Count -gt 0 -or
        $ServerProcesses.Count -gt 0 -or
        $SettingsProcesses.Count -gt 0 -or
        $ProfileProcesses.Count -gt 0
    Write-Output ($Result | ConvertTo-Json -Depth 12)
    return
}

if (-not $SourceClean) {
    throw "StageOnly/Deploy requires a clean pinned source tree. Dirty entries: $($DirtyPaths -join '; ')"
}
if (-not $PendingDelete.read_succeeded) {
    throw "could not verify PendingFileRenameOperations: $($PendingDelete.read_error)"
}
if ($PendingDelete.install_root_entry_count -gt 0) {
    throw "install root has pending delete/rename entries; reboot and verify cleanup first"
}

if ($Mode -eq "Deploy") {
    Assert-M10SafeInstallRoot -InstallRoot $InstallRoot
    if (-not $ApprovedMachineStateChange) {
        throw "Deploy requires -ApprovedMachineStateChange after current-session approval"
    }
    if ([string]::IsNullOrWhiteSpace($ApprovalNote)) {
        throw "Deploy requires a non-empty -ApprovalNote"
    }
    if ($Holders.Count -gt 0 -and -not $AllowLoadedTsfHolders) {
        throw "loaded TSF holders remain; rerun only with -AllowLoadedTsfHolders and require sign-out/reboot before testing"
    }
    foreach ($RequiredInstalledPath in @(
            $Paths.server_exe,
            $Paths.tsf_dll,
            $Paths.rime_dll,
            $InstalledSettings,
            $InstalledProfile,
            (Join-Path $InstalledSkins "default\theme.json")
        )) {
        if (-not (Test-Path -LiteralPath $RequiredInstalledPath)) {
            throw "refusing partial in-place deployment; installed component is missing: $RequiredInstalledPath"
        }
    }
    $InstalledRimeHash =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $Paths.rime_dll).Hash
    if (-not [string]::Equals(
            $InstalledRimeHash,
            $PackageRime.sha256,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "installed rime.dll does not match the packaged frozen dependency"
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputRoot = Resolve-YuneWindowsDevFullPath (Join-Path $env:TEMP (
            "yune-windows\m10-frozen-candidate-{0}-{1}" -f
            $PID,
            [Guid]::NewGuid().ToString("N").Substring(0, 8)))
}
else {
    $OutputRoot = Resolve-YuneWindowsDevFullPath $OutputDir
}
$BuildDir = Join-Path $OutputRoot "build"
if ((Test-M10PathNested -Candidate $BuildDir -Root $InstallRoot) -or
    (Test-M10PathNested -Candidate $InstallRoot -Root $BuildDir)) {
    throw "candidate build output and install root must be separate"
}

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path $OutputRoot "m10-frozen-candidate.json"
}
$ResultPath = Resolve-YuneWindowsDevFullPath $ResultPath
if (Test-M10PathNested -Candidate $ResultPath -Root $InstallRoot) {
    throw "candidate result must be written outside the install root"
}
$Result.manifest.scratch_path = $ResultPath

if ($Mode -eq "Deploy") {
    if ([string]::IsNullOrWhiteSpace($DurableManifestPath)) {
        $DurableManifestPath = Join-Path $RepoRoot (
            "docs\evidence\m10\machine-state\frozen-candidate.json")
    }
    $DurableManifestPath = Resolve-YuneWindowsDevFullPath $DurableManifestPath
    $OsTempRoot = Resolve-YuneWindowsDevFullPath ([System.IO.Path]::GetTempPath())
    if (Test-M10PathNested -Candidate $DurableManifestPath -Root $InstallRoot) {
        throw "durable candidate manifest must be written outside the install root"
    }
    if (Test-M10PathNested -Candidate $DurableManifestPath -Root $OsTempRoot) {
        throw "durable candidate manifest must be outside the OS temp tree"
    }
    $Result.manifest.durable_path = $DurableManifestPath
    $Result.manifest.durable_outside_os_temp = $true
}
elseif (-not [string]::IsNullOrWhiteSpace($DurableManifestPath)) {
    throw "-DurableManifestPath is valid only with -Mode Deploy"
}

New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
if (Test-Path -LiteralPath $BuildDir) {
    $ExistingBuildItems = @(Get-ChildItem -LiteralPath $BuildDir -Force)
    if ($ExistingBuildItems.Count -gt 0) {
        throw "candidate build directory must be empty: $BuildDir"
    }
}
else {
    New-Item -Path $BuildDir -ItemType Directory | Out-Null
}

$BuildOutput = @(& $BuildScript -OutputDir $BuildDir -YuneRoot $Package.yune_root)
foreach ($Line in $BuildOutput) {
    Write-Host $Line
}
if ($LASTEXITCODE -ne 0) {
    throw "frozen candidate build failed with exit code $LASTEXITCODE"
}

$PostBuildCommit = Invoke-M10GitText -Arguments @("rev-parse", "HEAD")
$PostBuildStatus = Invoke-M10GitText `
    -Arguments @("status", "--porcelain", "--untracked-files=all")
if (-not [string]::Equals(
        $PostBuildCommit,
        $ResolvedExpectedCommit,
        [System.StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace($PostBuildStatus)) {
    throw "source commit/tree changed during the frozen candidate build"
}
$Result.source.post_build_verified = $true
$PostBuildRimeHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Package.rime_dll).Hash
$PostBuildHeaderHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Package.profile_header).Hash
if (-not [string]::Equals(
        $PostBuildRimeHash,
        $PackageRime.sha256,
        [System.StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals(
        $PostBuildHeaderHash,
        $PackageHeader.sha256,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "packaged Yune build inputs changed during the frozen candidate build"
}
$Result.package.post_build_verified = $true

$CandidatePaths = [ordered]@{
    server = Join-Path $BuildDir "YuneWindowsServer.exe"
    tsf = Join-Path $BuildDir "YuneWindowsTSF.dll"
    settings = Join-Path $BuildDir "YuneWindowsSettings.exe"
    profile = Join-Path $BuildDir "YuneWindowsProfileTool.exe"
    default_skin = Join-Path $BuildDir "skins\default\theme.json"
}
$Artifacts = @(
    Get-M10FileRecord -Name "server" -Path $CandidatePaths.server -RelativePath "YuneWindowsServer.exe"
    Get-M10FileRecord -Name "tsf" -Path $CandidatePaths.tsf -RelativePath "YuneWindowsTSF.dll"
    Get-M10FileRecord -Name "settings" -Path $CandidatePaths.settings -RelativePath "YuneWindowsSettings.exe"
    Get-M10FileRecord -Name "profile" -Path $CandidatePaths.profile -RelativePath "YuneWindowsProfileTool.exe"
    Get-M10FileRecord -Name "default_skin" -Path $CandidatePaths.default_skin -RelativePath "skins\default\theme.json"
)
$ArtifactByName = @{}
foreach ($Artifact in $Artifacts) {
    $ArtifactByName[$Artifact.name] = $Artifact
}
$Result.build.performed = $true
$Result.build.output_dir = $BuildDir
$Result.build.invocation_count = 1
$Result.build.artifacts = $Artifacts
$Result.build.tsf_pe_size_of_image = Get-M10PeSizeOfImage -Path $CandidatePaths.tsf
$Result.status = "staged"

if ($Mode -eq "Deploy") {
    # The build can take long enough for a new TSF holder or pending-delete
    # entry to appear. Refresh the preflight immediately before any rename.
    $Preflight = Get-M10InstalledPreflight `
        -InstallRoot $InstallRoot `
        -Paths $Paths `
        -InstalledSettings $InstalledSettings `
        -InstalledProfile $InstalledProfile
    $Holders = @($Preflight.tsf_holders)
    $ServerProcesses = @($Preflight.server_processes)
    $SettingsProcesses = @($Preflight.settings_processes)
    $ProfileProcesses = @($Preflight.profile_processes)
    $PendingDelete = $Preflight.pending_delete
    $Result.install.pending_delete = $PendingDelete
    $Result.install.tsf_holder_count = $Holders.Count
    $Result.install.tsf_holders = @($Holders)
    $Result.install.installed_server_processes = @($ServerProcesses)
    $Result.install.installed_settings_processes = @($SettingsProcesses)
    $Result.install.installed_profile_processes = @($ProfileProcesses)
    $RefreshedInstalledRimeHash =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $Paths.rime_dll).Hash
    $Result.install.installed_rime_sha256 = $RefreshedInstalledRimeHash
    if (-not [string]::Equals(
            $RefreshedInstalledRimeHash,
            $PackageRime.sha256,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "installed rime.dll changed during the candidate build; no deployment was attempted"
    }
    if (-not $PendingDelete.read_succeeded -or
        $PendingDelete.install_root_entry_count -gt 0) {
        throw "install-root pending delete state changed during the candidate build"
    }
    if ($Holders.Count -gt 0 -and -not $AllowLoadedTsfHolders) {
        throw "new TSF holder(s) appeared during the build; no deployment was attempted"
    }
}
Write-M10Result `
    -Result $Result `
    -Path $ResultPath `
    -DurablePath $DurableManifestPath

if ($Mode -eq "StageOnly") {
    Write-Host "Staged one frozen M10 candidate build at $BuildDir"
    Write-Host "Candidate manifest: $ResultPath"
    Write-Output ($Result | ConvertTo-Json -Depth 12)
    return
}

$Tag = "{0}-{1}" -f (New-YuneWindowsDevTimestamp), [Guid]::NewGuid().ToString("N").Substring(0, 8)
$Operations = [System.Collections.Generic.List[object]]::new()
$Result.deployment.started_at = [DateTimeOffset]::Now.ToString("o")
$Result.deployment.session_restart_required = $true
$Result.deployment.live_test_allowed_without_restart = $false
$Result.status = "deploying_restart_required"
# Persist the restart boundary before the first rename. If this PowerShell
# process is interrupted mid-swap, the durable manifest still fails closed.
Write-M10Result `
    -Result $Result `
    -Path $ResultPath `
    -DurablePath $DurableManifestPath
try {
    # The order is protocol-significant: new server accepts old clients, while
    # the new TSF requires the server's boot_id/revision response fields.
    Install-M10CandidateFile `
        -Name "server" `
        -Source $CandidatePaths.server `
        -Destination $Paths.server_exe `
        -ExpectedHash $ArtifactByName.server.sha256 `
        -Tag $Tag `
        -Operations $Operations | Out-Null
    $Result.deployment.operations = @($Operations)
    Write-M10Result -Result $Result -Path $ResultPath -DurablePath $DurableManifestPath
    Install-M10CandidateFile `
        -Name "tsf" `
        -Source $CandidatePaths.tsf `
        -Destination $Paths.tsf_dll `
        -ExpectedHash $ArtifactByName.tsf.sha256 `
        -Tag $Tag `
        -Operations $Operations | Out-Null
    $Result.deployment.operations = @($Operations)
    Write-M10Result -Result $Result -Path $ResultPath -DurablePath $DurableManifestPath
    Install-M10CandidateFile `
        -Name "settings" `
        -Source $CandidatePaths.settings `
        -Destination $InstalledSettings `
        -ExpectedHash $ArtifactByName.settings.sha256 `
        -Tag $Tag `
        -Operations $Operations | Out-Null
    $Result.deployment.operations = @($Operations)
    Write-M10Result -Result $Result -Path $ResultPath -DurablePath $DurableManifestPath
    Install-M10CandidateFile `
        -Name "profile" `
        -Source $CandidatePaths.profile `
        -Destination $InstalledProfile `
        -ExpectedHash $ArtifactByName.profile.sha256 `
        -Tag $Tag `
        -Operations $Operations | Out-Null
    $Result.deployment.operations = @($Operations)
    Write-M10Result -Result $Result -Path $ResultPath -DurablePath $DurableManifestPath
    Install-M10CandidateSkins `
        -Source (Join-Path $BuildDir "skins") `
        -Destination $InstalledSkins `
        -ExpectedDefaultHash $ArtifactByName.default_skin.sha256 `
        -Tag $Tag `
        -Operations $Operations | Out-Null
    $Result.deployment.operations = @($Operations)
    Write-M10Result -Result $Result -Path $ResultPath -DurablePath $DurableManifestPath

    $Result.deployment.performed = $true
    $Result.deployment.completed_at = [DateTimeOffset]::Now.ToString("o")
    $Result.deployment.operations = @($Operations)
    # A session boundary is mandatory even if the preflight saw no holders;
    # another TSF host can load during the multi-file rename sequence.
    $Result.deployment.session_restart_required = $true
    $Result.deployment.live_test_allowed_without_restart = $false
    $Result.status = "deployed_restart_required"
    Write-M10Result `
        -Result $Result `
        -Path $ResultPath `
        -DurablePath $DurableManifestPath
}
catch {
    $DeployError = $_.Exception.Message
    $Result.deployment.error = $DeployError
    $Result.deployment.rollback_attempted = $Operations.Count -gt 0
    if ($Operations.Count -gt 0) {
        Restore-M10DeploymentOperations -Operations $Operations -Tag $Tag
    }
    $Result.deployment.operations = @($Operations)
    $Result.deployment.rollback_complete =
        $Operations.Count -gt 0 -and
        @($Operations | Where-Object { -not $_.rollback_succeeded }).Count -eq 0
    Set-M10FailedDeploymentSessionState `
        -Result $Result `
        -Operations $Operations
    try {
        $PostRollback = Get-M10InstalledPreflight `
            -InstallRoot $InstallRoot `
            -Paths $Paths `
            -InstalledSettings $InstalledSettings `
            -InstalledProfile $InstalledProfile
        $Result.deployment.post_rollback_preflight = [ordered]@{
            captured_at = $PostRollback.captured_at
            pending_delete = $PostRollback.pending_delete
            tsf_holder_count = @($PostRollback.tsf_holders).Count
            tsf_holders = @($PostRollback.tsf_holders)
            installed_server_processes = @($PostRollback.server_processes)
            installed_settings_processes = @($PostRollback.settings_processes)
            installed_profile_processes = @($PostRollback.profile_processes)
        }
    }
    catch {
        $Result.deployment.post_rollback_preflight_error =
            $_.Exception.Message
    }
    Write-M10Result `
        -Result $Result `
        -Path $ResultPath `
        -DurablePath $DurableManifestPath
    throw "M10 frozen candidate deployment failed; no process was stopped and rollback was attempted: $DeployError. Durable manifest: $DurableManifestPath"
}

Write-Host "M10 frozen candidate deployed in server/TSF/settings/profile/skin order."
Write-Host "Scratch candidate manifest: $ResultPath"
Write-Host "Durable candidate manifest: $DurableManifestPath"
if ($Result.deployment.session_restart_required) {
    Write-Warning "Loaded old images remain. Full sign-out/reboot is required before live testing."
}
Write-Output ($Result | ConvertTo-Json -Depth 12)
