param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$EvidenceDir = "",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

Require-ApprovedMachineStateChange `
    -Approved $ApprovedMachineStateChange.IsPresent `
    -Action "activate the IME and drive Notepad"

Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote

if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    throw "Run this smoke from an STA PowerShell session so clipboard evidence can be captured."
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
$ProfileTool = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"
if (-not (Test-Path -LiteralPath $ProfileTool)) {
    throw "missing installed profile tool: $ProfileTool"
}

if ($EvidenceDir -eq "") {
    $EvidenceDir = Join-Path $RepoRoot "docs\evidence\p2-win01-tsf-smoke"
}
New-Item -ItemType Directory -Force $EvidenceDir | Out-Null
$ResultPath = Join-Path $EvidenceDir "notepad-smoke-result.md"
$PostStatePath = Join-Path $EvidenceDir "notepad-post-state.json"
$TypedInput = "ngohaig"
$ExpectedCommitText = -join ([char[]](0x6211, 0x4fc2, 0x500b))
$StructuralLogPath = Join-Path $InstallRoot "logs\tsf-events.log"
$StructuralLogStartLineCount = 0
$StructuralLogBaselineCaptured = $false
$CurrentStage = "pre-state"
$ResultWritten = $false
$PostStateSnapshotWritten = $false
$ClipboardClearedBeforeTyping = $false
$ClipboardClearedAfterCapture = $false
$ClipboardClearedAfterFailure = $false
$ForegroundTargetVerifiedBeforeTyping = $false
$ActiveProfileVerifiedBeforeTyping = $false
$ProfileActiveVerifiedBeforeTyping = $false
$ProductOwnedServerStartObserved = $false
$ProductOwnedServerReadyObserved = $false
$CandidateScreenshotCaptured = $false
$CommitScreenshotCaptured = $false
$CandidateCommitScreenshotsDistinct = $false
$FailureScreenshotName = "failure-notepad.png"
$Observed = ""
$Pass = $false
$Raw = "Unknown"
$MatchesExpectedCommit = $false
$StructuralCandidateUpdateObserved = $false
$StructuralCandidateUpdateCandidateCountPositive = $false
$StructuralCommitEventObserved = $false
$StructuralCandidateWindowFailureObserved = $false
$NewStructuralLogLines = @()
$StructuralEventSummary = "none"

function Get-StructuralLogLineCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }
    return @(Get-Content -LiteralPath $Path).Count
}

function Get-NewStructuralLogLines {
    param(
        [string]$Path,
        [int]$StartLineCount
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    $Lines = @(Get-Content -LiteralPath $Path)
    if ($Lines.Count -le $StartLineCount) {
        return @()
    }
    return @($Lines[$StartLineCount..($Lines.Count - 1)])
}

function Update-StructuralSmokeEvidence {
    if (-not $script:StructuralLogBaselineCaptured) {
        return
    }

    $script:NewStructuralLogLines = @(Get-NewStructuralLogLines `
            -Path $script:StructuralLogPath `
            -StartLineCount $script:StructuralLogStartLineCount)
    $script:StructuralEventSummary = Get-StructuralEventSummary -Lines $script:NewStructuralLogLines
    $script:StructuralCandidateUpdateObserved = [bool]($script:NewStructuralLogLines |
            Where-Object { Test-StructuralCandidateUpdateLine -Line $_ } |
            Select-Object -First 1)
    $script:StructuralCandidateUpdateCandidateCountPositive =
        $script:StructuralCandidateUpdateObserved
    $script:StructuralCommitEventObserved = [bool]($script:NewStructuralLogLines |
            Where-Object { Test-StructuralEventLine -Line $_ -EventName "commit_text" } |
            Select-Object -First 1)
    $script:StructuralCandidateWindowFailureObserved =
        [bool]($script:NewStructuralLogLines |
            Where-Object { Test-StructuralEventLine -Line $_ -EventName "candidate_window_failed" } |
            Select-Object -First 1)
}

function Write-TextSmokeResult {
    param(
        [string]$Status,
        [string]$FailureStage = "",
        [string]$FailureMessage = "",
        [string]$FailureScreenshot = "",
        [string]$FailureScreenshotCaptured = "False",
        [string]$FailureScreenshotError = "",
        [string]$Observed = "",
        [string]$Pass = "False",
        [string]$Raw = "Unknown",
        [string]$ForegroundTargetVerifiedBeforeTyping = "False",
        [string]$ActiveProfileVerifiedBeforeTyping = "False",
        [string]$ProfileActiveVerifiedBeforeTyping = "False",
        [string]$ClipboardClearedBeforeTyping = "False",
        [string]$ClipboardClearedAfterCapture = "False",
        [string]$ClipboardClearedAfterFailure = "False",
        [string]$CandidateScreenshotCaptured = "False",
        [string]$CommitScreenshotCaptured = "False",
        [string]$CandidateCommitScreenshotsDistinct = "False",
        [string]$MatchesExpectedCommit = "False",
        [string]$StructuralCandidateUpdateObserved = "False",
        [string]$StructuralCandidateUpdateCandidateCountPositive = "False",
        [string]$StructuralCommitEventObserved = "False",
        [string]$StructuralCandidateWindowFailureObserved = "False",
        [string]$StructuralNewLineCount = "0",
        [string]$ProductOwnedServerStartObserved = "False",
        [string]$ProductOwnedServerReadyObserved = "False"
    )

    $Lines = @(
        "# Notepad Smoke Result",
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
            "",
            "Failure screenshot: $FailureScreenshot",
            "",
            "Failure screenshot captured: $FailureScreenshotCaptured",
            "",
            $(if ([string]::IsNullOrEmpty($FailureScreenshotError)) { "Failure screenshot error:" } else { "Failure screenshot error: $FailureScreenshotError" }),
            "",
            "Clipboard cleared after failure: $ClipboardClearedAfterFailure",
            ""
        )
    }
    $Lines += @(
        "Input: ``$TypedInput`` followed by space.",
        "",
        "Input method: Win32 virtual-key typed test input.",
        "",
        'Candidate-display screenshot: `candidate-display-notepad.png`.',
        "",
        "Candidate-display screenshot captured: $CandidateScreenshotCaptured",
        "",
        'Commit screenshot: `notepad-commit.png`.',
        "",
        "Commit screenshot captured: $CommitScreenshotCaptured",
        "",
        "Candidate/commit screenshots distinct: $CandidateCommitScreenshotsDistinct",
        "",
        "Expected committed text:",
        "",
        "````text",
        $ExpectedCommitText,
        "````",
        "",
        "Observed clipboard text after select-all/copy:",
        "",
        "````text",
        $Observed,
        "````",
        "",
        "Pass: $Pass",
        "",
        "Raw ASCII observed: $Raw",
        "",
        "Foreground target verified before typing: $ForegroundTargetVerifiedBeforeTyping",
        "",
        "Active profile verified before typing: $ActiveProfileVerifiedBeforeTyping",
        "",
        "profile_active_verified_before_typing: $ProfileActiveVerifiedBeforeTyping",
        "",
        "Clipboard cleared before typing: $ClipboardClearedBeforeTyping",
        "",
        "Clipboard cleared after capture: $ClipboardClearedAfterCapture",
        "",
        "Matches expected Yune commit: $MatchesExpectedCommit",
        "",
        "Structural candidate update observed: $StructuralCandidateUpdateObserved",
        "",
        "Structural candidate update candidate count positive: $StructuralCandidateUpdateCandidateCountPositive",
        "",
        "Structural commit event observed: $StructuralCommitEventObserved",
        "",
        "Structural candidate window failure observed: $StructuralCandidateWindowFailureObserved",
        "",
        "Structural event matcher: exact event tokens",
        "",
        "Structural event summary: $StructuralEventSummary",
        "",
        "Structural new log lines: $StructuralNewLineCount",
        "",
        "product_owned_server_start_observed: $ProductOwnedServerStartObserved",
        "",
        "product_owned_server_ready_observed: $ProductOwnedServerReadyObserved"
    )
    $Lines | Out-File -LiteralPath $ResultPath -Encoding utf8
    $script:ResultWritten = $true
}

function Write-PostSmokeStateSnapshot {
    Write-YuneWindowsStateSnapshot `
        -Path $PostStatePath `
        -InstallDir $InstallRoot
    Assert-YuneWindowsActiveInstalledSnapshot `
        -Path $PostStatePath `
        -Context "Notepad smoke post-state"
    $script:PostStateSnapshotWritten = $true
}

Write-YuneWindowsStateSnapshot `
    -Path (Join-Path $EvidenceDir "notepad-pre-state.json") `
    -InstallDir $InstallRoot

Add-Type -AssemblyName System.Windows.Forms
$Shell = New-Object -ComObject WScript.Shell
$Notepad = $null
$NotepadLaunchTime = [DateTime]::MinValue
$NotepadForegroundProcessId = 0
$NotepadForegroundWindow = [IntPtr]::Zero

try {
    $CurrentStage = "server-preflight"
    Assert-NoYuneWindowsServerProcess -Context "Notepad smoke"

    $CurrentStage = "profile-preflight"
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Notepad smoke before launch"

    $CurrentStage = "notepad-launch"
    $NotepadLaunchTime = Get-Date
    $Notepad = Start-Process -FilePath "notepad.exe" -PassThru
    $NotepadFocus = Set-YuneWindowsForegroundNotepadWindow `
        -StartedAfter $NotepadLaunchTime `
        -Shell $Shell `
        -TimeoutMs 15000
    if (-not $NotepadFocus.focused) {
        throw "failed to focus Notepad"
    }
    $NotepadForegroundProcessId = [int]$NotepadFocus.process_id
    $NotepadForegroundWindow = $NotepadFocus.window_handle
    if ($NotepadForegroundProcessId -le 0 -or $NotepadForegroundWindow -eq [IntPtr]::Zero) {
        throw "focused Notepad window did not expose a process id and window handle"
    }
    try {
        [void]$Shell.AppActivate($NotepadForegroundProcessId)
    }
    catch {
    }
    Start-Sleep -Milliseconds 300
    Assert-ForegroundWindowHandle `
        -Window $NotepadForegroundWindow `
        -Context "Notepad smoke"
    Assert-ForegroundProcess `
        -ProcessId $NotepadForegroundProcessId `
        -Context "Notepad smoke"
    $ForegroundTargetVerifiedBeforeTyping = $true
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Notepad smoke before typing"
    $ProfileActiveVerifiedBeforeTyping = $true
    $ActiveProfileVerifiedBeforeTyping = $true

    $CurrentStage = "target-reset"
    Reset-TextSmokeTargetContent -Context "Notepad smoke"

    $CurrentStage = "clipboard-reset"
    Reset-TextSmokeClipboard -Context "Notepad smoke"
    $ClipboardClearedBeforeTyping = $true
    $StructuralLogStartLineCount = Get-StructuralLogLineCount -Path $StructuralLogPath
    $StructuralLogBaselineCaptured = $true
    $CurrentStage = "server-autostart"
    Send-YuneWindowsAsciiText -Text "n" -Context "Notepad smoke server launch probe"
    $ServerReadiness = Wait-YuneWindowsProductOwnedServerReady `
        -InstallDir $InstallRoot `
        -StructuralLogPath $StructuralLogPath `
        -StartLineCount $StructuralLogStartLineCount
    $ProductOwnedServerStartObserved = [bool]$ServerReadiness.server_process_observed
    $ProductOwnedServerReadyObserved = [bool]$ServerReadiness.ready_observed
    if (-not $ProductOwnedServerReadyObserved) {
        throw "Notepad smoke product-owned server launch did not become ready; structural events: $($ServerReadiness.structural_event_summary)"
    }
    Cancel-YuneWindowsTextComposition -Context "Notepad smoke composition cancel after server launch probe"

    $CurrentStage = "target-reset-after-server-ready"
    Reset-TextSmokeTargetContent -Context "Notepad smoke after server launch probe"
    Assert-ForegroundProcess `
        -ProcessId $NotepadForegroundProcessId `
        -Context "Notepad smoke after server launch probe"
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Notepad smoke before typing after server ready"
    $ProfileActiveVerifiedBeforeTyping = $true
    $ActiveProfileVerifiedBeforeTyping = $true
    $StructuralLogStartLineCount = Get-StructuralLogLineCount -Path $StructuralLogPath

    $CurrentStage = "candidate-display"
    Send-YuneWindowsAsciiText -Text $TypedInput -Context "Notepad smoke typed input"
    Start-Sleep -Milliseconds 1000
    $ServerProcessesAfterTyping = @(Get-YuneWindowsInstalledServerProcesses -InstallDir $InstallRoot)
    $ProductOwnedServerStartObserved = $ProductOwnedServerStartObserved -or ($ServerProcessesAfterTyping.Count -gt 0)
    $CandidateScreenshot = Join-Path $EvidenceDir "candidate-display-notepad.png"
    Capture-DesktopScreenshot -Path $CandidateScreenshot
    Assert-DesktopScreenshotEvidence `
        -Path $CandidateScreenshot `
        -Context "Notepad candidate-display"
    $CandidateScreenshotCaptured = $true
    $CurrentStage = "candidate-commit"
    Assert-ForegroundProcess `
        -ProcessId $NotepadForegroundProcessId `
        -Context "Notepad smoke before commit"
    Send-YuneWindowsVirtualKey -VirtualKey 0x20 -Context "Notepad smoke commit"
    Start-Sleep -Milliseconds 1200
    $CommitScreenshot = Join-Path $EvidenceDir "notepad-commit.png"
    Capture-DesktopScreenshot -Path $CommitScreenshot
    Assert-DesktopScreenshotEvidence `
        -Path $CommitScreenshot `
        -Context "Notepad commit"
    $CommitScreenshotCaptured = $true
    Assert-DistinctDesktopScreenshots `
        -CandidatePath $CandidateScreenshot `
        -CommitPath $CommitScreenshot `
        -Context "Notepad smoke"
    $CandidateCommitScreenshotsDistinct = $true
    $CurrentStage = "clipboard-capture"
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("^c")
    Start-Sleep -Milliseconds 300
    $Observed = [System.Windows.Forms.Clipboard]::GetText()
    Reset-TextSmokeClipboard -Context "Notepad smoke after evidence capture"
    $ClipboardClearedAfterCapture = $true
    $ObservedText = $Observed.Trim()

    $Raw = $ObservedText -eq "ngohaig" -or $ObservedText -eq "ngohaig "
    $MatchesExpectedCommit = $ObservedText -eq $ExpectedCommitText
    Update-StructuralSmokeEvidence
    $Pass = $MatchesExpectedCommit -and
        $ForegroundTargetVerifiedBeforeTyping -and
        $ProfileActiveVerifiedBeforeTyping -and
        $ProductOwnedServerStartObserved -and
        $ProductOwnedServerReadyObserved -and
        $ClipboardClearedBeforeTyping -and
        $ClipboardClearedAfterCapture -and
        $CandidateScreenshotCaptured -and
        $CommitScreenshotCaptured -and
        $CandidateCommitScreenshotsDistinct -and
        $StructuralCandidateUpdateObserved -and
        $StructuralCandidateUpdateCandidateCountPositive -and
        $StructuralCommitEventObserved -and
        -not $StructuralCandidateWindowFailureObserved
    $CurrentStage = "result-check"
    if (-not $Pass) {
        $FailureScreenshot = Save-TextSmokeFailureScreenshot `
            -Path (Join-Path $EvidenceDir $FailureScreenshotName)
        Write-TextSmokeResult `
            -Status "failed" `
            -FailureStage $CurrentStage `
            -FailureMessage "Expected '$ExpectedCommitText' with structural candidate_update and commit_text events, observed '$Observed'" `
            -FailureScreenshot $FailureScreenshotName `
            -FailureScreenshotCaptured ([string]$FailureScreenshot.captured) `
            -FailureScreenshotError ([string]$FailureScreenshot.error) `
            -Observed $Observed `
            -Pass ([string]$Pass) `
            -Raw ([string]$Raw) `
            -ForegroundTargetVerifiedBeforeTyping ([string]$ForegroundTargetVerifiedBeforeTyping) `
            -ActiveProfileVerifiedBeforeTyping ([string]$ActiveProfileVerifiedBeforeTyping) `
            -ProfileActiveVerifiedBeforeTyping ([string]$ProfileActiveVerifiedBeforeTyping) `
            -ClipboardClearedBeforeTyping ([string]$ClipboardClearedBeforeTyping) `
            -ClipboardClearedAfterCapture ([string]$ClipboardClearedAfterCapture) `
            -CandidateScreenshotCaptured ([string]$CandidateScreenshotCaptured) `
            -CommitScreenshotCaptured ([string]$CommitScreenshotCaptured) `
            -CandidateCommitScreenshotsDistinct ([string]$CandidateCommitScreenshotsDistinct) `
            -MatchesExpectedCommit ([string]$MatchesExpectedCommit) `
            -StructuralCandidateUpdateObserved ([string]$StructuralCandidateUpdateObserved) `
            -StructuralCandidateUpdateCandidateCountPositive ([string]$StructuralCandidateUpdateCandidateCountPositive) `
            -StructuralCommitEventObserved ([string]$StructuralCommitEventObserved) `
            -StructuralCandidateWindowFailureObserved ([string]$StructuralCandidateWindowFailureObserved) `
            -StructuralNewLineCount ([string]($NewStructuralLogLines.Count)) `
            -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
            -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)
        throw "Notepad smoke failed; expected '$ExpectedCommitText', observed '$Observed'"
    }

    $CurrentStage = "post-state"
    Write-PostSmokeStateSnapshot

    Write-TextSmokeResult `
        -Status "passed" `
        -Observed $Observed `
        -Pass ([string]$Pass) `
        -Raw ([string]$Raw) `
        -ForegroundTargetVerifiedBeforeTyping ([string]$ForegroundTargetVerifiedBeforeTyping) `
        -ActiveProfileVerifiedBeforeTyping ([string]$ActiveProfileVerifiedBeforeTyping) `
        -ProfileActiveVerifiedBeforeTyping ([string]$ProfileActiveVerifiedBeforeTyping) `
        -ClipboardClearedBeforeTyping ([string]$ClipboardClearedBeforeTyping) `
        -ClipboardClearedAfterCapture ([string]$ClipboardClearedAfterCapture) `
        -CandidateScreenshotCaptured ([string]$CandidateScreenshotCaptured) `
        -CommitScreenshotCaptured ([string]$CommitScreenshotCaptured) `
        -CandidateCommitScreenshotsDistinct ([string]$CandidateCommitScreenshotsDistinct) `
        -MatchesExpectedCommit ([string]$MatchesExpectedCommit) `
        -StructuralCandidateUpdateObserved ([string]$StructuralCandidateUpdateObserved) `
        -StructuralCandidateUpdateCandidateCountPositive ([string]$StructuralCandidateUpdateCandidateCountPositive) `
        -StructuralCommitEventObserved ([string]$StructuralCommitEventObserved) `
        -StructuralCandidateWindowFailureObserved ([string]$StructuralCandidateWindowFailureObserved) `
        -StructuralNewLineCount ([string]($NewStructuralLogLines.Count)) `
        -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
        -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)

    Write-Host "Notepad smoke passed; observed '$Observed'"
}
catch {
    if (-not $ClipboardClearedAfterCapture) {
        try {
            Reset-TextSmokeClipboard -Context "Notepad smoke failure cleanup"
            $ClipboardClearedAfterFailure = $true
        }
        catch {
            Write-Warning "failed to clear clipboard after Notepad smoke failure: $($_.Exception.Message)"
        }
    }
    if (-not $ResultWritten) {
        Update-StructuralSmokeEvidence
        $FailureScreenshot = Save-TextSmokeFailureScreenshot `
            -Path (Join-Path $EvidenceDir $FailureScreenshotName)
        Write-TextSmokeResult `
            -Status "failed" `
            -FailureStage $CurrentStage `
            -FailureMessage $_.Exception.Message `
            -FailureScreenshot $FailureScreenshotName `
            -FailureScreenshotCaptured ([string]$FailureScreenshot.captured) `
            -FailureScreenshotError ([string]$FailureScreenshot.error) `
            -Observed $Observed `
            -Pass ([string]$Pass) `
            -Raw ([string]$Raw) `
            -ForegroundTargetVerifiedBeforeTyping ([string]$ForegroundTargetVerifiedBeforeTyping) `
            -ActiveProfileVerifiedBeforeTyping ([string]$ActiveProfileVerifiedBeforeTyping) `
            -ProfileActiveVerifiedBeforeTyping ([string]$ProfileActiveVerifiedBeforeTyping) `
            -ClipboardClearedBeforeTyping ([string]$ClipboardClearedBeforeTyping) `
            -ClipboardClearedAfterCapture ([string]$ClipboardClearedAfterCapture) `
            -ClipboardClearedAfterFailure ([string]$ClipboardClearedAfterFailure) `
            -CandidateScreenshotCaptured ([string]$CandidateScreenshotCaptured) `
            -CommitScreenshotCaptured ([string]$CommitScreenshotCaptured) `
            -CandidateCommitScreenshotsDistinct ([string]$CandidateCommitScreenshotsDistinct) `
            -MatchesExpectedCommit ([string]$MatchesExpectedCommit) `
            -StructuralCandidateUpdateObserved ([string]$StructuralCandidateUpdateObserved) `
            -StructuralCandidateUpdateCandidateCountPositive ([string]$StructuralCandidateUpdateCandidateCountPositive) `
            -StructuralCommitEventObserved ([string]$StructuralCommitEventObserved) `
            -StructuralCandidateWindowFailureObserved ([string]$StructuralCandidateWindowFailureObserved) `
            -StructuralNewLineCount ([string]($NewStructuralLogLines.Count)) `
            -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
            -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)
    }
    throw
}
finally {
    $CleanupErrors = [System.Collections.Generic.List[string]]::new()
    if (-not $PostStateSnapshotWritten) {
        try {
            Write-PostSmokeStateSnapshot
        }
        catch {
            Write-Warning "failed to write Notepad post-smoke state snapshot: $($_.Exception.Message)"
        }
    }
    if ($Notepad -and -not $Notepad.HasExited) {
        try {
            Stop-Process -Id $Notepad.Id -Force
            Wait-YuneWindowsProcessExit -ProcessId $Notepad.Id -RequireExit
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }
    if ($NotepadLaunchTime -gt [DateTime]::MinValue) {
        try {
            Stop-YuneWindowsNotepadSmokeProcesses -StartedAfter $NotepadLaunchTime
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }
    foreach ($InstalledServerProcess in @(Get-YuneWindowsInstalledServerProcesses -InstallDir $InstallRoot)) {
        try {
            Stop-Process -Id $InstalledServerProcess.Id -Force
            Wait-YuneWindowsProcessExit -ProcessId $InstalledServerProcess.Id -RequireExit
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }
    if ($CleanupErrors.Count -gt 0) {
        Update-StructuralSmokeEvidence
        $CleanupFailureMessage = "Notepad smoke cleanup failed: $($CleanupErrors -join '; ')"
        $FailureScreenshot = Save-TextSmokeFailureScreenshot `
            -Path (Join-Path $EvidenceDir $FailureScreenshotName)
        Write-TextSmokeResult `
            -Status "failed" `
            -FailureStage "cleanup" `
            -FailureMessage $CleanupFailureMessage `
            -FailureScreenshot $FailureScreenshotName `
            -FailureScreenshotCaptured ([string]$FailureScreenshot.captured) `
            -FailureScreenshotError ([string]$FailureScreenshot.error) `
            -Observed $Observed `
            -Pass ([string]$Pass) `
            -Raw ([string]$Raw) `
            -ForegroundTargetVerifiedBeforeTyping ([string]$ForegroundTargetVerifiedBeforeTyping) `
            -ActiveProfileVerifiedBeforeTyping ([string]$ActiveProfileVerifiedBeforeTyping) `
            -ProfileActiveVerifiedBeforeTyping ([string]$ProfileActiveVerifiedBeforeTyping) `
            -ClipboardClearedBeforeTyping ([string]$ClipboardClearedBeforeTyping) `
            -ClipboardClearedAfterCapture ([string]$ClipboardClearedAfterCapture) `
            -ClipboardClearedAfterFailure ([string]$ClipboardClearedAfterFailure) `
            -CandidateScreenshotCaptured ([string]$CandidateScreenshotCaptured) `
            -CommitScreenshotCaptured ([string]$CommitScreenshotCaptured) `
            -CandidateCommitScreenshotsDistinct ([string]$CandidateCommitScreenshotsDistinct) `
            -MatchesExpectedCommit ([string]$MatchesExpectedCommit) `
            -StructuralCandidateUpdateObserved ([string]$StructuralCandidateUpdateObserved) `
            -StructuralCandidateUpdateCandidateCountPositive ([string]$StructuralCandidateUpdateCandidateCountPositive) `
            -StructuralCommitEventObserved ([string]$StructuralCommitEventObserved) `
            -StructuralCandidateWindowFailureObserved ([string]$StructuralCandidateWindowFailureObserved) `
            -StructuralNewLineCount ([string]($NewStructuralLogLines.Count)) `
            -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
            -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)
        throw $CleanupFailureMessage
    }
}
