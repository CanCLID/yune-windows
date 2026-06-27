param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$EvidenceRoot = "",
    [string]$BrowserPath = "",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = "",
    [switch]$PreflightOnly,
    [string]$PreflightPath = "",
    [string]$CurrentResiduePath = "",
    [switch]$RefreshCurrentResidue
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$YuneRoot = [System.IO.Path]::GetFullPath($YuneRoot)

if ($PreflightOnly) {
    if ($RefreshCurrentResidue.IsPresent) {
        Require-LiveSmokeApprovalNote `
            -ApprovalNote $ApprovalNote
    }
    if ($PreflightPath -eq "") {
        $PreflightPath = Join-Path $env:TEMP "yune-windows\p2-win01-live-preflight.json"
    }
    Write-P2Win01PreflightReport `
        -Path $PreflightPath `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -BrowserPath $BrowserPath `
        -RequireBrowser $true `
        -CurrentResiduePath $CurrentResiduePath `
        -ApprovalNote $ApprovalNote `
        -RefreshCurrentResidue:$($RefreshCurrentResidue.IsPresent) | Out-Null
    Write-Output $PreflightPath
    return
}

Require-ApprovedMachineStateChange `
    -Approved $ApprovedMachineStateChange.IsPresent `
    -Action "run the P2-WIN01 install/register/smoke/diagnostics/uninstall sequence"

Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
Require-ApprovedLiveSmokeContext

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($EvidenceRoot -eq "") {
    $EvidenceRoot = Join-Path $RepoRoot "docs\evidence"
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
$ResolvedBrowserPath = Find-ChromiumBrowserPath -RequestedPath $BrowserPath
Assert-ConcreteChromiumBrowserPath `
    -PathValue $ResolvedBrowserPath `
    -Source "Resolved Chromium browser path"

$InstallerEvidence = Join-Path $EvidenceRoot "p2-win01-installer"
$TsfEvidence = Join-Path $EvidenceRoot "p2-win01-tsf-smoke"
$DiagnosticsEvidence = Join-Path $EvidenceRoot "p2-win01-settings"
New-Item -ItemType Directory -Force $InstallerEvidence | Out-Null
New-Item -ItemType Directory -Force $TsfEvidence | Out-Null
New-Item -ItemType Directory -Force $DiagnosticsEvidence | Out-Null

$ApprovalPath = Join-Path $InstallerEvidence "approval.md"
Write-LiveSmokeApprovalEvidence `
    -Path $ApprovalPath `
    -ApprovalNote $ApprovalNote `
    -InstallDir $InstallDir `
    -YuneRoot $YuneRoot `
    -BrowserPath $ResolvedBrowserPath

$ApprovalText = Get-Content -Raw -LiteralPath $ApprovalPath
if ($ApprovalText -notmatch '(?m)^Date:\s*(?<date>\S+)\s*$') {
    throw "Live smoke approval evidence is missing a Date timestamp: $ApprovalPath"
}
try {
    $ApprovalDate = [System.DateTimeOffset]::Parse(
        $Matches["date"],
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind)
}
catch {
    throw "Live smoke approval evidence has a malformed Date timestamp: $ApprovalPath"
}

$CommandsPath = Join-Path $InstallerEvidence "commands.txt"
$ResultPath = Join-Path $InstallerEvidence "result.md"
$CleanupPath = Join-Path $InstallerEvidence "cleanup-result.md"
$BuildDir = Join-Path $env:TEMP "yune-windows\p2-win01-install-build"
$ProfileProbePath = Join-Path $BuildDir "YuneWindowsProfileTool.exe"
$Transcript = [System.Collections.Generic.List[string]]::new()
$CurrentStage = "initialization"
$LiveSmokeSucceeded = $false
$DiagnosticsBundleText = ""
$LiveSmokeStartedAt = Get-Date

function Write-TranscriptFile {
    New-Item -ItemType Directory -Force (Split-Path -Parent $CommandsPath) | Out-Null
    $Transcript | Out-File -LiteralPath $CommandsPath -Encoding utf8
}

function Record-Command {
    param([string]$Command)
    $Transcript.Add($Command)
    Write-TranscriptFile
}

function Record-CommandSuccess {
    param([string]$Command)
    Record-Command "PASS $Command"
}

function Record-CommandFailure {
    param(
        [string]$Command,
        [string]$Message = ""
    )
    $Line = "FAIL $Command"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $Line += " # " + ($Message -replace '\r?\n', ' ')
    }
    Record-Command $Line
}

function Format-CommandValue {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Write-LiveSmokeResult {
    param(
        [string]$Status,
        [string]$FailureStage = "",
        [string]$FailureMessage = "",
        [string]$DiagnosticsBundle = ""
    )

    $Lines = @(
        "# Install And Smoke Result",
        "",
        "Date: $((Get-Date).ToString("o"))",
        "",
        "Status: $Status",
        ""
    )
    if ($Status -ne "passed") {
        $Lines += @(
            "Failure stage: $FailureStage",
            "",
            "Failure message: $FailureMessage",
            ""
        )
    }
    $Lines += @(
        "Fresh install: attempted through ``tools\install-yune-windows-ime.ps1``.",
        "",
        "TSF registration/profile state: see ``pre-install-state.json`` and ``post-install-state.json`` when present.",
        "",
        "Notepad smoke: see ``docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md`` when present.",
        "",
        "Chromium smoke: see ``docs/evidence/p2-win01-tsf-smoke/chromium-smoke-result.md`` when present.",
        "",
        "Diagnostics bundle:",
        "",
        "````text",
        $DiagnosticsBundle,
        "````"
    )
    $Lines | Out-File -LiteralPath $ResultPath -Encoding utf8
}

function Assert-DiagnosticsBundleEvidence {
    param(
        [string]$Path,
        [string]$OutputDir,
        [System.DateTimeOffset]$NotBefore = [System.DateTimeOffset]::MinValue,
        [string]$PreStatePath = ""
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Diagnostics export did not return a support bundle path."
    }
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        throw "Diagnostics export output directory was not provided."
    }

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        throw "Diagnostics export returned a non-absolute support bundle path: $Path"
    }

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $FullOutputDir = [System.IO.Path]::GetFullPath($OutputDir).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $OutputDirPrefix = $FullOutputDir + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($OutputDirPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Diagnostics support bundle was not written under the registered-session diagnostics output directory: $FullPath"
    }

    if ([System.IO.Path]::GetExtension($FullPath) -ne ".zip") {
        throw "Diagnostics export did not return a zip support bundle path: $FullPath"
    }

    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "Diagnostics support bundle was not created: $FullPath"
    }

    $Bundle = Get-Item -LiteralPath $FullPath
    if ($Bundle.Length -le 0) {
        throw "Diagnostics support bundle is empty: $FullPath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = $null
    try {
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($FullPath)
        $ManifestEntry = $Archive.GetEntry("manifest.json")
        if (($null -eq $ManifestEntry) -or ($ManifestEntry.Length -le 0)) {
            throw "Diagnostics support bundle is missing manifest.json: $FullPath"
        }

        $Reader = [System.IO.StreamReader]::new($ManifestEntry.Open())
        try {
            $ManifestText = $Reader.ReadToEnd()
        }
        finally {
            $Reader.Dispose()
        }

        try {
            $Manifest = $ManifestText | ConvertFrom-Json
        }
        catch {
            throw "Diagnostics support bundle manifest is not valid JSON: $FullPath"
        }

        if ($null -eq $Manifest.generated_at) {
            throw "Diagnostics support bundle manifest is missing generated_at: $FullPath"
        }

        try {
            $ManifestGeneratedAt = [System.DateTimeOffset]::Parse(
                [string]$Manifest.generated_at,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
        catch {
            throw "Diagnostics support bundle manifest has malformed generated_at: $FullPath"
        }
        if (($NotBefore -ne [System.DateTimeOffset]::MinValue) -and
            ($ManifestGeneratedAt -lt $NotBefore)) {
            throw "Diagnostics support bundle manifest generated_at predates current-session approval evidence: $FullPath"
        }

        if (-not [string]::IsNullOrWhiteSpace($PreStatePath)) {
            if (-not (Test-Path -LiteralPath $PreStatePath -PathType Leaf)) {
                throw "Diagnostics pre-state evidence does not exist: $PreStatePath"
            }
            try {
                $PreState = Get-Content -Raw -LiteralPath $PreStatePath | ConvertFrom-Json
            }
            catch {
                throw "Diagnostics pre-state evidence is not valid JSON: $PreStatePath"
            }
            $CapturedAtProperty = $PreState.PSObject.Properties["captured_at"]
            if (($null -eq $CapturedAtProperty) -or [string]::IsNullOrWhiteSpace([string]$CapturedAtProperty.Value)) {
                throw "Diagnostics pre-state evidence is missing captured_at: $PreStatePath"
            }
            try {
                $PreStateCapturedAt = [System.DateTimeOffset]::Parse(
                    [string]$CapturedAtProperty.Value,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind)
            }
            catch {
                throw "Diagnostics pre-state evidence has malformed captured_at: $PreStatePath"
            }
            if ($PreStateCapturedAt -gt $ManifestGeneratedAt) {
                throw "Diagnostics support bundle manifest generated_at predates diagnostics-pre-state captured_at: $FullPath"
            }
        }

        $DiagnosticsLogsProperty = $Manifest.PSObject.Properties["diagnostics_logs"]
        if ($null -eq $DiagnosticsLogsProperty) {
            throw "Diagnostics support bundle manifest is missing diagnostics_logs metadata: $FullPath"
        }
        $DiagnosticsLogs = $DiagnosticsLogsProperty.Value

        foreach ($BooleanRule in @(
                @{ Name = "included"; Expected = $true },
                @{ Name = "typed_content_logs"; Expected = $false },
                @{ Name = "structural_events_only"; Expected = $true }
            )) {
            $Property = $DiagnosticsLogs.PSObject.Properties[$BooleanRule.Name]
            if (($null -eq $Property) -or (-not ($Property.Value -is [bool]))) {
                throw "Diagnostics support bundle manifest diagnostics_logs.$($BooleanRule.Name) must be a typed JSON boolean: $FullPath"
            }
            if ($Property.Value -ne $BooleanRule.Expected) {
                throw "Diagnostics support bundle manifest diagnostics_logs.$($BooleanRule.Name) has an unexpected value: $FullPath"
            }
        }

        $DirectoryProperty = $DiagnosticsLogs.PSObject.Properties["directory"]
        if (($null -eq $DirectoryProperty) -or ([string]$DirectoryProperty.Value -ne "logs")) {
            throw "Diagnostics support bundle manifest diagnostics_logs.directory must be logs: $FullPath"
        }

        $FileCountProperty = $DiagnosticsLogs.PSObject.Properties["file_count"]
        if ($null -eq $FileCountProperty) {
            throw "Diagnostics support bundle manifest is missing diagnostics_logs.file_count: $FullPath"
        }
        $FileCountValue = $FileCountProperty.Value
        $FileCountIsNumeric = $FileCountValue -is [byte] -or
            $FileCountValue -is [sbyte] -or
            $FileCountValue -is [int16] -or
            $FileCountValue -is [uint16] -or
            $FileCountValue -is [int] -or
            $FileCountValue -is [uint32] -or
            $FileCountValue -is [long] -or
            $FileCountValue -is [uint64]
        if (-not $FileCountIsNumeric) {
            throw "Diagnostics support bundle manifest diagnostics_logs.file_count must be numeric: $FullPath"
        }

        $ExpectedLogFileCount = [int64]$FileCountValue
        if ($ExpectedLogFileCount -le 0) {
            throw "Diagnostics support bundle manifest diagnostics_logs.file_count must be positive: $FullPath"
        }

        $LogEntries = @($Archive.Entries | Where-Object {
                $EntryPath = $_.FullName -replace "\\", "/"
                $EntryPath.StartsWith("logs/", [System.StringComparison]::OrdinalIgnoreCase) -and
                $EntryPath.EndsWith(".log", [System.StringComparison]::OrdinalIgnoreCase) -and
                $_.Length -gt 0
            })
        if ($LogEntries.Count -ne $ExpectedLogFileCount) {
            throw "Diagnostics support bundle log file count does not match manifest diagnostics_logs.file_count: $FullPath"
        }

        $ApprovedSmokeInput = "ngohaig"
        $ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))
        $TypedContentFieldPattern = '(?i)(^|\s)(input|raw_input|preedit|typed_text|commit|committed|committed_text|candidate_text|text)=[^\s]+'
        $HasCandidateUpdateEvent = $false
        $HasPositiveCandidateUpdateCount = $false
        $HasCommitTextEvent = $false

        foreach ($LogEntry in $LogEntries) {
            $LogReader = [System.IO.StreamReader]::new($LogEntry.Open())
            try {
                $LogText = $LogReader.ReadToEnd()
            }
            finally {
                $LogReader.Dispose()
            }

            if (($LogText -match [regex]::Escape($ApprovedSmokeInput)) -or
                ($LogText -match [regex]::Escape($ExpectedCommit)) -or
                ($LogText -match $TypedContentFieldPattern)) {
                throw "Diagnostics support bundle log contains typed content: $FullPath"
            }

            foreach ($Line in ($LogText -split "\r?\n")) {
                if ($Line -match "(^|\s)event=candidate_window_failed(?=\s|$)") {
                    throw "Diagnostics support bundle log contains candidate_window_failed event: $FullPath"
                }

                if ($Line -match "(^|\s)event=candidate_update(?=\s|$)") {
                    $HasCandidateUpdateEvent = $true
                    $CandidateCountMatch = [regex]::Match($Line, "(^|\s)candidate_count=(?<value>\d+)(?=\s|$)")
                    $CandidateCount = [int64]0
                    if ($CandidateCountMatch.Success -and
                        [int64]::TryParse($CandidateCountMatch.Groups["value"].Value, [ref]$CandidateCount) -and
                        $CandidateCount -gt 0) {
                        $HasPositiveCandidateUpdateCount = $true
                    }
                }

                if ($Line -match "(^|\s)event=commit_text(?=\s|$)") {
                    $HasCommitTextEvent = $true
                }
            }
        }

        if (-not $HasCandidateUpdateEvent) {
            throw "Diagnostics support bundle logs are missing exact candidate_update event: $FullPath"
        }
        if (-not $HasPositiveCandidateUpdateCount) {
            throw "Diagnostics support bundle logs are missing positive candidate_count on candidate_update: $FullPath"
        }
        if (-not $HasCommitTextEvent) {
            throw "Diagnostics support bundle logs are missing exact commit_text event: $FullPath"
        }
    }
    finally {
        if ($null -ne $Archive) {
            $Archive.Dispose()
        }
    }
}

$CurrentStage = "live-preflight"
$LivePreflightPath = Join-Path $InstallerEvidence "live-preflight.json"
$LivePreflightCommand = "tools\run-p2-win01-live-smoke.ps1 -PreflightOnly -PreflightPath $(Format-CommandValue $LivePreflightPath) -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -RefreshCurrentResidue -ApprovalNote $(Format-CommandValue $ApprovalNote)"
$LivePreflightCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"
Record-Command $LivePreflightCommand
try {
    Write-P2Win01PreflightReport `
        -Path $LivePreflightPath `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -BrowserPath $ResolvedBrowserPath `
        -RequireBrowser $true `
        -ApprovalNote $ApprovalNote `
        -RefreshCurrentResidue | Out-Null
    $LivePreflight = Get-Content -Raw -LiteralPath $LivePreflightPath | ConvertFrom-Json
    Assert-P2Win01PreflightReady `
        -Report $LivePreflight `
        -Context "Approved live smoke preflight"
    Record-CommandSuccess $LivePreflightCommand
}
catch {
    Record-CommandFailure $LivePreflightCommand $_.Exception.Message
    Write-LiveSmokeResult `
        -Status "failed" `
        -FailureStage $CurrentStage `
        -FailureMessage $_.Exception.Message
    throw
}

$CurrentStage = "install-preflight"
$InstallPreflightPath = Join-Path $InstallerEvidence "install-preflight.json"
$InstallPreflightCommand = "tools\install-yune-windows-ime.ps1 -PreflightOnly -PreflightPath $(Format-CommandValue $InstallPreflightPath) -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -RefreshCurrentResidue -ApprovalNote $(Format-CommandValue $ApprovalNote)"
$InstallPreflightCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"
Record-Command $InstallPreflightCommand
try {
    & (Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1") `
        -PreflightOnly `
        -PreflightPath $InstallPreflightPath `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -RefreshCurrentResidue `
        -ApprovalNote $ApprovalNote `
        -BrowserPath $ResolvedBrowserPath | Out-Null
    $InstallPreflight = Get-Content -Raw -LiteralPath $InstallPreflightPath | ConvertFrom-Json
    Assert-P2Win01PreflightReady `
        -Report $InstallPreflight `
        -Context "Approved install preflight"
    Record-CommandSuccess $InstallPreflightCommand
}
catch {
    Record-CommandFailure $InstallPreflightCommand $_.Exception.Message
    Write-LiveSmokeResult `
        -Status "failed" `
        -FailureStage $CurrentStage `
        -FailureMessage $_.Exception.Message
    throw
}

$CurrentStage = "profile-probe-build"
$BuildCommand = "tools\build-tsf-shell.ps1 -OutputDir $(Format-CommandValue $BuildDir) -YuneRoot $(Format-CommandValue $YuneRoot)"
try {
    Record-Command $BuildCommand
    & (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") `
        -OutputDir $BuildDir `
        -YuneRoot $YuneRoot
    if ($LASTEXITCODE -ne 0) {
        throw "profile probe build failed with exit code $LASTEXITCODE"
    }
    Record-CommandSuccess $BuildCommand
}
catch {
    Record-CommandFailure $BuildCommand $_.Exception.Message
    Write-LiveSmokeResult `
        -Status "failed" `
        -FailureStage $CurrentStage `
        -FailureMessage $_.Exception.Message
    throw
}

$CurrentStage = "pre-install-state"
$PreInstallStatePath = Join-Path $InstallerEvidence "pre-install-state.json"
try {
    Write-YuneWindowsStateSnapshot `
        -Path $PreInstallStatePath `
        -InstallDir $InstallDir `
        -ProfileToolPath $ProfileProbePath `
        -ApprovalNote $ApprovalNote `
        -IncludeMachineResidue
    Assert-YuneWindowsCleanPreInstallSnapshot `
        -Path $PreInstallStatePath `
        -Context "Live smoke pre-install state"
}
catch {
    Write-LiveSmokeResult `
        -Status "failed" `
        -FailureStage $CurrentStage `
        -FailureMessage $_.Exception.Message
    throw
}

try {
    $CurrentStage = "install"
    $InstallCommand = "tools\install-yune-windows-ime.ps1 -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)"
    Record-Command $InstallCommand
    try {
        & (Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1") `
            -YuneRoot $YuneRoot `
            -InstallDir $InstallDir `
            -ApprovedMachineStateChange `
            -ApprovalNote $ApprovalNote
        Record-CommandSuccess $InstallCommand
    }
    catch {
        Record-CommandFailure $InstallCommand $_.Exception.Message
        throw
    }

    $CurrentStage = "post-install-state"
    $PostInstallStatePath = Join-Path $InstallerEvidence "post-install-state.json"
    Write-YuneWindowsStateSnapshot `
        -Path $PostInstallStatePath `
        -InstallDir $InstallDir `
        -ApprovalNote $ApprovalNote `
        -IncludeMachineRegistration
    Assert-YuneWindowsRegisteredInstalledSnapshot `
        -Path $PostInstallStatePath `
        -Context "Live smoke post-install state"

    $CurrentStage = "notepad-smoke"
    $NotepadCommand = "tools\run-notepad-smoke.ps1 -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -EvidenceDir $(Format-CommandValue $TsfEvidence) -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)"
    Record-Command $NotepadCommand
    try {
        Invoke-YuneWindowsInteractiveScript `
            -ScriptPath (Join-Path $RepoRoot "tools\run-notepad-smoke.ps1") `
            -ArgumentList @(
                "-YuneRoot", $YuneRoot,
                "-InstallDir", $InstallDir,
                "-EvidenceDir", $TsfEvidence,
                "-ApprovedMachineStateChange",
                "-ApprovalNote", $ApprovalNote
            ) `
            -StatusPath (Join-Path $TsfEvidence "notepad-interactive-status.json") `
            -WorkingDirectory $RepoRoot `
            -Operation "Notepad smoke"
        Record-CommandSuccess $NotepadCommand
    }
    catch {
        Record-CommandFailure $NotepadCommand $_.Exception.Message
        throw
    }

    $CurrentStage = "chromium-smoke"
    $ChromiumCommand = "tools\run-chromium-smoke.ps1 -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -EvidenceDir $(Format-CommandValue $TsfEvidence)"
    $ChromiumCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"
    $ChromiumCommand += " -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)"
    Record-Command $ChromiumCommand
    try {
        Invoke-YuneWindowsInteractiveScript `
            -ScriptPath (Join-Path $RepoRoot "tools\run-chromium-smoke.ps1") `
            -ArgumentList @(
                "-YuneRoot", $YuneRoot,
                "-InstallDir", $InstallDir,
                "-EvidenceDir", $TsfEvidence,
                "-BrowserPath", $ResolvedBrowserPath,
                "-ApprovedMachineStateChange",
                "-ApprovalNote", $ApprovalNote
            ) `
            -StatusPath (Join-Path $TsfEvidence "chromium-interactive-status.json") `
            -WorkingDirectory $RepoRoot `
            -Operation "Chromium smoke"
        Record-CommandSuccess $ChromiumCommand
    }
    catch {
        Record-CommandFailure $ChromiumCommand $_.Exception.Message
        throw
    }

    $CurrentStage = "diagnostics-profile-reactivation"
    $DiagnosticsProfileTool = Join-Path $InstallDir "YuneWindowsProfileTool.exe"
    $DiagnosticsActivationCommand = "YuneWindowsProfileTool.exe --activate for diagnostics pre-state"
    Record-Command $DiagnosticsActivationCommand
    try {
        Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $DiagnosticsProfileTool `
            -Arguments @("--activate") `
            -Operation "diagnostics pre-state profile reactivation" | Out-Null
        Assert-YuneWindowsProfileActive `
            -ProfileToolPath $DiagnosticsProfileTool `
            -Context "Diagnostics pre-state"
        Record-CommandSuccess $DiagnosticsActivationCommand
    }
    catch {
        Record-CommandFailure $DiagnosticsActivationCommand $_.Exception.Message
        throw
    }

    $CurrentStage = "diagnostics-pre-state"
    $DiagnosticsPreStatePath = Join-Path $DiagnosticsEvidence "diagnostics-pre-state.json"
    Invoke-YuneWindowsInteractiveScript `
        -ScriptPath (Join-Path $RepoRoot "tools\write-yune-windows-state-snapshot.ps1") `
        -ArgumentList @(
            "-Path", $DiagnosticsPreStatePath,
            "-InstallDir", $InstallDir,
            "-ApprovalNote", $ApprovalNote,
            "-AssertActiveInstalled"
        ) `
        -StatusPath (Join-Path $DiagnosticsEvidence "diagnostics-pre-state-interactive-status.json") `
        -WorkingDirectory $RepoRoot `
        -Operation "Diagnostics pre-state active-profile snapshot"
    Assert-YuneWindowsActiveInstalledSnapshot `
        -Path $DiagnosticsPreStatePath `
        -Context "Diagnostics export pre-state"

    $DiagnosticsDir = Join-Path $DiagnosticsEvidence "registered-session-diagnostics"
    $CurrentStage = "diagnostics-export"
    $DiagnosticsCommand = "tools\export-yune-windows-diagnostics.ps1 -OutputDir $(Format-CommandValue $DiagnosticsDir) -InstallDir $(Format-CommandValue $InstallDir)"
    Record-Command $DiagnosticsCommand
    try {
        $DiagnosticsBundle = & (Join-Path $RepoRoot "tools\export-yune-windows-diagnostics.ps1") `
            -OutputDir $DiagnosticsDir `
            -InstallDir $InstallDir
        $DiagnosticsBundleText = ($DiagnosticsBundle | Select-Object -Last 1)
        Assert-DiagnosticsBundleEvidence -Path $DiagnosticsBundleText -OutputDir $DiagnosticsDir -NotBefore $ApprovalDate -PreStatePath $DiagnosticsPreStatePath
        Record-CommandSuccess $DiagnosticsCommand
    }
    catch {
        Record-CommandFailure $DiagnosticsCommand $_.Exception.Message
        throw
    }

    $LiveSmokeSucceeded = $true
}
catch {
    Write-LiveSmokeResult `
        -Status "failed" `
        -FailureStage $CurrentStage `
        -FailureMessage $_.Exception.Message
    throw
}
finally {
    $CleanupFailureMessage = ""
    try {
        $CurrentStage = "cleanup-host-processes"
        $ChromiumProfileRoot = Join-Path $env:TEMP "yune-windows\chromium-smoke\profile"
        $HostProcessDrainCommand = "Stop-YuneWindowsLiveSmokeHostProcesses -StartedAfter $(Format-CommandValue ($LiveSmokeStartedAt.ToString("o"))) -ChromiumProfileRoot $(Format-CommandValue $ChromiumProfileRoot)"
        Record-Command $HostProcessDrainCommand
        try {
            Stop-YuneWindowsLiveSmokeHostProcesses `
                -StartedAfter $LiveSmokeStartedAt `
                -ChromiumProfileRoot $ChromiumProfileRoot
            Record-CommandSuccess $HostProcessDrainCommand
        }
        catch {
            Record-CommandFailure $HostProcessDrainCommand $_.Exception.Message
            $CleanupFailureMessage = $_.Exception.Message
        }

        $CurrentStage = "cleanup"
        $UninstallCommand = "tools\uninstall-yune-windows-ime.ps1 -InstallDir $(Format-CommandValue $InstallDir) -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)"
        Record-Command $UninstallCommand
        try {
            & (Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1") `
                -InstallDir $InstallDir `
                -ApprovedMachineStateChange `
                -ApprovalNote $ApprovalNote
            Record-CommandSuccess $UninstallCommand
        }
        catch {
            Record-CommandFailure $UninstallCommand $_.Exception.Message
            throw
        }
    }
    catch {
        if ($CleanupFailureMessage -ne "") {
            $CleanupFailureMessage += "; "
        }
        $CleanupFailureMessage += $_.Exception.Message
    }
    finally {
        try {
            $CurrentStage = "post-cleanup-state"
            $PostCleanupStatePath = Join-Path $InstallerEvidence "post-cleanup-state.json"
            Write-YuneWindowsStateSnapshot `
                -Path $PostCleanupStatePath `
                -InstallDir $InstallDir `
                -ProfileToolPath $ProfileProbePath `
                -ApprovalNote $ApprovalNote `
                -IncludeMachineResidue

            $CleanupSnapshot = Get-Content -Raw -LiteralPath $PostCleanupStatePath |
                ConvertFrom-Json
            $CurrentStage = "cleanup-validation"
            $CleanupValidation = Test-YuneWindowsCleanupState `
                -Snapshot $CleanupSnapshot `
                -RequireProfileState `
                -RequireMachineResidueCheck `
                -RequireCapturedAt
            $CleanupValidationPath = Join-Path $InstallerEvidence "cleanup-validation.json"
            $CleanupValidation | ConvertTo-Json -Depth 6 |
                Out-File -LiteralPath $CleanupValidationPath -Encoding utf8
            $CleanupResultStatus = if ($CleanupValidation.pass) { "passed" } else { "failed" }

            @(
                "# Cleanup Result",
                "",
                "Date: $((Get-Date).ToString("o"))",
                "",
                "Status: $CleanupResultStatus",
                "",
                "Uninstall script: ``tools\uninstall-yune-windows-ime.ps1``.",
                "",
                "Cleanup state snapshot: ``post-cleanup-state.json``.",
                "",
                "Cleanup validation: ``cleanup-validation.json``.",
                "",
                "Pass: $($CleanupValidation.pass)",
                "",
                "Review criteria:",
                "",
                "- install directory removed unless ``-KeepFiles`` was used;",
                "- installed ``YuneWindowsProfileTool.exe`` removed;",
                "- no ``YuneWindowsServer.exe`` process remains;",
                "- YuneWindows TSF profile state is absent or inactive;",
                "- machine-state registry and PendingFileRenameOperations residue were checked;",
                "- no YuneWindows filesystem leftovers remain in machine-level Windows directories."
            ) | Out-File -LiteralPath $CleanupPath -Encoding utf8
        }
        catch {
            Write-LiveSmokeResult `
                -Status "failed" `
                -FailureStage $CurrentStage `
                -FailureMessage $_.Exception.Message `
                -DiagnosticsBundle $DiagnosticsBundleText
            throw
        }

        if (-not $CleanupValidation.pass) {
            $CleanupMessage = "Cleanup validation failed: $($CleanupValidation.issues -join '; ')"
            Write-LiveSmokeResult `
                -Status "failed" `
                -FailureStage $CurrentStage `
                -FailureMessage $CleanupMessage `
                -DiagnosticsBundle $DiagnosticsBundleText
            throw $CleanupMessage
        }

        if ($CleanupFailureMessage -ne "") {
            Write-LiveSmokeResult `
                -Status "failed" `
                -FailureStage "cleanup" `
                -FailureMessage $CleanupFailureMessage `
                -DiagnosticsBundle $DiagnosticsBundleText
            throw $CleanupFailureMessage
        }

        if ($LiveSmokeSucceeded) {
            Write-LiveSmokeResult `
                -Status "passed" `
                -DiagnosticsBundle $DiagnosticsBundleText

            $CurrentStage = "closeout-audit"
            try {
                $AuditCommand = "tools\audit-p2-win01-closeout.ps1 -RequireComplete"
                Record-Command $AuditCommand
                & (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") -RequireComplete | Out-Null
                Record-CommandSuccess $AuditCommand
            }
            catch {
                Record-CommandFailure $AuditCommand $_.Exception.Message
                Write-LiveSmokeResult `
                    -Status "failed" `
                    -FailureStage $CurrentStage `
                    -FailureMessage $_.Exception.Message `
                    -DiagnosticsBundle $DiagnosticsBundleText
                throw
            }
        }
    }
}

Write-Host "P2-WIN01 live smoke sequence finished. Review $ResultPath and $CleanupPath."
