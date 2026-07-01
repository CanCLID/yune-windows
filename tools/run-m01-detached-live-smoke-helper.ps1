param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$EvidenceRoot = "",
    [string]$BrowserPath = "",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = "",
    [string]$HelperResultPath = "",
    [string]$HelperTranscriptPath = "",
    [int]$WaitTimeoutMinutes = 45,
    [string[]]$WaitForProcessNames = @("Codex", "Zed")
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
$InstallerEvidence = Join-Path $EvidenceRoot "m01\installer"
if ($HelperResultPath -eq "") {
    $HelperResultPath = Join-Path $InstallerEvidence "detached-live-smoke-helper-result.json"
}
$HelperResultPath = [System.IO.Path]::GetFullPath($HelperResultPath)
if ($HelperTranscriptPath -eq "") {
    $HelperTranscriptPath = Join-Path $InstallerEvidence ("detached-live-smoke-helper-transcript-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}
$HelperTranscriptPath = [System.IO.Path]::GetFullPath($HelperTranscriptPath)
$ResolvedBrowserPath = Find-ChromiumBrowserPath -RequestedPath $BrowserPath
Assert-ConcreteChromiumBrowserPath `
    -PathValue $ResolvedBrowserPath `
    -Source "Detached live-smoke helper browser path"

$Stage = "starting"
$InitialProcessIds = @{}
$ExitCode = 1

function Get-BlockingProcessIds {
    $Result = [ordered]@{}
    foreach ($Name in $WaitForProcessNames) {
        $Result[$Name] = @(Get-Process -Name $Name -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id)
    }
    return [pscustomobject]$Result
}

function Write-HelperResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatusValue,
        [Parameter(Mandatory = $true)]
        [string]$StageValue,
        [string]$Message = "",
        [AllowNull()]
        [Nullable[int]]$ExitCodeValue = $null
    )

    $Blocking = Get-BlockingProcessIds
    $Initial = [ordered]@{}
    $Remaining = [ordered]@{}
    foreach ($Name in $WaitForProcessNames) {
        $Initial[$Name] = @($InitialProcessIds[$Name])
        $Remaining[$Name] = @($Blocking.PSObject.Properties[$Name].Value)
    }

    $Result = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        status = $StatusValue
        stage = $StageValue
        error_message = $Message
        exit_code = $ExitCodeValue
        approved_machine_state_change = $ApprovedMachineStateChange.IsPresent
        approval_note = $ApprovalNote
        helper_elevated = Test-IsAdministrator
        helper_is_sta = ([Threading.Thread]::CurrentThread.ApartmentState -eq "STA")
        initial_process_ids = $Initial
        remaining_process_ids = $Remaining
        repo_root = $RepoRoot
        yune_root = $YuneRoot
        install_dir = $InstallDir
        install_dir_exists = (Test-Path -LiteralPath $InstallDir)
        evidence_root = $EvidenceRoot
        browser_path = $ResolvedBrowserPath
        transcript_path = $HelperTranscriptPath
        transcript_exists = (Test-Path -LiteralPath $HelperTranscriptPath -PathType Leaf)
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $HelperResultPath) | Out-Null
    $Result | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $HelperResultPath -Encoding utf8
}

try {
    foreach ($Name in $WaitForProcessNames) {
        $InitialProcessIds[$Name] = @(Get-Process -Name $Name -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id)
    }

    Require-ApprovedMachineStateChange `
        -Approved $ApprovedMachineStateChange.IsPresent `
        -Action "run the detached M01 live smoke helper"
    Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
    if (-not (Test-IsAdministrator)) {
        throw "Detached live-smoke helper requires an elevated PowerShell session."
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
        throw "Detached live-smoke helper requires an STA PowerShell session."
    }

    Start-Transcript -LiteralPath $HelperTranscriptPath -Force
    Set-Location -LiteralPath $RepoRoot

    $Stage = "waiting-for-process-exit"
    Write-HelperResult `
        -StatusValue "waiting-for-process-exit" `
        -StageValue $Stage `
        -ExitCodeValue $null
    $Deadline = (Get-Date).AddMinutes($WaitTimeoutMinutes)
    while ($true) {
        $Blocking = Get-BlockingProcessIds
        $Remaining = @()
        foreach ($Name in $WaitForProcessNames) {
            $Ids = @($Blocking.PSObject.Properties[$Name].Value)
            if ($Ids.Count -gt 0) {
                $Remaining += "$Name=$($Ids -join ',')"
            }
        }
        if ($Remaining.Count -eq 0) {
            break
        }
        if ((Get-Date) -gt $Deadline) {
            throw "Timed out waiting for process exit: $($Remaining -join '; ')"
        }
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Seconds 3

    $Stage = "prelive-cleanup"
    Write-HelperResult -StatusValue "running" -StageValue $Stage -ExitCodeValue $null
    & (Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1") `
        -InstallDir $InstallDir `
        -ApprovedMachineStateChange `
        -ApprovalNote $ApprovalNote

    $Stage = "preflight-refresh"
    Write-HelperResult -StatusValue "running" -StageValue $Stage -ExitCodeValue $null
    & (Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1") `
        -PreflightOnly `
        -PreflightPath (Join-Path $InstallerEvidence "live-preflight.json") `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -EvidenceRoot $EvidenceRoot `
        -RefreshCurrentResidue `
        -ApprovalNote $ApprovalNote `
        -BrowserPath $ResolvedBrowserPath | Out-Host
    & (Join-Path $RepoRoot "tools\plan-yune-windows-machine-cleanup.ps1") `
        -InstallDir $InstallDir `
        -OutputPath (Join-Path $InstallerEvidence "machine-cleanup-plan.json") `
        -RefreshCurrentResidue `
        -ApprovalNote $ApprovalNote | Out-Host

    $Stage = "prep-validation"
    Write-HelperResult -StatusValue "running" -StageValue $Stage -ExitCodeValue $null
    & (Join-Path $RepoRoot "tools\start-m01-elevated-live-smoke.ps1") `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -PrepPreflightPath (Join-Path $InstallerEvidence "live-preflight.json") `
        -LaunchResultPath (Join-Path $InstallerEvidence "elevated-live-smoke-prep-validation-result.json") `
        -ValidatePrepOnly `
        -BrowserPath $ResolvedBrowserPath | Out-Host

    $Stage = "full-live-smoke"
    Write-HelperResult -StatusValue "running" -StageValue $Stage -ExitCodeValue $null
    & (Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1") `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -EvidenceRoot $EvidenceRoot `
        -BrowserPath $ResolvedBrowserPath `
        -ApprovedMachineStateChange `
        -ApprovalNote $ApprovalNote

    $Stage = "final-audit"
    Write-HelperResult -StatusValue "running" -StageValue $Stage -ExitCodeValue $null
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") -RequireComplete | Out-Host

    $ExitCode = 0
    Write-HelperResult `
        -StatusValue "completed" `
        -StageValue "completed" `
        -ExitCodeValue $ExitCode
}
catch {
    $Message = $_.Exception.Message
    Write-HelperResult `
        -StatusValue "failed" `
        -StageValue $Stage `
        -Message $Message `
        -ExitCodeValue 1
    Write-Error $Message
    $ExitCode = 1
}
finally {
    try {
        Stop-Transcript
    }
    catch {
    }
}

exit $ExitCode
