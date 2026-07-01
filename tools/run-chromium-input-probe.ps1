param(
    [string]$BrowserPath = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "live-smoke-support.ps1")

if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    throw "Run this Chromium input probe from an STA PowerShell session so clipboard evidence can be captured."
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputPath -eq "") {
    $OutputPath = Join-Path $RepoRoot "docs\evidence\m01\tsf-smoke\chromium-input-probe.json"
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null

$TypedInput = "ngohaig"
$Browser = ""
$Observed = ""
$Status = "failed"
$FailureStage = ""
$FailureMessage = ""
$EventTitleAfterTyping = ""
$EventSummaryAfterTyping = ""
$EventTitleAfterCapture = ""
$EventSummaryAfterCapture = ""
$ClipboardClearedBeforeTyping = $false
$ClipboardClearedAfterCapture = $false
$TextFieldClickVerifiedBeforeTyping = $false
$TextareaFocusVerifiedBeforeTyping = $false
$ForegroundTargetVerifiedBeforeTyping = $false
$ScreenshotPath = ""
$ScreenshotCaptured = $false
$BrowserProcess = $null
$BrowserForegroundWindow = [IntPtr]::Zero
$BrowserForegroundProcessId = 0
$TempRoot = Join-Path $env:TEMP "yune-windows\chromium-input-probe"
$ProfileRoot = Join-Path $TempRoot "profile"
$HtmlPath = Join-Path $TempRoot "yune_windows-chromium-input-probe.html"

function Write-ChromiumInputProbeResult {
    $Result = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        status = $Status
        failure_stage = $FailureStage
        failure_message = $FailureMessage
        machine_state_changed = $false
        product_closeout_evidence = $false
        browser_path = $Browser
        typed_input = $TypedInput
        observed_text = $Observed
        matches_typed_input = ($Observed -eq $TypedInput)
        foreground_target_verified_before_typing = $ForegroundTargetVerifiedBeforeTyping
        text_field_click_verified_before_typing = $TextFieldClickVerifiedBeforeTyping
        textarea_focus_verified_before_typing = $TextareaFocusVerifiedBeforeTyping
        clipboard_cleared_before_typing = $ClipboardClearedBeforeTyping
        clipboard_cleared_after_capture = $ClipboardClearedAfterCapture
        event_title_after_typing = $EventTitleAfterTyping
        event_summary_after_typing = $EventSummaryAfterTyping
        event_title_after_capture = $EventTitleAfterCapture
        event_summary_after_capture = $EventSummaryAfterCapture
        screenshot_path = $ScreenshotPath
        screenshot_captured = $ScreenshotCaptured
    }
    $Result | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $OutputPath -Encoding utf8
}

function Test-PositiveChromiumInputEventSummary {
    param(
        [string]$Title,
        [int]$ExpectedValueLength
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }
    $InputMatch = [regex]::Match($Title, "(^|\s)input=(?<count>\d+)(?=\s|$)")
    $ValueLengthMatch = [regex]::Match($Title, "(^|\s)value_len=(?<count>\d+)(?=\s|$)")
    if (-not $InputMatch.Success -or -not $ValueLengthMatch.Success) {
        return $false
    }
    return ([int]$InputMatch.Groups["count"].Value -gt 0) -and
        ([int]$ValueLengthMatch.Groups["count"].Value -eq $ExpectedValueLength)
}

try {
    $FailureStage = "browser-discovery"
    $Browser = Find-ChromiumBrowserPath -RequestedPath $BrowserPath
    Assert-ConcreteChromiumBrowserPath -PathValue $Browser -Source "Chromium input probe browser path"

    $FailureStage = "probe-page"
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
      const input = document.getElementById('yune_windows-chromium-input-probe');
      if (input) {
        input.focus();
      }
      markSmokeFocusState();
    }
    function markSmokeFocusState() {
      const input = document.getElementById('yune_windows-chromium-input-probe');
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
      const input = document.getElementById('yune_windows-chromium-input-probe');
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
  <textarea id="yune_windows-chromium-input-probe" autofocus aria-label="YuneWindows Chromium input probe" onfocus="markSmokeFocusState()" onblur="markSmokeFocusState()"></textarea>
</body>
</html>
"@ | Out-File -LiteralPath $HtmlPath -Encoding utf8

    $FailureStage = "browser-launch"
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

    $FailureStage = "browser-focus"
    $Shell = New-Object -ComObject WScript.Shell
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
    Assert-ForegroundWindowHandle `
        -Window $BrowserForegroundWindow `
        -Context "Chromium input probe"
    Assert-ForegroundProcess `
        -ProcessId $BrowserForegroundProcessId `
        -Context "Chromium input probe"
    $ForegroundTargetVerifiedBeforeTyping = $true

    $FailureStage = "text-field-focus"
    Invoke-YuneWindowsClientClick `
        -Window $BrowserForegroundWindow `
        -ClientX 160 `
        -ClientY 220 `
        -Context "Chromium input probe text-field click"
    [void](Wait-YuneWindowsWindowTitle `
            -Window $BrowserForegroundWindow `
            -Pattern "Textarea Focused" `
            -Context "Chromium input probe text-field focus" `
            -TimeoutMs 5000)
    $TextFieldClickVerifiedBeforeTyping = $true
    $TextareaFocusVerifiedBeforeTyping = $true

    $FailureStage = "target-reset"
    Reset-TextSmokeTargetContent -Context "Chromium input probe"

    $FailureStage = "clipboard-reset"
    Reset-TextSmokeClipboard -Context "Chromium input probe"
    $ClipboardClearedBeforeTyping = $true

    $FailureStage = "typed-input"
    Invoke-YuneWindowsClientClick `
        -Window $BrowserForegroundWindow `
        -ClientX 160 `
        -ClientY 220 `
        -Context "Chromium input probe pre-type click"
    [void](Wait-YuneWindowsWindowTitle `
            -Window $BrowserForegroundWindow `
            -Pattern "Textarea Focused" `
            -Context "Chromium input probe focus before typing" `
            -TimeoutMs 5000)
    Send-YuneWindowsAsciiText -Text $TypedInput -Context "Chromium input probe typed input"
    Start-Sleep -Milliseconds 700
    $EventTitleAfterTyping = Get-YuneWindowsWindowTitle -Window $BrowserForegroundWindow
    $EventSummaryAfterTyping = Get-YuneWindowsChromiumSmokeEventSummary -Title $EventTitleAfterTyping
    if (-not (Test-PositiveChromiumInputEventSummary `
                -Title $EventTitleAfterTyping `
                -ExpectedValueLength $TypedInput.Length)) {
        throw "Chromium input probe did not observe positive input events and expected value length after typing: $EventTitleAfterTyping"
    }

    $FailureStage = "screenshot"
    $ScreenshotPath = Join-Path (Split-Path -Parent $OutputPath) "chromium-input-probe.png"
    Capture-DesktopScreenshot -Path $ScreenshotPath
    Assert-DesktopScreenshotEvidence -Path $ScreenshotPath -Context "Chromium input probe"
    $ScreenshotCaptured = $true

    $FailureStage = "clipboard-capture"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("^c")
    Start-Sleep -Milliseconds 300
    $Observed = [System.Windows.Forms.Clipboard]::GetText()
    $EventTitleAfterCapture = Get-YuneWindowsWindowTitle -Window $BrowserForegroundWindow
    $EventSummaryAfterCapture = Get-YuneWindowsChromiumSmokeEventSummary -Title $EventTitleAfterCapture
    Reset-TextSmokeClipboard -Context "Chromium input probe after evidence capture"
    $ClipboardClearedAfterCapture = $true
    if ($Observed -ne $TypedInput) {
        throw "Chromium input probe expected '$TypedInput', observed '$Observed'"
    }

    $Status = "passed"
    $FailureStage = ""
    $FailureMessage = ""
    Write-ChromiumInputProbeResult
    Write-Host "Chromium input probe passed: $OutputPath"
}
catch {
    $Status = "failed"
    $FailureMessage = $_.Exception.Message
    try {
        Write-ChromiumInputProbeResult
    }
    catch {
    }
    throw
}
finally {
    $CleanupErrors = [System.Collections.Generic.List[string]]::new()
    if ($BrowserProcess -and -not $BrowserProcess.HasExited) {
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
    if (Test-Path -LiteralPath $ProfileRoot) {
        try {
            Remove-YuneWindowsPathWithRetry -Path $ProfileRoot -Context "Chromium input probe profile cleanup"
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }
    if ($CleanupErrors.Count -gt 0) {
        Write-Warning "Chromium input probe cleanup issue: $($CleanupErrors -join '; ')"
    }
}
