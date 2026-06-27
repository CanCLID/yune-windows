param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$EvidenceRoot = "",
    [string]$BrowserPath = "",
    [string]$PrepPreflightPath = "",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = "",
    [string]$TranscriptPath = "",
    [string]$LaunchResultPath = "",
    [string]$PowerShellPath = "powershell.exe",
    [switch]$ValidatePrepOnly
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RepoRoot = [System.IO.Path]::GetFullPath([string]$RepoRoot)
$YuneRoot = [System.IO.Path]::GetFullPath($YuneRoot)
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
if ($EvidenceRoot -eq "") {
    $EvidenceRoot = Join-Path $RepoRoot "docs\evidence"
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
if ($PrepPreflightPath -eq "") {
    $PrepPreflightPath = Join-Path $EvidenceRoot "p2-win01-installer\live-preflight.json"
}
$PrepPreflightPath = [System.IO.Path]::GetFullPath($PrepPreflightPath)

if ($ValidatePrepOnly.IsPresent) {
    if ($ApprovedMachineStateChange.IsPresent -or
        (-not [string]::IsNullOrWhiteSpace($ApprovalNote))) {
        throw "ValidatePrepOnly is non-mutating prep validation and must not carry approval switches or approval notes."
    }
}
else {
    Require-ApprovedMachineStateChange `
        -Approved $ApprovedMachineStateChange.IsPresent `
        -Action "start the elevated P2-WIN01 live smoke sequence"
    Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
}

$InstallerEvidence = Join-Path $EvidenceRoot "p2-win01-installer"
New-Item -ItemType Directory -Force $InstallerEvidence | Out-Null
if ($TranscriptPath -eq "") {
    $TranscriptPath = Join-Path $InstallerEvidence ("elevated-live-smoke-transcript-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}
$TranscriptPath = [System.IO.Path]::GetFullPath($TranscriptPath)
if ($LaunchResultPath -eq "") {
    $LaunchResultPath = Join-Path $InstallerEvidence "elevated-live-smoke-launch-result.json"
}
$LaunchResultPath = [System.IO.Path]::GetFullPath($LaunchResultPath)

$ResolvedBrowserPath = Find-ChromiumBrowserPath -RequestedPath $BrowserPath
Assert-ConcreteChromiumBrowserPath `
    -PathValue $ResolvedBrowserPath `
    -Source "Elevated live-smoke launcher browser path"

function ConvertTo-PowerShellLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Write-ElevatedLiveSmokeLaunchResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [Parameter(Mandatory = $true)]
        [bool]$ElevatedProcessStarted,
        [AllowNull()]
        [Nullable[int]]$ExitCode,
        [string]$ErrorMessage = ""
    )

    $Result = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        status = $Status
        approved_machine_state_change = $ApprovedMachineStateChange.IsPresent
        approval_note = $ApprovalNote
        elevated_process_started = $ElevatedProcessStarted
        exit_code = $ExitCode
        error_message = $ErrorMessage
        transcript_exists = (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)
        machine_state_changed_before_elevated_process = $false
        repo_root = $RepoRoot
        yune_root = $YuneRoot
        install_dir = $InstallDir
        evidence_root = $EvidenceRoot
        browser_path = $ResolvedBrowserPath
        prep_preflight_path = $PrepPreflightPath
        transcript_path = $TranscriptPath
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $LaunchResultPath) | Out-Null
    $Result | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $LaunchResultPath -Encoding utf8
}

function Get-PrepPreflightProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $Report.PSObject.Properties.Name.Contains($Name)) {
        throw "prep preflight is missing $Name."
    }
    return $Report.PSObject.Properties[$Name].Value
}

function Assert-PrepPreflightBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [AllowNull()]
        [object]$Expected = $null
    )

    $Value = Get-PrepPreflightProperty -Report $Report -Name $Name
    if ($Value -isnot [bool]) {
        throw "prep preflight $Name must be a JSON boolean."
    }
    if (($null -ne $Expected) -and ($Value -ne [bool]$Expected)) {
        throw "prep preflight must record $Name=$(([bool]$Expected).ToString().ToLowerInvariant())."
    }
}

function Assert-PrepPreflightReadyForElevation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedYuneRoot,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedInstallDir,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedBrowserPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing prep preflight evidence: $Path"
    }

    try {
        $Report = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "prep preflight evidence is not valid JSON: $Path"
    }

    $GeneratedAt = [string](Get-PrepPreflightProperty -Report $Report -Name "generated_at")
    if ([string]::IsNullOrWhiteSpace($GeneratedAt)) {
        throw "prep preflight generated_at is missing."
    }
    try {
        [void][System.DateTimeOffset]::Parse(
            $GeneratedAt,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        throw "prep preflight generated_at is not a parseable ISO timestamp."
    }

    $ResidueSource = [string](Get-PrepPreflightProperty -Report $Report -Name "machine_residue_source")
    if ([string]::IsNullOrWhiteSpace($ResidueSource)) {
        throw "prep preflight machine_residue_source is missing."
    }
    $ResidueSourcePath = $null
    try {
        $ResidueSourcePath = [System.IO.Path]::GetFullPath($ResidueSource)
    }
    catch {
        throw "prep preflight machine_residue_source is invalid: $ResidueSource"
    }
    if ($ResidueSourcePath -ieq $Path) {
        throw "prep preflight machine_residue_source must not point to itself."
    }

    Assert-PrepPreflightBoolean -Report $Report -Name "ready_for_live_smoke"
    Assert-PrepPreflightBoolean -Report $Report -Name "is_administrator"
    foreach ($BooleanCheck in @(
            @{ Name = "machine_state_changed"; Expected = $false },
            @{ Name = "machine_state_checked"; Expected = $true },
            @{ Name = "install_dir_exists"; Expected = $false },
            @{ Name = "yune_runtime_exists"; Expected = $true },
            @{ Name = "yune_schema_exists"; Expected = $true },
            @{ Name = "tsf_source_exists"; Expected = $true },
            @{ Name = "server_source_exists"; Expected = $true },
            @{ Name = "build_script_exists"; Expected = $true },
            @{ Name = "is_sta"; Expected = $true },
            @{ Name = "browser_available"; Expected = $true }
        )) {
        Assert-PrepPreflightBoolean `
            -Report $Report `
            -Name $BooleanCheck.Name `
            -Expected ([bool]$BooleanCheck.Expected)
    }

    $MachineStateIssues = @(Get-PrepPreflightProperty -Report $Report -Name "machine_state_issues")
    if ($MachineStateIssues.Count -ne 0) {
        throw "prep preflight machine_state_issues must be empty before UAC."
    }
    $FilesystemLeftovers = @(Get-PrepPreflightProperty -Report $Report -Name "filesystem_leftovers")
    if ($FilesystemLeftovers.Count -ne 0) {
        throw "prep preflight filesystem_leftovers must be empty before UAC."
    }

    $ServerProcessCount = Get-PrepPreflightProperty -Report $Report -Name "server_process_count"
    if (($ServerProcessCount -isnot [int]) -and
        ($ServerProcessCount -isnot [long]) -and
        ($ServerProcessCount -isnot [double]) -and
        ($ServerProcessCount -isnot [decimal])) {
        throw "prep preflight server_process_count must be a JSON number."
    }
    if ([int]$ServerProcessCount -ne 0) {
        throw "prep preflight server_process_count must be 0 before UAC."
    }

    $ReportInstallDir = [System.IO.Path]::GetFullPath([string](Get-PrepPreflightProperty -Report $Report -Name "install_dir"))
    if ($ReportInstallDir -ine $ExpectedInstallDir) {
        throw "prep preflight install_dir does not match approved install path: $ReportInstallDir"
    }
    $ReportYuneRoot = [System.IO.Path]::GetFullPath([string](Get-PrepPreflightProperty -Report $Report -Name "yune_root"))
    if ($ReportYuneRoot -ine $ExpectedYuneRoot) {
        throw "prep preflight yune_root does not match approved Yune root: $ReportYuneRoot"
    }
    $ReportBrowserPath = [System.IO.Path]::GetFullPath([string](Get-PrepPreflightProperty -Report $Report -Name "browser_path"))
    Assert-ConcreteChromiumBrowserPath `
        -PathValue $ReportBrowserPath `
        -Source "Prep preflight browser path"
    if (-not (Test-Path -LiteralPath $ReportBrowserPath -PathType Leaf)) {
        throw "prep preflight browser_path does not exist: $ReportBrowserPath"
    }
    if ($ReportBrowserPath -ine $ExpectedBrowserPath) {
        throw "prep preflight browser_path does not match resolved browser path: $ReportBrowserPath"
    }
}

try {
    Assert-PrepPreflightReadyForElevation `
        -Path $PrepPreflightPath `
        -ExpectedYuneRoot $YuneRoot `
        -ExpectedInstallDir $InstallDir `
        -ExpectedBrowserPath $ResolvedBrowserPath
}
catch {
    $Message = $_.Exception.Message
    Write-ElevatedLiveSmokeLaunchResult `
        -Status "prep-preflight-invalid" `
        -ElevatedProcessStarted $false `
        -ExitCode $null `
        -ErrorMessage $Message
    throw "Elevated live smoke launch did not start (prep-preflight-invalid): $Message"
}

if ($ValidatePrepOnly.IsPresent) {
    Write-ElevatedLiveSmokeLaunchResult `
        -Status "prep-preflight-ready" `
        -ElevatedProcessStarted $false `
        -ExitCode $null
    Write-Host "Elevated live smoke launch did not start (prep-preflight-ready): prep preflight is valid."
    Write-Host "Launch result: $LaunchResultPath"
    return
}

$LiveSmokeScript = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$InnerScript = @"
`$ErrorActionPreference = "Stop"
`$exitCode = 1
Set-Location -LiteralPath $(ConvertTo-PowerShellLiteral $RepoRoot)
Start-Transcript -LiteralPath $(ConvertTo-PowerShellLiteral $TranscriptPath) -Force
try {
    & $(ConvertTo-PowerShellLiteral $LiveSmokeScript) -ApprovedMachineStateChange -ApprovalNote $(ConvertTo-PowerShellLiteral $ApprovalNote) -YuneRoot $(ConvertTo-PowerShellLiteral $YuneRoot) -InstallDir $(ConvertTo-PowerShellLiteral $InstallDir) -EvidenceRoot $(ConvertTo-PowerShellLiteral $EvidenceRoot) -BrowserPath $(ConvertTo-PowerShellLiteral $ResolvedBrowserPath)
    `$exitCode = `$LASTEXITCODE
    if (`$null -eq `$exitCode) {
        `$exitCode = 0
    }
}
catch {
    Write-Error `$_.Exception.Message
    `$exitCode = 1
}
finally {
    Stop-Transcript
}
exit `$exitCode
"@

$EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($InnerScript))
try {
    $Process = Start-Process `
        -FilePath $PowerShellPath `
        -Verb RunAs `
        -WindowStyle Hidden `
        -ArgumentList @("-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $EncodedCommand) `
        -Wait `
        -PassThru
}
catch {
    $Message = $_.Exception.Message
    $Status = "failed-to-start"
    if ($Message -match "operation was canceled") {
        $Status = "elevation-canceled"
    }
    Write-ElevatedLiveSmokeLaunchResult `
        -Status $Status `
        -ElevatedProcessStarted $false `
        -ExitCode $null `
        -ErrorMessage $Message
    throw "Elevated live smoke launch did not start ($Status): $Message"
}

$ExitCode = 0
if ($null -ne $Process.ExitCode) {
    $ExitCode = [int]$Process.ExitCode
}

if ($ExitCode -eq 0) {
    Write-ElevatedLiveSmokeLaunchResult `
        -Status "completed" `
        -ElevatedProcessStarted $true `
        -ExitCode $ExitCode
    Write-Host "Elevated live smoke completed. Transcript: $TranscriptPath"
    Write-Host "Launch result: $LaunchResultPath"
    return
}

Write-ElevatedLiveSmokeLaunchResult `
    -Status "failed" `
    -ElevatedProcessStarted $true `
    -ExitCode $ExitCode `
    -ErrorMessage "Elevated live smoke exited with code $ExitCode."
throw "Elevated live smoke exited with code $ExitCode. Transcript: $TranscriptPath"
