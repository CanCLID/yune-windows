param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
    [string]$EvidenceDir = "",
    [string]$BrowserPath = "",
    [switch]$ApprovedMachineStateChange,
    [string]$ApprovalNote = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

Require-ApprovedMachineStateChange `
    -Approved $ApprovedMachineStateChange.IsPresent `
    -Action "activate the IME and drive a Chromium text field"

Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote

if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    throw "Run this smoke from an STA PowerShell session so clipboard evidence can be captured."
}

function Find-ChromiumBrowser {
    param([string]$RequestedPath)
    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        throw "Requested -BrowserPath must provide a concrete Chromium browser path: an existing absolute .exe path."
    }

    Assert-ConcreteChromiumBrowserPath `
        -PathValue $RequestedPath `
        -Source "Requested -BrowserPath"
    $RequestedBrowserPath = [System.IO.Path]::GetFullPath($RequestedPath)
    if (-not (Test-Path -LiteralPath $RequestedBrowserPath -PathType Leaf)) {
        throw "Requested -BrowserPath must provide a concrete Chromium browser path: an existing absolute .exe path."
    }
    return $RequestedBrowserPath
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
$ProfileTool = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"
if (-not (Test-Path -LiteralPath $ProfileTool)) {
    throw "missing installed profile tool: $ProfileTool"
}

if ($EvidenceDir -eq "") {
    $EvidenceDir = Join-Path $RepoRoot "docs\evidence\m01\tsf-smoke"
}
New-Item -ItemType Directory -Force $EvidenceDir | Out-Null
$ResultPath = Join-Path $EvidenceDir "chromium-smoke-result.md"
$PostStatePath = Join-Path $EvidenceDir "chromium-post-state.json"
$TypedInput = "ngohaig"
$ExpectedCommitText = -join ([char[]](0x6211, 0x4fc2, 0x500b))
$StructuralLogPath = Join-Path $InstallRoot "logs\tsf-events.log"
$StructuralLogStartLineCount = 0
$StructuralLogBaselineCaptured = $false
$CurrentStage = "pre-state"
$ResultWritten = $false
$PostStateSnapshotWritten = $false
$Browser = ""
$ClipboardClearedBeforeTyping = $false
$ClipboardClearedAfterCapture = $false
$ClipboardClearedAfterFailure = $false
$ForegroundTargetVerifiedBeforeTyping = $false
$TextFieldClickVerifiedBeforeTyping = $false
$TextareaFocusVerifiedBeforeTyping = $false
$ActiveProfileVerifiedBeforeTyping = $false
$ProfileActiveVerifiedBeforeTyping = $false
$ProductOwnedServerStartObserved = $false
$ProductOwnedServerReadyObserved = $false
$CandidateScreenshotCaptured = $false
$CommitScreenshotCaptured = $false
$CandidateCommitScreenshotsDistinct = $false
$FailureScreenshotName = "failure-chromium.png"
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
$ChromiumEventTitleAfterTyping = ""
$ChromiumEventTitleAfterCommit = ""
$ChromiumEventSummaryAfterTyping = ""
$ChromiumEventSummaryAfterCommit = ""

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
        [string]$TextFieldClickVerifiedBeforeTyping = "False",
        [string]$TextareaFocusVerifiedBeforeTyping = "False",
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
        [string]$ChromiumEventTitleAfterTyping = "",
        [string]$ChromiumEventTitleAfterCommit = "",
        [string]$ChromiumEventSummaryAfterTyping = "",
        [string]$ChromiumEventSummaryAfterCommit = "",
        [string]$ProductOwnedServerStartObserved = "False",
        [string]$ProductOwnedServerReadyObserved = "False"
    )

    $Lines = @(
        "# Chromium Text Field Smoke Result",
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
        "Browser: $Browser",
        "",
        "Input: ``$TypedInput`` followed by space.",
        "",
        "Input method: Win32 virtual-key typed test input.",
        "",
        'Candidate-display screenshot: `candidate-display-chromium.png`.',
        "",
        "Candidate-display screenshot captured: $CandidateScreenshotCaptured",
        "",
        'Commit screenshot: `chromium-commit.png`.',
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
        "Chromium text-field click verified before typing: $TextFieldClickVerifiedBeforeTyping",
        "",
        "Chromium textarea focus verified before typing: $TextareaFocusVerifiedBeforeTyping",
        "",
        "Chromium event title after typing: $ChromiumEventTitleAfterTyping",
        "",
        "Chromium event title after commit: $ChromiumEventTitleAfterCommit",
        "",
        "Chromium event summary after typing: $ChromiumEventSummaryAfterTyping",
        "",
        "Chromium event summary after commit: $ChromiumEventSummaryAfterCommit",
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
        -Context "Chromium smoke post-state"
    $script:PostStateSnapshotWritten = $true
}

Write-YuneWindowsStateSnapshot `
    -Path (Join-Path $EvidenceDir "chromium-pre-state.json") `
    -InstallDir $InstallRoot

Add-Type -AssemblyName System.Windows.Forms
$Shell = New-Object -ComObject WScript.Shell
$BrowserProcess = $null
$BrowserForegroundProcessId = 0
$BrowserForegroundWindow = [IntPtr]::Zero
$TempRoot = Join-Path $env:TEMP "yune-windows\chromium-smoke"
$ProfileRoot = Join-Path $TempRoot "profile"
$HtmlPath = Join-Path $TempRoot "yune_windows-chromium-smoke.html"

New-Item -ItemType Directory -Force $TempRoot | Out-Null
if (Test-Path -LiteralPath $ProfileRoot) {
    Remove-Item -LiteralPath $ProfileRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $ProfileRoot | Out-Null

@"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>YuneWindows Chromium Smoke - Waiting</title>
  <style>
    html, body { width: 100%; height: 100%; margin: 0; }
    body { font: 18px Segoe UI, sans-serif; }
    textarea {
      position: fixed;
      left: 48px;
      top: 120px;
      width: 720px;
      height: 180px;
      font: 22px Segoe UI, sans-serif;
    }
  </style>
  <script>
    const smokeEventState = {
      keydown: 0,
      beforeinput: 0,
      input: 0,
      compositionstart: 0,
      compositionupdate: 0,
      compositionend: 0
    };
    function recordSmokeEvent(name) {
      if (Object.prototype.hasOwnProperty.call(smokeEventState, name)) {
        smokeEventState[name] += 1;
      }
      markSmokeFocusState();
    }
    function focusSmokeInput() {
      const input = document.getElementById('yune_windows-chromium-smoke-input');
      if (input) {
        input.focus();
      }
      markSmokeFocusState();
    }
    function markSmokeFocusState() {
      const input = document.getElementById('yune_windows-chromium-smoke-input');
      const focused = input && document.activeElement === input;
      const valueLength = input ? input.value.length : 0;
      const diagnostics = 'keydown=' + smokeEventState.keydown
        + ' beforeinput=' + smokeEventState.beforeinput
        + ' input=' + smokeEventState.input
        + ' compositionstart=' + smokeEventState.compositionstart
        + ' compositionupdate=' + smokeEventState.compositionupdate
        + ' compositionend=' + smokeEventState.compositionend
        + ' value_len=' + valueLength;
      document.title = focused
        ? 'YuneWindows Chromium Smoke - Textarea Focused - ' + diagnostics
        : 'YuneWindows Chromium Smoke - Waiting - ' + diagnostics;
    }
    function installSmokeEventDiagnostics() {
      const input = document.getElementById('yune_windows-chromium-smoke-input');
      if (!input) {
        return;
      }
      input.addEventListener('keydown', () => recordSmokeEvent('keydown'));
      input.addEventListener('beforeinput', () => recordSmokeEvent('beforeinput'));
      input.addEventListener('input', () => recordSmokeEvent('input'));
      input.addEventListener('compositionstart', () => recordSmokeEvent('compositionstart'));
      input.addEventListener('compositionupdate', () => recordSmokeEvent('compositionupdate'));
      input.addEventListener('compositionend', () => recordSmokeEvent('compositionend'));
    }
    document.addEventListener('DOMContentLoaded', () => {
      installSmokeEventDiagnostics();
      focusSmokeInput();
    });
    window.addEventListener('focus', () => setTimeout(focusSmokeInput, 50));
    document.addEventListener('visibilitychange', () => setTimeout(focusSmokeInput, 50));
    document.addEventListener('selectionchange', markSmokeFocusState);
    setTimeout(focusSmokeInput, 250);
    setInterval(focusSmokeInput, 250);
  </script>
</head>
<body>
  <textarea id="yune_windows-chromium-smoke-input" autofocus aria-label="YuneWindows Chromium smoke" onfocus="markSmokeFocusState()" onblur="markSmokeFocusState()"></textarea>
</body>
</html>
"@ | Out-File -LiteralPath $HtmlPath -Encoding utf8

try {
    $CurrentStage = "browser-discovery"
    $Browser = Find-ChromiumBrowser -RequestedPath $BrowserPath

    $CurrentStage = "server-preflight"
    Assert-NoYuneWindowsServerProcess -Context "Chromium smoke"

    $CurrentStage = "profile-preflight"
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Chromium smoke before launch"

    $CurrentStage = "browser-launch"
    $Uri = (New-Object System.Uri($HtmlPath)).AbsoluteUri
    $BrowserProcess = Start-Process -FilePath $Browser -ArgumentList @(
        "--user-data-dir=$ProfileRoot",
        "--no-first-run",
        "--no-default-browser-check",
        "--do-not-de-elevate",
        "--disable-sync",
        "--disable-background-networking",
        "--disable-features=msEdgeOnRampFRE,msEdgeSignIn,msImplicitSignin,msEdgeSync",
        "--app=$Uri"
    ) -PassThru
    $BrowserFocus = Set-YuneWindowsForegroundChromiumWindow `
        -Process $BrowserProcess `
        -ProfileRoot $ProfileRoot `
        -Shell $Shell `
        -TimeoutMs 15000
    if (-not $BrowserFocus.focused) {
        throw "failed to focus Chromium browser"
    }
    $BrowserForegroundProcessId = [int]$BrowserFocus.process_id
    $BrowserForegroundWindow = $BrowserFocus.window_handle
    if ($BrowserForegroundProcessId -le 0 -or $BrowserForegroundWindow -eq [IntPtr]::Zero) {
        throw "focused Chromium window did not expose a process id and window handle"
    }
    try {
        [void]$Shell.AppActivate($BrowserForegroundProcessId)
    }
    catch {
    }
    Start-Sleep -Milliseconds 500
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke"
    Assert-ForegroundProcess `
        -ProcessId $BrowserForegroundProcessId `
        -Context "Chromium smoke"
    $ForegroundTargetVerifiedBeforeTyping = $true
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Chromium smoke after focus"
    $ProfileActiveVerifiedBeforeTyping = $true
    $ActiveProfileVerifiedBeforeTyping = $true

    $CurrentStage = "browser-modal-dismiss"
    Send-YuneWindowsVirtualKey -VirtualKey 0x0d -Context "Chromium smoke browser modal dismissal"
    Start-Sleep -Milliseconds 800

    $CurrentStage = "browser-text-field-click"
    [void](Set-YuneWindowsForegroundWindowHandle `
            -Window $BrowserForegroundWindow `
            -Shell $Shell `
            -TimeoutMs 3000)
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke before text-field click"
    Invoke-YuneWindowsClientClick `
        -Window $BrowserForegroundWindow `
        -ClientX 160 `
        -ClientY 220 `
        -Context "Chromium smoke text-field click"
    [void](Wait-YuneWindowsWindowTitle `
            -Window $BrowserForegroundWindow `
            -Pattern "Textarea Focused" `
            -Context "Chromium smoke text-field focus" `
            -TimeoutMs 5000)
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke after text-field click"

    $CurrentStage = "target-reset"
    Reset-TextSmokeTargetContent -Context "Chromium smoke"

    $CurrentStage = "clipboard-reset"
    Reset-TextSmokeClipboard -Context "Chromium smoke"
    $ClipboardClearedBeforeTyping = $true
    $StructuralLogStartLineCount = Get-StructuralLogLineCount -Path $StructuralLogPath
    $StructuralLogBaselineCaptured = $true
    $CurrentStage = "candidate-display"
    [void](Set-YuneWindowsForegroundWindowHandle `
            -Window $BrowserForegroundWindow `
            -Shell $Shell `
            -TimeoutMs 3000)
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke before typing"
    Assert-ForegroundProcess `
        -ProcessId $BrowserForegroundProcessId `
        -Context "Chromium smoke before typing"
    Invoke-YuneWindowsClientClick `
        -Window $BrowserForegroundWindow `
        -ClientX 160 `
        -ClientY 220 `
        -Context "Chromium smoke text-field pre-type click"
    [void](Wait-YuneWindowsWindowTitle `
            -Window $BrowserForegroundWindow `
            -Pattern "Textarea Focused" `
            -Context "Chromium smoke text-field focus before typing" `
            -TimeoutMs 5000)
    $TextFieldClickVerifiedBeforeTyping = $true
    $TextareaFocusVerifiedBeforeTyping = $true
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke after pre-type click"
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Chromium smoke after pre-type click"
    $ProfileActiveVerifiedBeforeTyping = $true
    $ActiveProfileVerifiedBeforeTyping = $true

    $CurrentStage = "server-autostart"
    Send-YuneWindowsAsciiText -Text "n" -Context "Chromium smoke server launch probe"
    $ServerReadiness = Wait-YuneWindowsProductOwnedServerReady `
        -InstallDir $InstallRoot `
        -StructuralLogPath $StructuralLogPath `
        -StartLineCount $StructuralLogStartLineCount
    $ProductOwnedServerStartObserved = [bool]$ServerReadiness.server_process_observed
    $ProductOwnedServerReadyObserved = [bool]$ServerReadiness.ready_observed
    if (-not $ProductOwnedServerReadyObserved) {
        throw "Chromium smoke product-owned server launch did not become ready; structural events: $($ServerReadiness.structural_event_summary)"
    }
    Cancel-YuneWindowsTextComposition -Context "Chromium smoke composition cancel after server launch probe"

    $CurrentStage = "target-reset-after-server-ready"
    Reset-TextSmokeTargetContent -Context "Chromium smoke after server launch probe"
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke after server launch probe"
    Invoke-YuneWindowsClientClick `
        -Window $BrowserForegroundWindow `
        -ClientX 160 `
        -ClientY 220 `
        -Context "Chromium smoke text-field click after server launch probe"
    [void](Wait-YuneWindowsWindowTitle `
            -Window $BrowserForegroundWindow `
            -Pattern "Textarea Focused" `
            -Context "Chromium smoke text-field focus after server launch probe" `
            -TimeoutMs 5000)
    Assert-YuneWindowsProfileActive `
        -ProfileToolPath $ProfileTool `
        -Context "Chromium smoke before typing after server ready"
    $ProfileActiveVerifiedBeforeTyping = $true
    $ActiveProfileVerifiedBeforeTyping = $true
    $StructuralLogStartLineCount = Get-StructuralLogLineCount -Path $StructuralLogPath

    $CurrentStage = "candidate-display"
    Send-YuneWindowsAsciiText -Text $TypedInput -Context "Chromium smoke typed input"
    Start-Sleep -Milliseconds 1000
    $ServerProcessesAfterTyping = @(Get-YuneWindowsInstalledServerProcesses -InstallDir $InstallRoot)
    $ProductOwnedServerStartObserved = $ProductOwnedServerStartObserved -or ($ServerProcessesAfterTyping.Count -gt 0)
    $ChromiumEventTitleAfterTyping = Get-YuneWindowsWindowTitle -Window $BrowserForegroundWindow
    $ChromiumEventSummaryAfterTyping =
        Get-YuneWindowsChromiumSmokeEventSummary -Title $ChromiumEventTitleAfterTyping
    $CandidateScreenshot = Join-Path $EvidenceDir "candidate-display-chromium.png"
    Capture-DesktopScreenshot -Path $CandidateScreenshot
    Assert-DesktopScreenshotEvidence `
        -Path $CandidateScreenshot `
        -Context "Chromium candidate-display"
    $CandidateScreenshotCaptured = $true
    $CurrentStage = "candidate-commit"
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium smoke before commit"
    Assert-ForegroundProcess `
        -ProcessId $BrowserForegroundProcessId `
        -Context "Chromium smoke before commit"
    Send-YuneWindowsVirtualKey -VirtualKey 0x20 -Context "Chromium smoke commit"
    Start-Sleep -Milliseconds 1200
    $ChromiumEventTitleAfterCommit = Get-YuneWindowsWindowTitle -Window $BrowserForegroundWindow
    $ChromiumEventSummaryAfterCommit =
        Get-YuneWindowsChromiumSmokeEventSummary -Title $ChromiumEventTitleAfterCommit
    $CommitScreenshot = Join-Path $EvidenceDir "chromium-commit.png"
    Capture-DesktopScreenshot -Path $CommitScreenshot
    Assert-DesktopScreenshotEvidence `
        -Path $CommitScreenshot `
        -Context "Chromium commit"
    $CommitScreenshotCaptured = $true
    Assert-DistinctDesktopScreenshots `
        -CandidatePath $CandidateScreenshot `
        -CommitPath $CommitScreenshot `
        -Context "Chromium smoke"
    $CandidateCommitScreenshotsDistinct = $true
    $CurrentStage = "clipboard-capture"
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("^c")
    Start-Sleep -Milliseconds 300
    $Observed = [System.Windows.Forms.Clipboard]::GetText()
    Reset-TextSmokeClipboard -Context "Chromium smoke after evidence capture"
    $ClipboardClearedAfterCapture = $true
    $ObservedText = $Observed.Trim()

    $Raw = $ObservedText -eq "ngohaig" -or $ObservedText -eq "ngohaig "
    $MatchesExpectedCommit = $ObservedText -eq $ExpectedCommitText
    Update-StructuralSmokeEvidence
    $Pass = $MatchesExpectedCommit -and
        $ForegroundTargetVerifiedBeforeTyping -and
        $TextFieldClickVerifiedBeforeTyping -and
        $TextareaFocusVerifiedBeforeTyping -and
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
            -TextFieldClickVerifiedBeforeTyping ([string]$TextFieldClickVerifiedBeforeTyping) `
            -TextareaFocusVerifiedBeforeTyping ([string]$TextareaFocusVerifiedBeforeTyping) `
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
            -ChromiumEventTitleAfterTyping $ChromiumEventTitleAfterTyping `
            -ChromiumEventTitleAfterCommit $ChromiumEventTitleAfterCommit `
            -ChromiumEventSummaryAfterTyping $ChromiumEventSummaryAfterTyping `
            -ChromiumEventSummaryAfterCommit $ChromiumEventSummaryAfterCommit `
            -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
            -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)
        throw "Chromium smoke failed; expected '$ExpectedCommitText', observed '$Observed'"
    }

    $CurrentStage = "post-state"
    Write-PostSmokeStateSnapshot

    Write-TextSmokeResult `
        -Status "passed" `
        -Observed $Observed `
        -Pass ([string]$Pass) `
        -Raw ([string]$Raw) `
        -ForegroundTargetVerifiedBeforeTyping ([string]$ForegroundTargetVerifiedBeforeTyping) `
        -TextFieldClickVerifiedBeforeTyping ([string]$TextFieldClickVerifiedBeforeTyping) `
        -TextareaFocusVerifiedBeforeTyping ([string]$TextareaFocusVerifiedBeforeTyping) `
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
        -ChromiumEventTitleAfterTyping $ChromiumEventTitleAfterTyping `
        -ChromiumEventTitleAfterCommit $ChromiumEventTitleAfterCommit `
        -ChromiumEventSummaryAfterTyping $ChromiumEventSummaryAfterTyping `
        -ChromiumEventSummaryAfterCommit $ChromiumEventSummaryAfterCommit `
        -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
        -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)

    Write-Host "Chromium smoke passed; observed '$Observed'"
}
catch {
    if (-not $ClipboardClearedAfterCapture) {
        try {
            Reset-TextSmokeClipboard -Context "Chromium smoke failure cleanup"
            $ClipboardClearedAfterFailure = $true
        }
        catch {
            Write-Warning "failed to clear clipboard after Chromium smoke failure: $($_.Exception.Message)"
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
            -TextFieldClickVerifiedBeforeTyping ([string]$TextFieldClickVerifiedBeforeTyping) `
            -TextareaFocusVerifiedBeforeTyping ([string]$TextareaFocusVerifiedBeforeTyping) `
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
            -ChromiumEventTitleAfterTyping $ChromiumEventTitleAfterTyping `
            -ChromiumEventTitleAfterCommit $ChromiumEventTitleAfterCommit `
            -ChromiumEventSummaryAfterTyping $ChromiumEventSummaryAfterTyping `
            -ChromiumEventSummaryAfterCommit $ChromiumEventSummaryAfterCommit `
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
            Write-Warning "failed to write Chromium post-smoke state snapshot: $($_.Exception.Message)"
        }
    }
    if ($BrowserProcess) {
        try {
            Stop-ProcessTree -ProcessId $BrowserProcess.Id
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }
    try {
        Stop-ProcessesUsingPathInCommandLine -Path $ProfileRoot
    }
    catch {
        $CleanupErrors.Add($_.Exception.Message)
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
    if (Test-Path -LiteralPath $ProfileRoot) {
        try {
            Remove-YuneWindowsPathWithRetry -Path $ProfileRoot -Context "Chromium smoke profile cleanup"
        }
        catch {
            $CleanupErrors.Add("failed to remove Chromium smoke profile directory: $($_.Exception.Message)")
        }
    }
    if ($CleanupErrors.Count -gt 0) {
        Update-StructuralSmokeEvidence
        $CleanupFailureMessage = "Chromium smoke cleanup failed: $($CleanupErrors -join '; ')"
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
            -TextFieldClickVerifiedBeforeTyping ([string]$TextFieldClickVerifiedBeforeTyping) `
            -TextareaFocusVerifiedBeforeTyping ([string]$TextareaFocusVerifiedBeforeTyping) `
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
            -ChromiumEventTitleAfterTyping $ChromiumEventTitleAfterTyping `
            -ChromiumEventTitleAfterCommit $ChromiumEventTitleAfterCommit `
            -ChromiumEventSummaryAfterTyping $ChromiumEventSummaryAfterTyping `
            -ChromiumEventSummaryAfterCommit $ChromiumEventSummaryAfterCommit `
            -ProductOwnedServerStartObserved ([string]$ProductOwnedServerStartObserved) `
            -ProductOwnedServerReadyObserved ([string]$ProductOwnedServerReadyObserved)
        throw $CleanupFailureMessage
    }
}
