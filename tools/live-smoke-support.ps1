$ErrorActionPreference = "Stop"

function Require-ApprovedMachineStateChange {
    param(
        [bool]$Approved,
        [string]$Action
    )
    if (-not $Approved) {
        throw "Refusing to $Action without explicit approval. Rerun with -ApprovedMachineStateChange only after approval in the current session."
    }
}

function Require-ApprovedLiveSmokeContext {
    if (-not (Test-IsAdministrator)) {
        throw "Run this live smoke from an elevated STA PowerShell session after approval."
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
        throw "Run this live smoke from an elevated STA PowerShell session after approval."
    }
}

function Require-ApprovedMachineCleanupContext {
    if (-not (Test-IsAdministrator)) {
        throw "Run approved YuneWindows machine cleanup from an elevated STA PowerShell session after approval."
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
        throw "Run approved YuneWindows machine cleanup from an elevated STA PowerShell session after approval."
    }
}

function Test-IsPlaceholderApprovalNote {
    param([string]$ApprovalNote)

    if ([string]::IsNullOrWhiteSpace($ApprovalNote)) {
        return $false
    }

    return $ApprovalNote.Trim() -match '^<current-session(?:\s+cleanup)?\s+approval note>$'
}

function Require-LiveSmokeApprovalNote {
    param([string]$ApprovalNote)

    if ([string]::IsNullOrWhiteSpace($ApprovalNote)) {
        throw "Approved live smoke requires -ApprovalNote describing the explicit user approval in this session."
    }
    if (Test-IsPlaceholderApprovalNote -ApprovalNote $ApprovalNote) {
        throw "Approved live smoke requires -ApprovalNote describing the explicit user approval in this session; replace the approval-note placeholder from the approval brief."
    }
}

function Test-StructuralEventLine {
    param(
        [AllowEmptyString()][string]$Line,
        [Parameter(Mandatory = $true)]
        [string]$EventName
    )

    $EscapedEvent = [regex]::Escape($EventName)
    return $Line -match "(^|\s)event=$EscapedEvent(?=\s|$)"
}

function Test-StructuralCandidateUpdateLine {
    param([AllowEmptyString()][string]$Line)

    if (-not (Test-StructuralEventLine -Line $Line -EventName "candidate_update")) {
        return $false
    }

    $Match = [regex]::Match($Line, "(^|\s)candidate_count=(?<count>\d+)(?=\s|$)")
    if (-not $Match.Success) {
        return $false
    }

    return [int]$Match.Groups["count"].Value -gt 0
}

function Get-StructuralEventSummary {
    param([string[]]$Lines)

    $Counts = @{}
    foreach ($Line in @($Lines)) {
        $Match = [regex]::Match([string]$Line, "(^|\s)event=(?<event>[A-Za-z0-9_:-]+)(?=\s|$)")
        if (-not $Match.Success) {
            continue
        }

        $EventName = $Match.Groups["event"].Value
        if (-not $Counts.ContainsKey($EventName)) {
            $Counts[$EventName] = 0
        }
        $Counts[$EventName] += 1
    }

    if ($Counts.Count -eq 0) {
        return "none"
    }

    return (($Counts.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ", ")
}

function Get-YuneWindowsStructuralLogLinesAfter {
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

function Wait-YuneWindowsProductOwnedServerReady {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$StructuralLogPath,
        [int]$StartLineCount = 0,
        [int]$TimeoutMs = 20000,
        [int]$DelayMilliseconds = 250
    )

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $ServerProcesses = @()
    $ServerProcessObserved = $false
    $ReadyObserved = $false
    $ReadyEvent = ""
    $NewLines = @()

    do {
        $ServerProcesses = @(Get-YuneWindowsInstalledServerProcesses -InstallDir $InstallDir)
        if ($ServerProcesses.Count -gt 0) {
            $ServerProcessObserved = $true
        }

        $NewLines = @(Get-YuneWindowsStructuralLogLinesAfter `
                -Path $StructuralLogPath `
                -StartLineCount $StartLineCount)
        foreach ($EventName in @("server_launch_ready", "candidate_update")) {
            if ($NewLines | Where-Object { Test-StructuralEventLine -Line $_ -EventName $EventName } | Select-Object -First 1) {
                $ReadyObserved = $true
                $ReadyEvent = $EventName
                break
            }
        }

        if ($ReadyObserved) {
            break
        }

        Start-Sleep -Milliseconds $DelayMilliseconds
    } while ($Stopwatch.ElapsedMilliseconds -lt $TimeoutMs)

    return [pscustomobject]@{
        server_process_observed = $ServerProcessObserved
        server_process_count = @($ServerProcesses).Count
        ready_observed = $ReadyObserved
        ready_event = $ReadyEvent
        structural_event_summary = Get-StructuralEventSummary -Lines $NewLines
        structural_new_line_count = @($NewLines).Count
    }
}

function Get-YuneWindowsChromiumSmokeEventSummary {
    param([AllowEmptyString()][string]$Title)

    $Names = @(
        "keydown",
        "beforeinput",
        "input",
        "compositionstart",
        "compositionupdate",
        "compositionend",
        "value_len"
    )
    $Focused = ([string]$Title) -match "Textarea Focused"
    $Parts = [System.Collections.Generic.List[string]]::new()
    $Parts.Add("focused=$($Focused.ToString().ToLowerInvariant())") | Out-Null

    foreach ($Name in $Names) {
        $Match = [regex]::Match([string]$Title, "(^|\s)$([regex]::Escape($Name))=(?<value>\d+)(?=\s|$)")
        $Value = "unknown"
        if ($Match.Success) {
            $Value = $Match.Groups["value"].Value
        }
        $Parts.Add("$Name=$Value") | Out-Null
    }

    return ($Parts -join ", ")
}

function Format-YuneWindowsProcessArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument) {
        return '""'
    }
    if ($Argument -ne "" -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $Builder = [System.Text.StringBuilder]::new()
    [void]$Builder.Append('"')
    $Backslashes = 0
    foreach ($Character in $Argument.ToCharArray()) {
        if ($Character -eq [char]92) {
            $Backslashes += 1
            continue
        }
        if ($Character -eq [char]34) {
            if ($Backslashes -gt 0) {
                [void]$Builder.Append('\' * ($Backslashes * 2))
                $Backslashes = 0
            }
            [void]$Builder.Append('\"')
            continue
        }
        if ($Backslashes -gt 0) {
            [void]$Builder.Append('\' * $Backslashes)
            $Backslashes = 0
        }
        [void]$Builder.Append($Character)
    }
    if ($Backslashes -gt 0) {
        [void]$Builder.Append('\' * ($Backslashes * 2))
    }
    [void]$Builder.Append('"')
    return $Builder.ToString()
}

function Join-YuneWindowsProcessArguments {
    param([string[]]$ArgumentList = @())

    return (@($ArgumentList) | ForEach-Object {
            Format-YuneWindowsProcessArgument -Argument $_
        }) -join " "
}

function Invoke-YuneWindowsBoundedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 30,
        [string]$Operation = "external process"
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "$Operation executable not found: $FilePath"
    }

    $ProcessStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $ProcessStartInfo.FileName = $FilePath
    $ProcessStartInfo.Arguments = Join-YuneWindowsProcessArguments -ArgumentList $ArgumentList
    $ProcessStartInfo.UseShellExecute = $false
    $ProcessStartInfo.RedirectStandardOutput = $true
    $ProcessStartInfo.RedirectStandardError = $true
    $ProcessStartInfo.CreateNoWindow = $true

    $Process = [System.Diagnostics.Process]::new()

    try {
        $Process.StartInfo = $ProcessStartInfo
        if (-not $Process.Start()) {
            throw "$Operation failed to start: $FilePath"
        }
        $StdoutTask = $Process.StandardOutput.ReadToEndAsync()
        $StderrTask = $Process.StandardError.ReadToEndAsync()

        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $Process.Kill()
            }
            catch {
            }
            try {
                [void]$Process.WaitForExit(5000)
            }
            catch {
            }
            throw "$Operation timed out after $TimeoutSeconds seconds: $FilePath"
        }
        [void]$Process.WaitForExit()

        return [ordered]@{
            exit_code = $Process.ExitCode
            stdout = $StdoutTask.GetAwaiter().GetResult()
            stderr = $StderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $Process.Dispose()
    }
}

function Invoke-YuneWindowsProfileTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileToolPath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30,
        [string]$Operation = "profile tool"
    )

    $Result = Invoke-YuneWindowsBoundedProcess `
        -FilePath $ProfileToolPath `
        -ArgumentList $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Operation $Operation
    if ($Result.exit_code -ne 0) {
        $Detail = @($Result.stderr, $Result.stdout) -join " "
        $Detail = $Detail.Trim()
        if ($Detail) {
            throw "$Operation failed with exit code $($Result.exit_code): $Detail"
        }
        throw "$Operation failed with exit code $($Result.exit_code)"
    }
    return $Result.stdout
}

function Assert-YuneWindowsInteractiveScriptResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatusPath,
        [string]$Operation = "interactive script"
    )

    if (-not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
        throw "$Operation did not write interactive child status: $StatusPath"
    }

    try {
        $Status = Get-Content -Raw -LiteralPath $StatusPath | ConvertFrom-Json
    }
    catch {
        throw "$Operation interactive child status is not valid JSON: $StatusPath"
    }
    if ($null -eq $Status) {
        throw "$Operation interactive child status is empty or null JSON: $StatusPath"
    }

    $StateProperty = Get-JsonEvidenceProperty -Object $Status -Name "interactive_child_status"
    if (-not $StateProperty.Found -or [string]$StateProperty.Value -ne "completed") {
        throw "$Operation interactive child status did not complete: $StatusPath"
    }

    $ExitCodeProperty = Get-JsonEvidenceProperty -Object $Status -Name "exit_code"
    if (-not $ExitCodeProperty.Found) {
        throw "$Operation interactive child status is missing exit_code: $StatusPath"
    }
    $ExitCode = [int]$ExitCodeProperty.Value
    if ($ExitCode -ne 0) {
        $ErrorProperty = Get-JsonEvidenceProperty -Object $Status -Name "error"
        $ErrorText = if ($ErrorProperty.Found) { [string]$ErrorProperty.Value } else { "" }
        if ([string]::IsNullOrWhiteSpace($ErrorText)) {
            throw "$Operation failed in the interactive session with exit code $ExitCode."
        }
        throw "$Operation failed in the interactive session with exit code $ExitCode`: $ErrorText"
    }

    return $Status
}

function Invoke-YuneWindowsInteractiveScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)]
        [string]$StatusPath,
        [string]$WorkingDirectory = "",
        [int]$TimeoutSeconds = 300,
        [string]$Operation = "interactive script"
    )

    $FullScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $FullScriptPath -PathType Leaf)) {
        throw "$Operation script does not exist: $FullScriptPath"
    }

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = Split-Path -Parent $FullScriptPath
    }
    $FullWorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)
    if (-not (Test-Path -LiteralPath $FullWorkingDirectory -PathType Container)) {
        throw "$Operation working directory does not exist: $FullWorkingDirectory"
    }

    $FullStatusPath = [System.IO.Path]::GetFullPath($StatusPath)
    New-Item -ItemType Directory -Force (Split-Path -Parent $FullStatusPath) | Out-Null
    if (Test-Path -LiteralPath $FullStatusPath) {
        Remove-Item -LiteralPath $FullStatusPath -Force
    }

    $Payload = [ordered]@{
        script_path = $FullScriptPath
        arguments = @($ArgumentList)
        working_directory = $FullWorkingDirectory
        status_path = $FullStatusPath
        operation = $Operation
    }
    $PayloadJson = $Payload | ConvertTo-Json -Depth 6 -Compress
    $PayloadEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PayloadJson))
    $ChildScript = @"
`$ErrorActionPreference = "Stop"
`$PayloadJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$PayloadEncoded"))
`$Payload = `$PayloadJson | ConvertFrom-Json
`$ExitCode = 0
`$ErrorText = ""
try {
    Set-Location -LiteralPath ([string]`$Payload.working_directory)
    `$global:LASTEXITCODE = 0
    `$ChildArgumentList = @(`$Payload.arguments | ForEach-Object { [string]`$_ })
    `$ChildPowerShell = Join-Path `$PSHOME "powershell.exe"
    & `$ChildPowerShell -STA -NoProfile -ExecutionPolicy Bypass -File ([string]`$Payload.script_path) @ChildArgumentList
    if ((`$null -ne `$global:LASTEXITCODE) -and (`$global:LASTEXITCODE -ne 0)) {
        throw "child script exited with code `$global:LASTEXITCODE"
    }
}
catch {
    `$ExitCode = 1
    `$ErrorText = `$_.Exception.Message
}
try {
    New-Item -ItemType Directory -Force (Split-Path -Parent ([string]`$Payload.status_path)) | Out-Null
    [ordered]@{
        interactive_child_status = "completed"
        generated_at = (Get-Date).ToString("o")
        script_path = [string]`$Payload.script_path
        arguments = @(`$Payload.arguments)
        working_directory = [string]`$Payload.working_directory
        exit_code = `$ExitCode
        error = `$ErrorText
    } | ConvertTo-Json -Depth 6 | Out-File -LiteralPath ([string]`$Payload.status_path) -Encoding utf8
}
catch {
}
exit `$ExitCode
"@
    $EncodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ChildScript))
    $PowerShellExe = Join-Path $PSHOME "powershell.exe"
    $Shell = New-Object -ComObject Shell.Application
    Minimize-YuneWindowsCurrentProcessWindow
    $Shell.ShellExecute(
        $PowerShellExe,
        "-STA -NoProfile -ExecutionPolicy Bypass -EncodedCommand $EncodedCommand",
        $FullWorkingDirectory,
        "open",
        1) | Out-Null

    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $InteractiveStatusReadErrors = [System.Collections.Generic.List[string]]::new()
    do {
        if (Test-Path -LiteralPath $FullStatusPath -PathType Leaf) {
            try {
                return Assert-YuneWindowsInteractiveScriptResult `
                    -StatusPath $FullStatusPath `
                    -Operation $Operation
            }
            catch {
                $InteractiveStatusReadErrors.Add($_.Exception.Message) | Out-Null
            }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $Deadline)

    if ($InteractiveStatusReadErrors.Count -gt 0) {
        throw "$Operation timed out waiting for valid interactive child status after $TimeoutSeconds seconds: $FullStatusPath. Last status error: $($InteractiveStatusReadErrors[$InteractiveStatusReadErrors.Count - 1])"
    }
    throw "$Operation timed out waiting for interactive child status after $TimeoutSeconds seconds: $FullStatusPath"
}

function Invoke-YuneWindowsRegsvr32 {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 60,
        [string]$Operation = "regsvr32"
    )

    $Regsvr = Join-Path $env:SystemRoot "System32\regsvr32.exe"
    $Result = Invoke-YuneWindowsBoundedProcess `
        -FilePath $Regsvr `
        -ArgumentList $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -Operation $Operation
    if ($Result.exit_code -ne 0) {
        $Detail = @($Result.stderr, $Result.stdout) -join " "
        $Detail = $Detail.Trim()
        if ($Detail) {
            throw "$Operation failed with exit code $($Result.exit_code): $Detail"
        }
        throw "$Operation failed with exit code $($Result.exit_code)"
    }
    return $Result
}

function Write-LiveSmokeApprovalEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ApprovalNote,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [Parameter(Mandatory = $true)]
        [string]$YuneRoot,
        [string]$BrowserPath = ""
    )

    Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote

    $InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
    $YuneRootFullPath = [System.IO.Path]::GetFullPath($YuneRoot)
    $BrowserEvidence = Find-ChromiumBrowserPath -RequestedPath $BrowserPath
    Assert-ConcreteChromiumBrowserPath `
        -PathValue $BrowserEvidence `
        -Source "Live smoke approval browser path"
    $IsAdministrator = Test-IsAdministrator
    $IsSta = [Threading.Thread]::CurrentThread.ApartmentState -eq "STA"

    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    @(
        "# Live Smoke Approval",
        "",
        "Date: $((Get-Date).ToString("o"))",
        "",
        "Approval note: $ApprovalNote",
        "",
        "Machine state changed before approval evidence: false",
        "",
        "Administrator: $IsAdministrator",
        "",
        "STA: $IsSta",
        "",
        "Install dir: $InstallRoot",
        "",
        "Yune root: $YuneRootFullPath",
        "",
        "Browser path: $BrowserEvidence"
    ) | Out-File -LiteralPath $Path -Encoding utf8
}

function Capture-DesktopScreenshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $Bitmap = [System.Drawing.Bitmap]::new($Bounds.Width, $Bounds.Height)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    try {
        $Graphics.CopyFromScreen($Bounds.Left, $Bounds.Top, 0, 0, $Bounds.Size)
        New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
        $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
}

function Assert-DesktopScreenshotEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Context = "Desktop screenshot",
        [int]$MinimumWidth = 300,
        [int]$MinimumHeight = 200
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Context screenshot does not exist: $Path"
    }

    $Signature = [byte[]]::new(8)
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($Stream.Length -lt 8) {
            throw "$Context screenshot is too small to be a PNG: $Path"
        }
        [void]$Stream.Read($Signature, 0, $Signature.Length)
    }
    finally {
        $Stream.Dispose()
    }

    $PngSignature = [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
    for ($Index = 0; $Index -lt $PngSignature.Length; $Index++) {
        if ($Signature[$Index] -ne $PngSignature[$Index]) {
            throw "$Context screenshot is not a PNG file: $Path"
        }
    }

    Add-Type -AssemblyName System.Drawing
    $Image = $null
    try {
        $Image = [System.Drawing.Image]::FromFile($Path)
        if ($Image.Width -lt $MinimumWidth -or $Image.Height -lt $MinimumHeight) {
            throw "$Context screenshot is too small: $($Image.Width)x$($Image.Height), expected at least ${MinimumWidth}x${MinimumHeight}."
        }
    }
    catch {
        throw "$Context screenshot is not usable evidence: $($_.Exception.Message)"
    }
    finally {
        if ($Image) {
            $Image.Dispose()
        }
    }
}

function Assert-DistinctDesktopScreenshots {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidatePath,
        [Parameter(Mandatory = $true)]
        [string]$CommitPath,
        [string]$Context = "Text smoke"
    )

    Assert-DesktopScreenshotEvidence `
        -Path $CandidatePath `
        -Context "$Context candidate-display"
    Assert-DesktopScreenshotEvidence `
        -Path $CommitPath `
        -Context "$Context commit"

    $CandidateHash = (Get-FileHash -LiteralPath $CandidatePath -Algorithm SHA256).Hash
    $CommitHash = (Get-FileHash -LiteralPath $CommitPath -Algorithm SHA256).Hash
    if ($CandidateHash -eq $CommitHash) {
        throw "$Context candidate-display and commit screenshots are identical."
    }
}

function Reset-TextSmokeClipboard {
    param([string]$Context = "Text smoke")

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::Clear()
    Start-Sleep -Milliseconds 100
    $ClipboardText = [System.Windows.Forms.Clipboard]::GetText()
    if (-not [string]::IsNullOrEmpty($ClipboardText)) {
        throw "$Context clipboard could not be cleared before typing."
    }
}

function Reset-TextSmokeTargetContent {
    param([string]$Context = "Text smoke")

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep -Milliseconds 150
    Release-YuneWindowsModifierKeys -Context "$Context target reset"
    Send-YuneWindowsVirtualKey -VirtualKey 0x2e -Context "$Context target reset"
    Start-Sleep -Milliseconds 250
}

function Cancel-YuneWindowsTextComposition {
    param([string]$Context = "Text smoke")

    Release-YuneWindowsModifierKeys -Context "$Context composition cancel"
    Send-YuneWindowsVirtualKey -VirtualKey 0x1b -Context "$Context composition cancel"
    Release-YuneWindowsModifierKeys -Context "$Context composition cancel"
    Start-Sleep -Milliseconds 250
}

function Release-YuneWindowsModifierKeys {
    param([string]$Context = "Text smoke")

    Ensure-YuneWindowsForegroundWindowType
    $ModifierKeys = @(
        @{ Name = "VK_CONTROL"; Key = 0x11 },
        @{ Name = "VK_MENU"; Key = 0x12 },
        @{ Name = "VK_SHIFT"; Key = 0x10 },
        @{ Name = "VK_LWIN"; Key = 0x5b },
        @{ Name = "VK_RWIN"; Key = 0x5c }
    )
    $Inputs = [YuneWindowsWindows.Input[]]::new($ModifierKeys.Count)
    for ($Index = 0; $Index -lt $ModifierKeys.Count; $Index++) {
        $VirtualKey = [int]$ModifierKeys[$Index].Key
        $ScanCode = [byte]([YuneWindowsWindows.ForegroundWindow]::MapVirtualKey([uint32]$VirtualKey, 0) -band 0xff)
        $Inputs[$Index] = New-YuneWindowsKeyboardInput -VirtualKey $VirtualKey -ScanCode $ScanCode -Flags 2
    }

    $InputSize = [System.Runtime.InteropServices.Marshal]::SizeOf([YuneWindowsWindows.Input]::new())
    $SentInputCount = [YuneWindowsWindows.ForegroundWindow]::SendInput([uint32]$Inputs.Length, $Inputs, $InputSize)
    if ($SentInputCount -ne $Inputs.Length) {
        $LastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Context modifier release SendInput sent $SentInputCount of $($Inputs.Length) keyboard events (last error $LastError)."
    }
    Start-Sleep -Milliseconds 80
}

function Save-TextSmokeFailureScreenshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        Capture-DesktopScreenshot -Path $Path
        return [ordered]@{
            captured = $true
            error = ""
        }
    }
    catch {
        return [ordered]@{
            captured = $false
            error = $_.Exception.Message
        }
    }
}

function Add-StringItems {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [object]$Items,
        [string]$Prefix = ""
    )

    foreach ($Item in @($Items)) {
        $Text = [string]$Item
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            $Target.Add($Prefix + $Text)
        }
    }
}

function Get-UniqueStringItems {
    param([object]$Items)

    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Unique = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in @($Items)) {
        $Text = [string]$Item
        if ([string]::IsNullOrWhiteSpace($Text)) {
            continue
        }
        if ($Seen.Add($Text)) {
            $Unique.Add($Text)
        }
    }
    return @($Unique)
}

function Get-YuneWindowsMachineResidueRegistryKeys {
    $TextServiceClsid = "{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}"
    $ProfileGuid = "{3AE69B8D-19B4-4267-8F21-E239666D6632}"
    $LanguageProfilePath = "LanguageProfile\0x00000c04\$ProfileGuid"

    return @(
        "Registry::HKEY_CLASSES_ROOT\CLSID\$TextServiceClsid",
        "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\$TextServiceClsid",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\CTF\TIP\$TextServiceClsid",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\CTF\TIP\$TextServiceClsid\$LanguageProfilePath",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid\$LanguageProfilePath",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\CTF\TIP\$TextServiceClsid",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\CTF\TIP\$TextServiceClsid\$LanguageProfilePath"
    )
}

function Get-YuneWindowsMachineRegistrationRequiredRegistryKeys {
    $TextServiceClsid = "{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}"
    $ProfileGuid = "{3AE69B8D-19B4-4267-8F21-E239666D6632}"
    $LanguageProfilePath = "LanguageProfile\0x00000c04\$ProfileGuid"

    return @(
        "Registry::HKEY_CLASSES_ROOT\CLSID\$TextServiceClsid",
        "Registry::HKEY_CLASSES_ROOT\CLSID\$TextServiceClsid\InprocServer32",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid\$LanguageProfilePath",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\CTF\TIP\$TextServiceClsid\$LanguageProfilePath"
    )
}

function Get-YuneWindowsRegistryDefaultValue {
    param([Parameter(Mandatory = $true)][string]$RegistryPath)

    $Item = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
    return [string]$Item.GetValue("")
}

function Get-YuneWindowsMachineRegistrationState {
    param([string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme")

    $InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
    $ExpectedDllPath = Join-Path $InstallRoot "YuneWindowsTSF.dll"
    $RequiredKeys = @(Get-YuneWindowsMachineRegistrationRequiredRegistryKeys)
    $MissingKeys = [System.Collections.Generic.List[string]]::new()
    $RegistryCheckErrors = [System.Collections.Generic.List[string]]::new()

    foreach ($RegistryKey in $RequiredKeys) {
        try {
            if (-not (Test-Path -LiteralPath $RegistryKey)) {
                $MissingKeys.Add($RegistryKey) | Out-Null
            }
        }
        catch {
            $RegistryCheckErrors.Add("$RegistryKey ($($_.Exception.Message))") | Out-Null
        }
    }

    $InprocServerPath = "Registry::HKEY_CLASSES_ROOT\CLSID\{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\InprocServer32"
    $RegisteredDllPath = ""
    $DllPathMatches = $false
    try {
        if (Test-Path -LiteralPath $InprocServerPath) {
            $RegisteredDllPath = Get-YuneWindowsRegistryDefaultValue -RegistryPath $InprocServerPath
            if (-not [string]::IsNullOrWhiteSpace($RegisteredDllPath)) {
                $RegisteredFullPath = [System.IO.Path]::GetFullPath($RegisteredDllPath)
                $ExpectedFullPath = [System.IO.Path]::GetFullPath($ExpectedDllPath)
                $DllPathMatches = [string]::Equals(
                    $RegisteredFullPath,
                    $ExpectedFullPath,
                    [System.StringComparison]::OrdinalIgnoreCase)
            }
        }
    }
    catch {
        $RegistryCheckErrors.Add("$InprocServerPath default value ($($_.Exception.Message))") | Out-Null
    }

    $Verified = $RegistryCheckErrors.Count -eq 0
    $Registered = $Verified -and $MissingKeys.Count -eq 0 -and $DllPathMatches

    return [ordered]@{
        machine_registration_checked = $true
        machine_registration_verified = [bool]$Verified
        machine_registration_registered = [bool]$Registered
        machine_registration_required_keys = @($RequiredKeys)
        machine_registration_missing_keys = @($MissingKeys)
        machine_registration_registry_check_errors = @($RegistryCheckErrors)
        machine_registration_expected_dll_path = [System.IO.Path]::GetFullPath($ExpectedDllPath)
        machine_registration_dll_path = $RegisteredDllPath
        machine_registration_dll_path_matches = [bool]$DllPathMatches
    }
}

function Assert-YuneWindowsMachineRegistration {
    param([string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme")

    $State = Get-YuneWindowsMachineRegistrationState -InstallDir $InstallDir
    $Issues = [System.Collections.Generic.List[string]]::new()
    if ($State.machine_registration_verified -ne $true) {
        $Issues.Add("registry checks failed: $($State.machine_registration_registry_check_errors -join '; ')") | Out-Null
    }
    if (@($State.machine_registration_missing_keys).Count -gt 0) {
        $Issues.Add("missing registry keys: $($State.machine_registration_missing_keys -join '; ')") | Out-Null
    }
    if ($State.machine_registration_dll_path_matches -ne $true) {
        $Issues.Add("registered DLL path '$($State.machine_registration_dll_path)' did not match '$($State.machine_registration_expected_dll_path)'") | Out-Null
    }
    if ($State.machine_registration_registered -ne $true) {
        $Issues.Add("machine registration did not verify") | Out-Null
    }
    if ($Issues.Count -gt 0) {
        throw "YuneWindows machine registration did not verify after regsvr32: $($Issues -join '; ')"
    }
    return $State
}

function Assert-YuneWindowsMachineRegistrationAbsent {
    param([string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme")

    $State = Get-YuneWindowsMachineRegistrationState -InstallDir $InstallDir
    $RequiredKeyCount = @($State.machine_registration_required_keys).Count
    $MissingKeyCount = @($State.machine_registration_missing_keys).Count
    $Issues = [System.Collections.Generic.List[string]]::new()
    if ($State.machine_registration_verified -ne $true) {
        $Issues.Add("registry checks failed: $($State.machine_registration_registry_check_errors -join '; ')") | Out-Null
    }
    if ($MissingKeyCount -ne $RequiredKeyCount) {
        $PresentKeys = @($State.machine_registration_required_keys | Where-Object {
                @($State.machine_registration_missing_keys) -notcontains $_
            })
        $Issues.Add("machine registration remains after unregister: $($PresentKeys -join '; ')") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.machine_registration_dll_path)) {
        $Issues.Add("registered DLL path remains after unregister: $($State.machine_registration_dll_path)") | Out-Null
    }
    if ($State.machine_registration_registered -eq $true) {
        $Issues.Add("machine registration remains after unregister") | Out-Null
    }
    if ($Issues.Count -gt 0) {
        throw "YuneWindows machine registration did not clear after regsvr32 /u: $($Issues -join '; ')"
    }
    return $State
}

function Clear-YuneWindowsMachineRegistrationResidue {
    param([string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme")

    $Removed = [System.Collections.Generic.List[string]]::new()
    foreach ($RegistryPath in @(Get-YuneWindowsMachineResidueRegistryKeys)) {
        try {
            if (Test-Path -LiteralPath $RegistryPath) {
                Remove-Item -LiteralPath $RegistryPath -Recurse -Force
                $Removed.Add($RegistryPath) | Out-Null
            }
        }
        catch {
            throw "failed to clear YuneWindows registration residue $RegistryPath`: $($_.Exception.Message)"
        }
    }
    return @($Removed)
}

function Get-YuneWindowsMachineResidue {
    param([string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme")

    $MachineStateIssues = [System.Collections.Generic.List[string]]::new()
    $FilesystemLeftovers = [System.Collections.Generic.List[string]]::new()

    $RegistryKeys = Get-YuneWindowsMachineResidueRegistryKeys
    foreach ($RegistryKey in $RegistryKeys) {
        try {
            if (Test-Path -LiteralPath $RegistryKey) {
                $MachineStateIssues.Add("Registry key remains: $RegistryKey")
            }
        }
        catch {
            $MachineStateIssues.Add("Registry key check failed: $RegistryKey ($($_.Exception.Message))")
        }
    }

    $SessionManagerKey = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager"
    try {
        $Pending = (Get-ItemProperty `
                -LiteralPath $SessionManagerKey `
                -Name PendingFileRenameOperations `
                -ErrorAction Stop).PendingFileRenameOperations
        foreach ($Entry in @($Pending)) {
            $EntryText = [string]$Entry
            if ($EntryText -match "(?i)YuneWindows") {
                $MachineStateIssues.Add("PendingFileRenameOperations contains YuneWindows residue: $EntryText")
            }
        }
    }
    catch {
    }

    $SystemDirs = @(
        (Join-Path $env:SystemRoot "System32"),
        (Join-Path $env:SystemRoot "SysWOW64")
    )
    foreach ($SystemDir in $SystemDirs) {
        if (-not (Test-Path -LiteralPath $SystemDir)) {
            continue
        }
        Get-ChildItem -LiteralPath $SystemDir -File -Filter "YuneWindows*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $FilesystemLeftovers.Add($_.FullName)
            }
    }

    return [ordered]@{
        machine_state_issues = @(Get-UniqueStringItems -Items $MachineStateIssues)
        filesystem_leftovers = @(Get-UniqueStringItems -Items $FilesystemLeftovers)
    }
}

function Assert-CleanupPlanInstallDir {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Plan,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [string]$Context = "YuneWindows machine cleanup plan"
    )

    $InstallDirProperty = $Plan.PSObject.Properties["install_dir"]
    if ($null -eq $InstallDirProperty -or [string]::IsNullOrWhiteSpace([string]$InstallDirProperty.Value)) {
        throw "$Context must record install_dir."
    }

    $PlanInstallDir = [System.IO.Path]::GetFullPath([string]$InstallDirProperty.Value)
    $RequestedInstallDir = [System.IO.Path]::GetFullPath($InstallDir)
    if (-not [string]::Equals($PlanInstallDir, $RequestedInstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context install_dir mismatch: plan=$PlanInstallDir requested=$RequestedInstallDir"
    }
}

function Get-JsonEvidenceProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return [pscustomobject]@{
            Found = $true
            Value = $Object[$Name]
        }
    }

    $Property = $Object.PSObject.Properties[$Name]
    if ($null -ne $Property) {
        return [pscustomobject]@{
            Found = $true
            Value = $Property.Value
        }
    }

    return [pscustomobject]@{
        Found = $false
        Value = $null
    }
}

function Assert-JsonBooleanProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $Value = Get-RequiredJsonBooleanProperty -Object $Object -Name $Name -Context $Context
    if ($Value -ne $Expected) {
        throw "$Context must record $Name=$($Expected.ToString().ToLowerInvariant())."
    }
}

function Get-RequiredJsonBooleanProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $Property = Get-JsonEvidenceProperty -Object $Object -Name $Name
    if (-not $Property.Found -or $Property.Value -isnot [bool]) {
        throw "$Context $Name must be a JSON boolean."
    }
    return $Property.Value
}

function Get-OptionalJsonBooleanProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Default,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $Property = Get-JsonEvidenceProperty -Object $Object -Name $Name
    if (-not $Property.Found) {
        return $Default
    }
    if ($Property.Value -isnot [bool]) {
        throw "$Context $Name must be a JSON boolean."
    }
    return $Property.Value
}

function Read-YuneWindowsProfileStateEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileStateText,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "$Context profile state is not valid JSON: $ProfileStateText"
    }

    [void](Get-RequiredJsonBooleanProperty `
            -Object $ProfileState `
            -Name "registered" `
            -Context "$Context profile_state")
    [void](Get-RequiredJsonBooleanProperty `
            -Object $ProfileState `
            -Name "active" `
            -Context "$Context profile_state")
    return $ProfileState
}

function Assert-CleanupPlanProvenance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Plan,
        [string]$Context = "YuneWindows machine cleanup plan"
    )

    $GeneratedAtProperty = $Plan.PSObject.Properties["generated_at"]
    if ($null -eq $GeneratedAtProperty -or [string]::IsNullOrWhiteSpace([string]$GeneratedAtProperty.Value)) {
        throw "$Context must record parseable generated_at."
    }
    $ParsedGeneratedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            [string]$GeneratedAtProperty.Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$ParsedGeneratedAt)) {
        throw "$Context must record parseable generated_at."
    }
    Assert-JsonBooleanProperty -Object $Plan -Name "machine_state_changed" -Expected $false -Context $Context
    Assert-JsonBooleanProperty -Object $Plan -Name "machine_state_checked" -Expected $true -Context $Context
    if ([string]$Plan.residue_detector -ne "Get-YuneWindowsMachineResidue") {
        throw "$Context must record residue_detector=Get-YuneWindowsMachineResidue."
    }
    Assert-JsonBooleanProperty -Object $Plan -Name "requires_current_session_approval" -Expected $true -Context $Context
}

function Get-YuneWindowsStateSnapshotCapturedAtIssue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Snapshot,
        [string]$Context = "YuneWindows state snapshot"
    )

    $CapturedAtProperty = $Snapshot.PSObject.Properties["captured_at"]
    if ($null -eq $CapturedAtProperty -or [string]::IsNullOrWhiteSpace([string]$CapturedAtProperty.Value)) {
        return "$Context must record parseable captured_at."
    }

    $ParsedCapturedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            [string]$CapturedAtProperty.Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$ParsedCapturedAt)) {
        return "$Context must record parseable captured_at."
    }

    return $null
}

function Assert-YuneWindowsStateSnapshotCapturedAt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Snapshot,
        [string]$Context = "YuneWindows state snapshot"
    )

    $Issue = Get-YuneWindowsStateSnapshotCapturedAtIssue -Snapshot $Snapshot -Context $Context
    if ($Issue) {
        throw $Issue
    }
}

function Assert-CleanupPlanResidueGroups {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Plan,
        [string]$Context = "YuneWindows machine cleanup plan"
    )

    $ResidueGroupsProperty = $Plan.PSObject.Properties["residue_groups"]
    if ($null -eq $ResidueGroupsProperty) {
        throw "$Context must record residue_groups."
    }

    $ResidueGroups = @($ResidueGroupsProperty.Value)
    if ($ResidueGroups.Count -eq 0) {
        throw "$Context residue_groups must include at least one approval-required residue group."
    }

    foreach ($Group in $ResidueGroups) {
        $AffectedPath = [string]$Group.affected_path
        if ([string]::IsNullOrWhiteSpace($AffectedPath)) {
            throw "$Context residue group must record affected_path."
        }
        Assert-JsonBooleanProperty -Object $Group -Name "approval_required" -Expected $true -Context "$Context residue group"

        $ResidueEntryCount = @($Group.pending_rename_entries).Count +
            @($Group.registry_entries).Count +
            @($Group.registry_check_failures).Count +
            @($Group.machine_state_entries).Count +
            @($Group.filesystem_leftovers).Count
        if ($ResidueEntryCount -le 0) {
            throw "$Context residue group must include at least one residue entry: $AffectedPath"
        }
    }
}

function Add-CleanupPlanCoverageItem {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Target,
        [AllowNull()]
        [object]$Items
    )

    foreach ($Item in @($Items)) {
        $Text = [string]$Item
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            [void]$Target.Add($Text)
        }
    }
}

function New-CleanupPlanCoverageSet {
    param(
        [AllowNull()]
        [object]$Items
    )

    $Set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Add-CleanupPlanCoverageItem `
        -Target $Set `
        -Items $Items
    return ,$Set
}

function Assert-CleanupPlanHasNoExtraCoverageItems {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$CoveredItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$CurrentItems,
        [Parameter(Mandatory = $true)]
        [string]$Kind,
        [string]$Context = "YuneWindows machine cleanup plan"
    )

    foreach ($Item in $CoveredItems) {
        if (-not $CurrentItems.Contains($Item)) {
            throw "$Context contains extra cleanup target not present in current $Kind residue: $Item"
        }
    }
}

function Assert-CleanupPlanCoversCurrentResidue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Plan,
        [Parameter(Mandatory = $true)]
        [object]$CurrentResidue,
        [string]$Context = "YuneWindows machine cleanup plan"
    )

    $CoveredMachineResidue = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $CoveredFilesystemResidue = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    Add-CleanupPlanCoverageItem `
        -Target $CoveredMachineResidue `
        -Items $Plan.machine_state_issues
    Add-CleanupPlanCoverageItem `
        -Target $CoveredFilesystemResidue `
        -Items $Plan.filesystem_leftovers

    foreach ($Group in @($Plan.residue_groups)) {
        Add-CleanupPlanCoverageItem `
            -Target $CoveredMachineResidue `
            -Items $Group.pending_rename_entries
        Add-CleanupPlanCoverageItem `
            -Target $CoveredMachineResidue `
            -Items $Group.registry_entries
        Add-CleanupPlanCoverageItem `
            -Target $CoveredMachineResidue `
            -Items $Group.registry_check_failures
        Add-CleanupPlanCoverageItem `
            -Target $CoveredMachineResidue `
            -Items $Group.machine_state_entries
        Add-CleanupPlanCoverageItem `
            -Target $CoveredFilesystemResidue `
            -Items $Group.filesystem_leftovers
    }

    foreach ($Issue in @($CurrentResidue.machine_state_issues)) {
        $IssueText = [string]$Issue
        if ([string]::IsNullOrWhiteSpace($IssueText)) {
            continue
        }
        if (-not $CoveredMachineResidue.Contains($IssueText)) {
            throw "$Context does not cover current machine-state residue: $IssueText"
        }
    }

    foreach ($Leftover in @($CurrentResidue.filesystem_leftovers)) {
        $LeftoverText = [string]$Leftover
        if ([string]::IsNullOrWhiteSpace($LeftoverText)) {
            continue
        }
        if (-not $CoveredFilesystemResidue.Contains($LeftoverText)) {
            throw "$Context does not cover current filesystem leftover: $LeftoverText"
        }
    }

    $CurrentMachineResidue = New-CleanupPlanCoverageSet -Items $CurrentResidue.machine_state_issues
    $CurrentFilesystemResidue = New-CleanupPlanCoverageSet -Items $CurrentResidue.filesystem_leftovers
    Assert-CleanupPlanHasNoExtraCoverageItems `
        -CoveredItems $CoveredMachineResidue `
        -CurrentItems $CurrentMachineResidue `
        -Kind "machine-state" `
        -Context $Context
    Assert-CleanupPlanHasNoExtraCoverageItems `
        -CoveredItems $CoveredFilesystemResidue `
        -CurrentItems $CurrentFilesystemResidue `
        -Kind "filesystem" `
        -Context $Context
}

function Get-YuneWindowsStateSnapshot {
    param(
        [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
        [string]$ProfileToolPath = "",
        [string]$ApprovalNote = "",
        [switch]$IncludeMachineResidue,
        [switch]$IncludeMachineRegistration
    )

    $InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
    $InstalledProfileTool = Join-Path $InstallRoot "YuneWindowsProfileTool.exe"
    $ProfileTool = $InstalledProfileTool
    if (-not (Test-Path -LiteralPath $ProfileTool) -and $ProfileToolPath) {
        $ProfileTool = [System.IO.Path]::GetFullPath($ProfileToolPath)
    }
    $ProfileState = $null
    $ProfileStateVerified = $false
    $ProfileStateSource = $null
    $ProfileStateError = $null
    if (Test-Path -LiteralPath $ProfileTool) {
        $ProfileStateSource = [System.IO.Path]::GetFullPath($ProfileTool)
        try {
            $ProfileState = (Invoke-YuneWindowsProfileTool `
                    -ProfileToolPath $ProfileTool `
                    -Arguments @("--state") `
                    -Operation "profile state check").Trim()
            try {
                $ParsedProfileState = $ProfileState | ConvertFrom-Json
            }
            catch {
                throw "profile state check returned invalid JSON: $ProfileState"
            }
            $RegisteredProperty = $ParsedProfileState.PSObject.Properties["registered"]
            $ActiveProperty = $ParsedProfileState.PSObject.Properties["active"]
            if ($null -eq $RegisteredProperty -or $null -eq $ActiveProperty) {
                throw "profile state check returned invalid JSON: missing registered or active fields"
            }
            if ($RegisteredProperty.Value -isnot [bool] -or $ActiveProperty.Value -isnot [bool]) {
                throw "profile state check returned invalid JSON: registered and active fields must be booleans"
            }
            $ProfileStateVerified = $true
        }
        catch {
            $ProfileStateError = $_.Exception.Message
        }
    }

    $Processes = @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
        Select-Object Id, ProcessName, Path, StartTime)

    $MachineStateIssues = @()
    $FilesystemLeftovers = @()
    if ($IncludeMachineResidue) {
        Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
        $Residue = Get-YuneWindowsMachineResidue -InstallDir $InstallRoot
        $MachineStateIssues = @($Residue.machine_state_issues)
        $FilesystemLeftovers = @($Residue.filesystem_leftovers)
    }

    $MachineRegistration = [ordered]@{
        machine_registration_checked = [bool]$IncludeMachineRegistration
        machine_registration_verified = $false
        machine_registration_registered = $false
        machine_registration_required_keys = @()
        machine_registration_missing_keys = @()
        machine_registration_registry_check_errors = @()
        machine_registration_expected_dll_path = Join-Path $InstallRoot "YuneWindowsTSF.dll"
        machine_registration_dll_path = ""
        machine_registration_dll_path_matches = $false
    }
    if ($IncludeMachineRegistration) {
        Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
        $MachineRegistration = Get-YuneWindowsMachineRegistrationState -InstallDir $InstallRoot
    }

    return [ordered]@{
        captured_at = (Get-Date).ToString("o")
        install_dir = $InstallRoot
        install_dir_exists = Test-Path -LiteralPath $InstallRoot
        profile_tool_exists = Test-Path -LiteralPath $InstalledProfileTool
        profile_state_source = $ProfileStateSource
        profile_state_verified = $ProfileStateVerified
        profile_state_error = $ProfileStateError
        profile_state = $ProfileState
        server_processes = $Processes
        machine_state_checked = [bool]$IncludeMachineResidue
        machine_state_issues = $MachineStateIssues
        filesystem_leftovers = $FilesystemLeftovers
        machine_registration_checked = [bool]$MachineRegistration.machine_registration_checked
        machine_registration_verified = [bool]$MachineRegistration.machine_registration_verified
        machine_registration_registered = [bool]$MachineRegistration.machine_registration_registered
        machine_registration_required_keys = @($MachineRegistration.machine_registration_required_keys)
        machine_registration_missing_keys = @($MachineRegistration.machine_registration_missing_keys)
        machine_registration_registry_check_errors = @($MachineRegistration.machine_registration_registry_check_errors)
        machine_registration_expected_dll_path = [string]$MachineRegistration.machine_registration_expected_dll_path
        machine_registration_dll_path = [string]$MachineRegistration.machine_registration_dll_path
        machine_registration_dll_path_matches = [bool]$MachineRegistration.machine_registration_dll_path_matches
    }
}

function Write-YuneWindowsStateSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
        [string]$ProfileToolPath = "",
        [string]$ApprovalNote = "",
        [switch]$IncludeMachineResidue,
        [switch]$IncludeMachineRegistration
    )

    $Snapshot = Get-YuneWindowsStateSnapshot `
        -InstallDir $InstallDir `
        -ProfileToolPath $ProfileToolPath `
        -ApprovalNote $ApprovalNote `
        -IncludeMachineResidue:$IncludeMachineResidue `
        -IncludeMachineRegistration:$IncludeMachineRegistration
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    $Snapshot | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}

function Assert-NoYuneWindowsServerProcess {
    param([string]$Context = "YuneWindows live smoke")

    $Processes = @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue)
    if ($Processes.Count -eq 0) {
        return
    }

    $ProcessIds = @($Processes | ForEach-Object { [string]$_.Id })
    throw "$Context found existing YuneWindowsServer.exe process before starting the controlled shared server: PID(s) $($ProcessIds -join ', ')"
}

function Get-YuneWindowsInstalledServerProcesses {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $ServerPath = Join-Path $InstallDir "YuneWindowsServer.exe"
    return @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -eq $ServerPath
            }
            catch {
                $false
            }
        } |
        Select-Object Id, ProcessName, Path, StartTime)
}

function Assert-YuneWindowsActiveInstalledSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Context = "YuneWindows post-smoke state"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Context snapshot does not exist: $Path"
    }

    try {
        $Snapshot = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "$Context snapshot is not valid JSON: $Path"
    }

    Assert-YuneWindowsStateSnapshotCapturedAt -Snapshot $Snapshot -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "install_dir_exists" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "profile_tool_exists" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "profile_state_verified" -Expected $true -Context "$Context snapshot"

    $ProfileStateText = [string]$Snapshot.profile_state
    if ([string]::IsNullOrWhiteSpace($ProfileStateText)) {
        throw "$Context snapshot does not include profile state."
    }

    $ProfileState = Read-YuneWindowsProfileStateEvidence -ProfileStateText $ProfileStateText -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $true -Context "$Context snapshot profile_state"
    Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $true -Context "$Context snapshot profile_state"
}

function Assert-YuneWindowsRegisteredInstalledSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Context = "YuneWindows post-install state"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Context snapshot does not exist: $Path"
    }

    try {
        $Snapshot = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "$Context snapshot is not valid JSON: $Path"
    }

    Assert-YuneWindowsStateSnapshotCapturedAt -Snapshot $Snapshot -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "install_dir_exists" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "profile_tool_exists" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "machine_registration_checked" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "machine_registration_verified" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "machine_registration_registered" -Expected $true -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "machine_registration_dll_path_matches" -Expected $true -Context "$Context snapshot"
    if (@($Snapshot.machine_registration_missing_keys).Count -gt 0) {
        throw "$Context snapshot has missing machine-registration keys: $($Snapshot.machine_registration_missing_keys -join '; ')"
    }
    if (@($Snapshot.machine_registration_registry_check_errors).Count -gt 0) {
        throw "$Context snapshot has machine-registration check errors: $($Snapshot.machine_registration_registry_check_errors -join '; ')"
    }
}

function Assert-YuneWindowsCleanPreInstallSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Context = "YuneWindows pre-install state"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Context snapshot does not exist: $Path"
    }

    try {
        $Snapshot = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "$Context snapshot is not valid JSON: $Path"
    }

    Assert-YuneWindowsStateSnapshotCapturedAt -Snapshot $Snapshot -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "install_dir_exists" -Expected $false -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $Snapshot -Name "profile_tool_exists" -Expected $false -Context "$Context snapshot"
    $ServerProcesses = @()
    if ($null -ne $Snapshot.server_processes) {
        $IsEmptyObject = ($Snapshot.server_processes -is [pscustomobject]) -and
            (@($Snapshot.server_processes.PSObject.Properties).Count -eq 0)
        if (-not $IsEmptyObject) {
            $ServerProcesses = @($Snapshot.server_processes)
        }
    }
    if ($ServerProcesses.Count -ne 0) {
        throw "$Context snapshot shows a YuneWindowsServer.exe process."
    }
    Assert-JsonBooleanProperty -Object $Snapshot -Name "profile_state_verified" -Expected $true -Context "$Context snapshot"

    $ProfileStateText = [string]$Snapshot.profile_state
    if ([string]::IsNullOrWhiteSpace($ProfileStateText)) {
        throw "$Context snapshot does not include profile state."
    }

    $ProfileState = Read-YuneWindowsProfileStateEvidence -ProfileStateText $ProfileStateText -Context "$Context snapshot"
    Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $false -Context "$Context snapshot profile_state"
    Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false -Context "$Context snapshot profile_state"

    $ResidueResult = Test-YuneWindowsCleanupState `
        -Snapshot $Snapshot `
        -RequireProfileState `
        -RequireMachineResidueCheck `
        -RequireCapturedAt
    if ($ResidueResult.pass -ne $true) {
        throw "$Context snapshot shows cleanup residue: $($ResidueResult.issues -join '; ')"
    }
}

function Test-YuneWindowsCleanupState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Snapshot,
        [switch]$RequireProfileState,
        [switch]$RequireMachineResidueCheck,
        [switch]$RequireCapturedAt
    )

    $Issues = [System.Collections.Generic.List[string]]::new()
    $InstallDir = [string]$Snapshot.install_dir

    if ($RequireCapturedAt) {
        $CapturedAtIssue = Get-YuneWindowsStateSnapshotCapturedAtIssue `
            -Snapshot $Snapshot `
            -Context "YuneWindows cleanup state snapshot"
        if ($CapturedAtIssue) {
            $Issues.Add($CapturedAtIssue)
        }
    }

    $InstallDirExists = $null
    $InstallDirExistsProperty = Get-JsonEvidenceProperty -Object $Snapshot -Name "install_dir_exists"
    if (-not $InstallDirExistsProperty.Found -or $InstallDirExistsProperty.Value -isnot [bool]) {
        $Issues.Add("Install directory state was not recorded as a JSON boolean")
    }
    else {
        $InstallDirExists = $InstallDirExistsProperty.Value
    }

    $ProfileToolExists = $null
    $ProfileToolExistsProperty = Get-JsonEvidenceProperty -Object $Snapshot -Name "profile_tool_exists"
    if (-not $ProfileToolExistsProperty.Found -or $ProfileToolExistsProperty.Value -isnot [bool]) {
        $Issues.Add("Installed profile-tool state was not recorded as a JSON boolean")
    }
    else {
        $ProfileToolExists = $ProfileToolExistsProperty.Value
    }

    if ($InstallDirExists -eq $true) {
        $Issues.Add("Install directory still exists")
    }
    if ($ProfileToolExists -eq $true) {
        $Issues.Add("Installed YuneWindowsProfileTool.exe still exists")
    }

    $ServerProcesses = @()
    if ($null -ne $Snapshot.server_processes) {
        $IsEmptyObject = ($Snapshot.server_processes -is [pscustomobject]) -and
            (@($Snapshot.server_processes.PSObject.Properties).Count -eq 0)
        if (-not $IsEmptyObject) {
            $ServerProcesses = @($Snapshot.server_processes)
        }
    }
    foreach ($Process in $ServerProcesses) {
        $Path = [string]$Process.Path
        if ($Path -and $InstallDir -and
            $Path.StartsWith($InstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $Issues.Add("YuneWindowsServer.exe is still running from the install path")
        }
        else {
            $Issues.Add("YuneWindowsServer.exe is still running")
        }
        break
    }

    $ProfileText = [string]$Snapshot.profile_state
    if ($RequireProfileState) {
        $ProfileStateVerifiedProperty = Get-JsonEvidenceProperty -Object $Snapshot -Name "profile_state_verified"
        if (-not $ProfileStateVerifiedProperty.Found -or
            $ProfileStateVerifiedProperty.Value -isnot [bool] -or
            $ProfileStateVerifiedProperty.Value -ne $true) {
            $Issues.Add("YuneWindows TSF profile state was not verified")
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProfileText)) {
        try {
            $Profile = Read-YuneWindowsProfileStateEvidence -ProfileStateText $ProfileText -Context "YuneWindows TSF"
            if ($Profile.registered -eq $true) {
                $Issues.Add("YuneWindows TSF profile is still registered")
            }
            if ($Profile.active -eq $true) {
                $Issues.Add("YuneWindows TSF profile is still active")
            }
        }
        catch {
            $Issues.Add("YuneWindows TSF profile state could not be parsed")
        }
    }

    if ($RequireMachineResidueCheck) {
        $MachineStateCheckedProperty = Get-JsonEvidenceProperty -Object $Snapshot -Name "machine_state_checked"
        if (-not $MachineStateCheckedProperty.Found -or
            $MachineStateCheckedProperty.Value -isnot [bool] -or
            $MachineStateCheckedProperty.Value -ne $true) {
            $Issues.Add("Machine-state residue check was not verified")
        }
    }

    Add-StringItems `
        -Target $Issues `
        -Items $Snapshot.machine_state_issues `
        -Prefix "Machine-state cleanup issue: "
    Add-StringItems `
        -Target $Issues `
        -Items $Snapshot.filesystem_leftovers `
        -Prefix "Filesystem cleanup leftover: "

    return [ordered]@{
        generated_at = (Get-Date).ToString("o")
        pass = $Issues.Count -eq 0
        issues = @($Issues)
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-YuneWindowsProfileActive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileToolPath,
        [string]$Context = "YuneWindows"
    )

    $ProfileStateText = (Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $ProfileToolPath `
            -Arguments @("--state") `
            -Operation "$Context profile state check").Trim()
    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "$Context profile state check returned invalid JSON: $ProfileStateText"
    }

    try {
        Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $true -Context "$Context profile state"
        Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $true -Context "$Context profile state"
    }
    catch {
        throw "$Context profile activation did not verify: $ProfileStateText ($($_.Exception.Message))"
    }
}

function Wait-YuneWindowsProfileRegistered {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileToolPath,
        [string]$Context = "YuneWindows",
        [int]$Attempts = 20,
        [int]$DelayMilliseconds = 250
    )

    $LastProfileStateText = ""
    $LastError = ""
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        try {
            $ProfileStateText = (Invoke-YuneWindowsProfileTool `
                    -ProfileToolPath $ProfileToolPath `
                    -Arguments @("--state") `
                    -Operation "$Context profile registration wait").Trim()
            $LastProfileStateText = $ProfileStateText
            $ProfileState = $ProfileStateText | ConvertFrom-Json
            Assert-JsonBooleanProperty -Object $ProfileState -Name "registered" -Expected $true -Context "$Context profile state"
            return $ProfileStateText
        }
        catch {
            $LastError = $_.Exception.Message
        }

        if ($Attempt -lt $Attempts) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LastProfileStateText)) {
        throw "$Context profile registration did not become visible after $Attempts attempts: $LastProfileStateText ($LastError)"
    }
    throw "$Context profile registration did not become visible after $Attempts attempts: $LastError"
}

function Invoke-YuneWindowsProfileDeactivationForSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileToolPath,
        [string]$Context = "YuneWindows smoke"
    )

    $ProfileStateText = (Invoke-YuneWindowsProfileTool `
            -ProfileToolPath $ProfileToolPath `
            -Arguments @("--deactivate") `
            -Operation "$Context profile deactivation for cleanup").Trim()
    try {
        $ProfileState = $ProfileStateText | ConvertFrom-Json
    }
    catch {
        throw "$Context profile deactivation for cleanup returned invalid JSON: $ProfileStateText"
    }

    try {
        Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false -Context "$Context profile deactivation"
    }
    catch {
        throw "$Context profile deactivation for cleanup did not verify: $ProfileStateText ($($_.Exception.Message))"
    }
}

function Ensure-YuneWindowsForegroundWindowType {
    if (-not ("YuneWindowsWindows.ForegroundWindow" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace YuneWindowsWindows {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct Point {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KeyboardInput {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MouseInput {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HardwareInput {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)]
        public MouseInput mi;
        [FieldOffset(0)]
        public KeyboardInput ki;
        [FieldOffset(0)]
        public HardwareInput hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Input {
        public uint type;
        public InputUnion U;
    }

    public static class ForegroundWindow {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        public static extern uint MapVirtualKey(uint uCode, uint uMapType);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetClientRect(IntPtr hWnd, out Rect lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ClientToScreen(IntPtr hWnd, ref Point lpPoint);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    }
}
"@
    }
}

function Get-ForegroundWindowHandle {
    Ensure-YuneWindowsForegroundWindowType
    return [YuneWindowsWindows.ForegroundWindow]::GetForegroundWindow()
}

function Get-YuneWindowsWindowProcessId {
    param([Parameter(Mandatory = $true)][IntPtr]$Window)

    Ensure-YuneWindowsForegroundWindowType
    if ($Window -eq [IntPtr]::Zero) {
        return 0
    }

    $ProcessId = [uint32]0
    [void][YuneWindowsWindows.ForegroundWindow]::GetWindowThreadProcessId($Window, [ref]$ProcessId)
    return [int]$ProcessId
}

function Get-YuneWindowsWindowTitle {
    param([Parameter(Mandatory = $true)][IntPtr]$Window)

    Ensure-YuneWindowsForegroundWindowType
    if ($Window -eq [IntPtr]::Zero) {
        return ""
    }

    $Length = [YuneWindowsWindows.ForegroundWindow]::GetWindowTextLength($Window)
    if ($Length -le 0) {
        return ""
    }

    $Builder = [System.Text.StringBuilder]::new($Length + 1)
    [void][YuneWindowsWindows.ForegroundWindow]::GetWindowText($Window, $Builder, $Builder.Capacity)
    return $Builder.ToString()
}

function Wait-YuneWindowsWindowTitle {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Window,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [string]$Context = "Window title",
        [int]$TimeoutMs = 5000
    )

    if ($Window -eq [IntPtr]::Zero) {
        throw "$Context cannot wait on a zero window handle."
    }

    $LastTitle = ""
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $LastTitle = Get-YuneWindowsWindowTitle -Window $Window
        if ($LastTitle -match $Pattern) {
            return $LastTitle
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)

    throw "$Context did not report expected title pattern '$Pattern' before timeout. Last title: '$LastTitle'"
}

function Get-ForegroundProcessId {
    $Window = Get-ForegroundWindowHandle
    return Get-YuneWindowsWindowProcessId -Window $Window
}

function Get-YuneWindowsTopLevelWindows {
    Ensure-YuneWindowsForegroundWindowType

    $Windows = [System.Collections.Generic.List[object]]::new()
    $Callback = [YuneWindowsWindows.EnumWindowsProc] {
        param([IntPtr]$Window, [IntPtr]$Param)

        if (-not [YuneWindowsWindows.ForegroundWindow]::IsWindowVisible($Window)) {
            return $true
        }

        $ProcessId = Get-YuneWindowsWindowProcessId -Window $Window
        if ($ProcessId -le 0) {
            return $true
        }

        $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        $Windows.Add([pscustomobject]@{
                handle = $Window
                process_id = $ProcessId
                process_name = if ($Process) { $Process.ProcessName } else { "" }
                title = Get-YuneWindowsWindowTitle -Window $Window
            }) | Out-Null
        return $true
    }

    [void][YuneWindowsWindows.ForegroundWindow]::EnumWindows($Callback, [IntPtr]::Zero)
    return @($Windows)
}

function New-YuneWindowsKeyboardInput {
    param(
        [int]$VirtualKey = 0,
        [int]$ScanCode = 0,
        [uint32]$Flags = 0
    )

    Ensure-YuneWindowsForegroundWindowType
    $KeyboardInput = [YuneWindowsWindows.KeyboardInput]::new()
    $KeyboardInput.wVk = [uint16]$VirtualKey
    $KeyboardInput.wScan = [uint16]$ScanCode
    $KeyboardInput.dwFlags = $Flags
    $KeyboardInput.time = 0
    $KeyboardInput.dwExtraInfo = [UIntPtr]::Zero

    $InputUnion = [YuneWindowsWindows.InputUnion]::new()
    $InputUnion.ki = $KeyboardInput

    $Input = [YuneWindowsWindows.Input]::new()
    $Input.type = 1
    $Input.U = $InputUnion
    return $Input
}

function Send-YuneWindowsVirtualKey {
    param(
        [Parameter(Mandatory = $true)]
        [int]$VirtualKey,
        [string]$Context = "Text smoke",
        [int]$DelayMs = 50
    )

    Ensure-YuneWindowsForegroundWindowType
    if ($VirtualKey -lt 1 -or $VirtualKey -gt 255) {
        throw "$Context virtual key must be in byte range: $VirtualKey"
    }

    $ScanCode = [byte]([YuneWindowsWindows.ForegroundWindow]::MapVirtualKey([uint32]$VirtualKey, 0) -band 0xff)
    $Inputs = [YuneWindowsWindows.Input[]]::new(2)
    $Inputs[0] = New-YuneWindowsKeyboardInput -VirtualKey 0 -ScanCode $ScanCode -Flags 0x0008
    $Inputs[1] = New-YuneWindowsKeyboardInput -VirtualKey 0 -ScanCode $ScanCode -Flags (0x0008 -bor 2)
    $InputSize = [System.Runtime.InteropServices.Marshal]::SizeOf([YuneWindowsWindows.Input]::new())
    $SentInputCount = [YuneWindowsWindows.ForegroundWindow]::SendInput([uint32]$Inputs.Length, $Inputs, $InputSize)
    if ($SentInputCount -ne $Inputs.Length) {
        $LastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Context SendInput sent $SentInputCount of $($Inputs.Length) keyboard events for virtual key $VirtualKey (last error $LastError)."
    }
    Start-Sleep -Milliseconds $DelayMs
}

function Send-YuneWindowsAsciiText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [string]$Context = "Text smoke"
    )

    foreach ($Character in $Text.ToCharArray()) {
        if (($Character -ge [char]'a' -and $Character -le [char]'z') -or
            ($Character -ge [char]'A' -and $Character -le [char]'Z')) {
            $VirtualKey = [int][char]::ToUpperInvariant($Character)
            Send-YuneWindowsVirtualKey -VirtualKey $VirtualKey -Context $Context
            continue
        }
        throw "$Context can only type ASCII letters through virtual-key input: $Character"
    }
}

function Invoke-YuneWindowsClientClick {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Window,
        [int]$ClientX = 160,
        [int]$ClientY = 180,
        [string]$Context = "Text smoke"
    )

    Ensure-YuneWindowsForegroundWindowType
    if ($Window -eq [IntPtr]::Zero) {
        throw "$Context cannot click a zero window handle."
    }

    $Rect = [YuneWindowsWindows.Rect]::new()
    if (-not [YuneWindowsWindows.ForegroundWindow]::GetClientRect($Window, [ref]$Rect)) {
        throw "$Context could not read the target window client area."
    }

    $Width = [Math]::Max(1, $Rect.Right - $Rect.Left)
    $Height = [Math]::Max(1, $Rect.Bottom - $Rect.Top)
    $X = [Math]::Min([Math]::Max(8, $ClientX), [Math]::Max(8, $Width - 8))
    $Y = [Math]::Min([Math]::Max(8, $ClientY), [Math]::Max(8, $Height - 8))
    $Point = [YuneWindowsWindows.Point]::new()
    $Point.X = $X
    $Point.Y = $Y
    if (-not [YuneWindowsWindows.ForegroundWindow]::ClientToScreen($Window, [ref]$Point)) {
        throw "$Context could not translate target click coordinates."
    }

    [void][YuneWindowsWindows.ForegroundWindow]::SetCursorPos($Point.X, $Point.Y)
    Start-Sleep -Milliseconds 80
    [YuneWindowsWindows.ForegroundWindow]::mouse_event(0x0002, [uint32]$Point.X, [uint32]$Point.Y, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [YuneWindowsWindows.ForegroundWindow]::mouse_event(0x0004, [uint32]$Point.X, [uint32]$Point.Y, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
}

function Get-ProcessAncestorIds {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $Ancestors = [System.Collections.Generic.List[int]]::new()
    $Seen = [System.Collections.Generic.HashSet[int]]::new()
    $CurrentProcessId = $ProcessId

    while ($CurrentProcessId -gt 0 -and $Seen.Add($CurrentProcessId)) {
        $Process = Get-CimInstance Win32_Process -Filter "ProcessId = $CurrentProcessId" -ErrorAction SilentlyContinue
        if ($null -eq $Process -or $null -eq $Process.ParentProcessId) {
            break
        }

        $ParentProcessId = [int]$Process.ParentProcessId
        if ($ParentProcessId -le 0) {
            break
        }

        $Ancestors.Add($ParentProcessId)
        $CurrentProcessId = $ParentProcessId
    }

    return @($Ancestors)
}

function Get-ProcessChildIds {
    param([Parameter(Mandatory = $true)][int]$ParentProcessId)

    $Children = [System.Collections.Generic.List[int]]::new()
    $Queue = [System.Collections.Generic.Queue[int]]::new()
    $Seen = [System.Collections.Generic.HashSet[int]]::new()
    $Queue.Enqueue($ParentProcessId)
    [void]$Seen.Add($ParentProcessId)

    while ($Queue.Count -gt 0) {
        $CurrentParentId = $Queue.Dequeue()
        $ChildProcesses = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $CurrentParentId" -ErrorAction SilentlyContinue)
        foreach ($ChildProcess in $ChildProcesses) {
            $ChildProcessId = [int]$ChildProcess.ProcessId
            if ($ChildProcessId -le 0 -or -not $Seen.Add($ChildProcessId)) {
                continue
            }
            $Children.Add($ChildProcessId)
            $Queue.Enqueue($ChildProcessId)
        }
    }

    return @($Children)
}

function Wait-YuneWindowsProcessExit {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [int]$TimeoutSeconds = 5,
        [switch]$RequireExit
    )

    try {
        Wait-Process -Id $ProcessId -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
    }
    catch {
    }

    $Remaining = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($Remaining -and -not $Remaining.HasExited) {
        $Message = "process $ProcessId did not exit within $TimeoutSeconds seconds after stop request"
        if ($RequireExit) {
            throw $Message
        }
        Write-Warning $Message
    }
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $CleanupErrors = [System.Collections.Generic.List[string]]::new()
    $ProcessIds = @(Get-ProcessChildIds -ParentProcessId $ProcessId)
    [array]::Reverse($ProcessIds)
    $ProcessIds += $ProcessId

    foreach ($Id in $ProcessIds) {
        try {
            $Process = Get-Process -Id $Id -ErrorAction SilentlyContinue
            if ($Process -and -not $Process.HasExited) {
                Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue
                Wait-YuneWindowsProcessExit -ProcessId $Id -RequireExit
            }
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }

    if ($CleanupErrors.Count -gt 0) {
        throw "process tree cleanup failed: $($CleanupErrors -join '; ')"
    }
}

function Stop-ProcessesUsingPathInCommandLine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $MatchingProcessIds = Get-YuneWindowsProcessIdsUsingPathInCommandLine -Path $Path
    $CleanupErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($ProcessId in $MatchingProcessIds) {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
            Wait-YuneWindowsProcessExit -ProcessId $ProcessId -RequireExit
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }

    if ($CleanupErrors.Count -gt 0) {
        throw "profile process cleanup failed: $($CleanupErrors -join '; ')"
    }
}

function Remove-YuneWindowsPathWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Context = "Path cleanup",
        [int]$Attempts = 12,
        [int]$DelayMs = 250
    )

    $LastError = ""
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force
            if (-not (Test-Path -LiteralPath $Path)) {
                return
            }
        }
        catch {
            $LastError = $_.Exception.Message
        }
        if ($Attempt -lt $Attempts) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    if ([string]::IsNullOrWhiteSpace($LastError)) {
        throw "$Context failed to remove path after $Attempts attempts: $Path"
    }
    throw "$Context failed to remove path after $Attempts attempts: $Path ($LastError)"
}

function Get-YuneWindowsProcessIdsUsingPathInCommandLine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $PathNeedles = [System.Collections.Generic.List[string]]::new()
    foreach ($Candidate in @($Path, $FullPath)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
            $Normalized = [System.IO.Path]::GetFullPath($Candidate).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar)
            if (-not [string]::IsNullOrWhiteSpace($Normalized)) {
                $PathNeedles.Add($Normalized) | Out-Null
                $PathNeedles.Add($Normalized.Replace('\', '/')) | Out-Null
            }
        }
    }
    if (Test-Path -LiteralPath $FullPath) {
        try {
            $ResolvedPath = [System.IO.Path]::GetFullPath(
                (Resolve-Path -LiteralPath $FullPath).Path).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar)
            $PathNeedles.Add($ResolvedPath) | Out-Null
            $PathNeedles.Add($ResolvedPath.Replace('\', '/')) | Out-Null
        }
        catch {
        }
        try {
            $FileSystemObject = New-Object -ComObject Scripting.FileSystemObject
            $ShortPath = ""
            if (Test-Path -LiteralPath $FullPath -PathType Container) {
                $ShortPath = [string]$FileSystemObject.GetFolder($FullPath).ShortPath
            }
            elseif (Test-Path -LiteralPath $FullPath -PathType Leaf) {
                $ShortPath = [string]$FileSystemObject.GetFile($FullPath).ShortPath
            }
            if (-not [string]::IsNullOrWhiteSpace($ShortPath)) {
                $ShortPath = [System.IO.Path]::GetFullPath($ShortPath).TrimEnd(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar)
                $PathNeedles.Add($ShortPath) | Out-Null
                $PathNeedles.Add($ShortPath.Replace('\', '/')) | Out-Null
            }
        }
        catch {
        }
    }
    $Needles = @($PathNeedles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $CurrentProcessId = [int]$PID
    $MatchingProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $CandidateProcessId = [int]$_.ProcessId
            $CommandLine = [string]$_.CommandLine
            $CommandLineMatchesPath = $false
            foreach ($Needle in $Needles) {
                if ($CommandLine.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $CommandLineMatchesPath = $true
                    break
                }
            }
            $CandidateProcessId -gt 0 -and
                $CandidateProcessId -ne $CurrentProcessId -and
                (-not [string]::IsNullOrWhiteSpace($CommandLine)) -and
                $CommandLineMatchesPath
        })

    $ProcessIds = [System.Collections.Generic.List[int]]::new()
    foreach ($Process in $MatchingProcesses) {
        $ProcessId = [int]$Process.ProcessId
        $ProcessIds.Add($ProcessId)
        foreach ($ChildProcessId in @(Get-ProcessChildIds -ParentProcessId $ProcessId)) {
            $ProcessIds.Add([int]$ChildProcessId)
        }
    }

    return @($ProcessIds | Sort-Object -Unique)
}

function Stop-YuneWindowsNotepadSmokeProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [DateTime]$StartedAfter
    )

    $CleanupErrors = [System.Collections.Generic.List[string]]::new()
    $Cutoff = $StartedAfter.AddSeconds(-5)
    $Processes = @(Get-Process -Name "notepad" -ErrorAction SilentlyContinue | Where-Object {
            try {
                $_.StartTime -ge $Cutoff
            }
            catch {
                $false
            }
        })

    foreach ($Process in $Processes) {
        try {
            if (-not $Process.HasExited) {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                Wait-YuneWindowsProcessExit -ProcessId $Process.Id -RequireExit
            }
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }

    if ($CleanupErrors.Count -gt 0) {
        throw "Notepad smoke process cleanup failed: $($CleanupErrors -join '; ')"
    }
}

function Stop-YuneWindowsLiveSmokeHostProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [DateTime]$StartedAfter,
        [string]$ChromiumProfileRoot = ""
    )

    $CleanupErrors = [System.Collections.Generic.List[string]]::new()
    try {
        Stop-YuneWindowsNotepadSmokeProcesses -StartedAfter $StartedAfter
    }
    catch {
        $CleanupErrors.Add($_.Exception.Message)
    }

    $ProcessIds = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($Process in @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue)) {
        [void]$ProcessIds.Add([int]$Process.Id)
    }

    if (-not [string]::IsNullOrWhiteSpace($ChromiumProfileRoot)) {
        foreach ($ProcessId in @(Get-YuneWindowsProcessIdsUsingPathInCommandLine -Path $ChromiumProfileRoot)) {
            [void]$ProcessIds.Add([int]$ProcessId)
        }
    }

    foreach ($Window in @(Get-YuneWindowsTopLevelWindows)) {
        $ProcessName = [string]$Window.process_name
        $Title = [string]$Window.title
        if (($ProcessName -match '^(msedge|chrome)$' -and $Title -match 'YuneWindows Chromium Smoke') -or
            ($ProcessName -ieq "ApplicationFrameHost" -and $Title -match '(?i)notepad')) {
            [void]$ProcessIds.Add([int]$Window.process_id)
        }
    }

    foreach ($ProcessId in @($ProcessIds | Sort-Object)) {
        try {
            $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($Process -and -not $Process.HasExited) {
                Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
                Wait-YuneWindowsProcessExit -ProcessId $ProcessId -RequireExit
            }
        }
        catch {
            $CleanupErrors.Add($_.Exception.Message)
        }
    }

    if ($CleanupErrors.Count -gt 0) {
        throw "live smoke host process cleanup failed: $($CleanupErrors -join '; ')"
    }
}

function Assert-ForegroundProcess {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,
        [string]$Context = "Target app",
        [int]$TimeoutMs = 3000,
        [switch]$AllowDescendantProcess
    )

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $ForegroundProcessId = Get-ForegroundProcessId
        if ($ForegroundProcessId -eq $ProcessId) {
            return
        }
        if ($AllowDescendantProcess) {
            $AncestorIds = @(Get-ProcessAncestorIds -ProcessId $ForegroundProcessId)
            if ($AncestorIds -contains $ProcessId) {
                return
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)

    $ActualProcessId = Get-ForegroundProcessId
    if ($AllowDescendantProcess) {
        throw "$Context did not have foreground focus before typing. Expected process id $ProcessId or descendant foreground process, actual foreground process id $ActualProcessId."
    }
    throw "$Context did not have foreground focus before typing. Expected process id $ProcessId, actual foreground process id $ActualProcessId."
}

function Assert-ForegroundWindowHandle {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Window,
        [string]$Context = "Target app",
        [int]$TimeoutMs = 3000
    )

    if ($Window -eq [IntPtr]::Zero) {
        throw "$Context foreground window handle is empty."
    }

    $ExpectedProcessId = Get-YuneWindowsWindowProcessId -Window $Window
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $ForegroundWindow = Get-ForegroundWindowHandle
        if ($ForegroundWindow -eq $Window) {
            return
        }

        $ForegroundProcessId = Get-ForegroundProcessId
        if ($ExpectedProcessId -gt 0 -and $ForegroundProcessId -eq $ExpectedProcessId) {
            return
        }

        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)

    $ActualProcessId = Get-ForegroundProcessId
    throw "$Context did not have foreground focus before typing. Expected window process id $ExpectedProcessId, actual foreground process id $ActualProcessId."
}

function Wait-YuneWindowsMainWindowHandle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutMs = 10000
    )

    try {
        [void]$Process.WaitForInputIdle([Math]::Min($TimeoutMs, 5000))
    }
    catch {
    }

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $Process.Refresh()
        if ($Process.HasExited) {
            return [IntPtr]::Zero
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $Deadline)

    return [IntPtr]::Zero
}

function Set-YuneWindowsForegroundWindowHandle {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Window,
        [object]$Shell = $null,
        [int]$TimeoutMs = 10000
    )

    if ($Window -eq [IntPtr]::Zero) {
        return $false
    }

    $ProcessId = Get-YuneWindowsWindowProcessId -Window $Window
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        [void][YuneWindowsWindows.ForegroundWindow]::ShowWindow($Window, 9)
        [void][YuneWindowsWindows.ForegroundWindow]::BringWindowToTop($Window)
        [void][YuneWindowsWindows.ForegroundWindow]::SetForegroundWindow($Window)
        if ($null -ne $Shell -and $ProcessId -gt 0) {
            try {
                [void]$Shell.AppActivate($ProcessId)
            }
            catch {
            }
        }

        $ForegroundWindow = Get-ForegroundWindowHandle
        if ($ForegroundWindow -eq $Window) {
            return $true
        }
        $ForegroundProcessId = Get-ForegroundProcessId
        if ($ProcessId -gt 0 -and $ForegroundProcessId -eq $ProcessId) {
            return $true
        }
        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $Deadline)

    return $false
}

function Set-YuneWindowsForegroundProcess {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [object]$Shell = $null,
        [int]$TimeoutMs = 10000,
        [switch]$AllowDescendantProcess
    )

    $Window = Wait-YuneWindowsMainWindowHandle -Process $Process -TimeoutMs $TimeoutMs
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $Process.Refresh()
        if ($Process.HasExited) {
            return $false
        }
        if ($Window -eq [IntPtr]::Zero -and $Process.MainWindowHandle -ne [IntPtr]::Zero) {
            $Window = $Process.MainWindowHandle
        }
        if ($Window -ne [IntPtr]::Zero) {
            [void][YuneWindowsWindows.ForegroundWindow]::ShowWindow($Window, 9)
            [void][YuneWindowsWindows.ForegroundWindow]::BringWindowToTop($Window)
            [void][YuneWindowsWindows.ForegroundWindow]::SetForegroundWindow($Window)
        }
        if ($null -ne $Shell) {
            try {
                [void]$Shell.AppActivate($Process.Id)
            }
            catch {
            }
        }

        $ForegroundProcessId = Get-ForegroundProcessId
        if ($ForegroundProcessId -eq $Process.Id) {
            return $true
        }
        if ($AllowDescendantProcess) {
            $AncestorIds = @(Get-ProcessAncestorIds -ProcessId $ForegroundProcessId)
            if ($AncestorIds -contains $Process.Id) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $Deadline)

    return $false
}

function Set-YuneWindowsForegroundNotepadWindow {
    param(
        [Parameter(Mandatory = $true)]
        [DateTime]$StartedAfter,
        [object]$Shell = $null,
        [int]$TimeoutMs = 15000
    )

    $Cutoff = $StartedAfter.AddSeconds(-5)
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $Windows = @(Get-YuneWindowsTopLevelWindows | Where-Object {
                $ProcessName = [string]$_.process_name
                $Title = [string]$_.title
                $MatchesNotepadWindow = $false
                if ($ProcessName -ieq "notepad") {
                    try {
                        $Process = Get-Process -Id ([int]$_.process_id) -ErrorAction Stop
                        $MatchesNotepadWindow = $Process.StartTime -ge $Cutoff
                    }
                    catch {
                        $MatchesNotepadWindow = $true
                    }
                }
                elseif ($Title -match '(?i)notepad') {
                    $MatchesNotepadWindow = $true
                }
                $MatchesNotepadWindow
            } | Sort-Object `
            @{ Expression = { if ([string]::IsNullOrWhiteSpace([string]$_.title)) { 1 } else { 0 } }; Ascending = $true },
            @{ Expression = { [int]$_.process_id }; Ascending = $false })

        foreach ($Window in $Windows) {
            if (Set-YuneWindowsForegroundWindowHandle -Window $Window.handle -Shell $Shell -TimeoutMs 1000) {
                return [pscustomobject]@{
                    focused = $true
                    process_id = [int]$Window.process_id
                    window_handle = $Window.handle
                    title = [string]$Window.title
                }
            }
        }

        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $Deadline)

    return [pscustomobject]@{
        focused = $false
        process_id = 0
        window_handle = [IntPtr]::Zero
        title = ""
    }
}

function Set-YuneWindowsForegroundChromiumWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)]
        [string]$ProfileRoot,
        [object]$Shell = $null,
        [int]$TimeoutMs = 15000
    )

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        $TargetProcessIds = [System.Collections.Generic.HashSet[int]]::new()
        try {
            $Process.Refresh()
            if (-not $Process.HasExited) {
                [void]$TargetProcessIds.Add($Process.Id)
                foreach ($ChildProcessId in @(Get-ProcessChildIds -ParentProcessId $Process.Id)) {
                    [void]$TargetProcessIds.Add([int]$ChildProcessId)
                }
            }
        }
        catch {
        }

        foreach ($ProfileProcessId in @(Get-YuneWindowsProcessIdsUsingPathInCommandLine -Path $ProfileRoot)) {
            [void]$TargetProcessIds.Add([int]$ProfileProcessId)
        }

        $Windows = @(Get-YuneWindowsTopLevelWindows | Where-Object {
                $ProcessId = [int]$_.process_id
                $ProcessName = [string]$_.process_name
                $Title = [string]$_.title
                $TargetProcessIds.Contains($ProcessId) -or
                    (($ProcessName -match '^(msedge|chrome)$') -and
                        ($Title -match 'YuneWindows Chromium Smoke'))
            } | Sort-Object `
            @{ Expression = { if ([string]::IsNullOrWhiteSpace([string]$_.title)) { 1 } else { 0 } }; Ascending = $true },
            @{ Expression = { [int]$_.process_id }; Ascending = $false })

        foreach ($Window in $Windows) {
            if (Set-YuneWindowsForegroundWindowHandle -Window $Window.handle -Shell $Shell -TimeoutMs 1000) {
                return [pscustomobject]@{
                    focused = $true
                    process_id = [int]$Window.process_id
                    window_handle = $Window.handle
                    title = [string]$Window.title
                }
            }
        }

        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $Deadline)

    return [pscustomobject]@{
        focused = $false
        process_id = 0
        window_handle = [IntPtr]::Zero
        title = ""
    }
}

function Minimize-YuneWindowsCurrentProcessWindow {
    try {
        [void](Get-ForegroundProcessId)
        $Process = Get-Process -Id $PID -ErrorAction SilentlyContinue
        if ($Process -and $Process.MainWindowHandle -ne [IntPtr]::Zero) {
            [void][YuneWindowsWindows.ForegroundWindow]::ShowWindow($Process.MainWindowHandle, 6)
        }
    }
    catch {
    }
}

function Find-ChromiumBrowserPath {
    param([string]$RequestedPath = "")

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-ConcreteChromiumBrowserPath -PathValue $RequestedPath)) {
            throw "Requested -BrowserPath must provide a concrete Chromium browser path: an absolute .exe path, not a placeholder."
        }
        $RequestedBrowserPath = [System.IO.Path]::GetFullPath($RequestedPath)
        if (-not (Test-Path -LiteralPath $RequestedBrowserPath -PathType Leaf)) {
            throw "Requested -BrowserPath must provide a concrete Chromium browser path: an existing absolute .exe path."
        }
        Assert-YuneWindowsChromiumBrowserArchitecture `
            -Path $RequestedBrowserPath `
            -Source "Requested -BrowserPath"
        return $RequestedBrowserPath
    }

    $Candidates = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")
    )
    foreach ($Candidate in $Candidates) {
        if ($Candidate -and
            (Test-Path -LiteralPath $Candidate) -and
            (Test-YuneWindowsChromiumBrowserArchitecture -Path $Candidate)) {
            return [System.IO.Path]::GetFullPath($Candidate)
        }
    }
    return $null
}

function Get-YuneWindowsPortableExecutableMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Executable does not exist: $Path"
    }

    $Stream = [System.IO.File]::Open(
        [System.IO.Path]::GetFullPath($Path),
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $Reader = [System.IO.BinaryReader]::new($Stream)
        try {
            if ($Stream.Length -lt 0x40) {
                return "unknown"
            }
            if ($Reader.ReadByte() -ne [byte][char]'M' -or
                $Reader.ReadByte() -ne [byte][char]'Z') {
                return "unknown"
            }
            $Stream.Position = 0x3c
            $PeOffset = $Reader.ReadInt32()
            if ($PeOffset -lt 0 -or ($PeOffset + 6) -gt $Stream.Length) {
                return "unknown"
            }
            $Stream.Position = $PeOffset
            if ($Reader.ReadByte() -ne [byte][char]'P' -or
                $Reader.ReadByte() -ne [byte][char]'E' -or
                $Reader.ReadByte() -ne 0 -or
                $Reader.ReadByte() -ne 0) {
                return "unknown"
            }
            $Machine = $Reader.ReadUInt16()
            switch ($Machine) {
                0x8664 { return "x64" }
                0x014c { return "x86" }
                0xaa64 { return "arm64" }
                default { return ("0x{0:x4}" -f $Machine) }
            }
        }
        finally {
            $Reader.Dispose()
        }
    }
    finally {
        $Stream.Dispose()
    }
}

function Test-YuneWindowsChromiumBrowserArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return (Get-YuneWindowsPortableExecutableMachine -Path $Path) -eq "x64"
    }
    catch {
        return $false
    }
}

function Assert-YuneWindowsChromiumBrowserArchitecture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Source = "Chromium browser path"
    )

    $Machine = Get-YuneWindowsPortableExecutableMachine -Path $Path
    if ($Machine -ne "x64") {
        throw "$Source must point at an x64 Chromium browser for the current x64 YuneWindows TSF shell; observed PE machine: $Machine."
    }
}

function Test-ConcreteChromiumBrowserPath {
    param([object]$PathValue)

    if (($null -eq $PathValue) -or (-not ($PathValue -is [string]))) {
        return $false
    }

    $Candidate = $PathValue.Trim()
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $false
    }
    if (($Candidate -match '^<.*>$') -or
        ($Candidate -match '[<>"|?*]')) {
        return $false
    }
    if (-not [System.IO.Path]::IsPathRooted($Candidate)) {
        return $false
    }
    if ([System.IO.Path]::GetExtension($Candidate) -ine ".exe") {
        return $false
    }

    return $true
}

function Assert-ConcreteChromiumBrowserPath {
    param(
        [object]$PathValue,
        [string]$Source = "Chromium browser path"
    )

    if (-not (Test-ConcreteChromiumBrowserPath -PathValue $PathValue)) {
        throw "$Source must provide a concrete Chromium browser path: an absolute .exe path, not a placeholder."
    }
}

function New-M01PreflightReport {
    param(
        [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
        [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
        [string]$BrowserPath = "",
        [bool]$RequireBrowser = $false,
        [string]$CurrentResiduePath = "",
        [switch]$RefreshCurrentResidue,
        [string]$ApprovalNote = ""
    )

    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $PackageDir = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist"
    $RimeDll = Join-Path $PackageDir "lib\rime.dll"
    $SchemaSource = Join-Path $YuneRoot "apps\yune-web\public\schema"
    $ResolvedBrowser = Find-ChromiumBrowserPath -RequestedPath $BrowserPath
    $InstallRoot = [System.IO.Path]::GetFullPath($InstallDir)
    $InstallDirExists = Test-Path -LiteralPath $InstallRoot
    $ServerProcesses = @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue)
    if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath)) {
        $CurrentResiduePath = [System.IO.Path]::GetFullPath($CurrentResiduePath)
        if (-not (Test-Path -LiteralPath $CurrentResiduePath)) {
            throw "Missing preflight current-residue evidence: $CurrentResiduePath"
        }
        $MachineResidue = Get-Content -Raw -LiteralPath $CurrentResiduePath | ConvertFrom-Json
        $MachineResidueSource = $CurrentResiduePath
    }
    elseif ($RefreshCurrentResidue.IsPresent) {
        Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote
        $RefreshedResidue = Get-YuneWindowsMachineResidue -InstallDir $InstallRoot
        $MachineResidue = [pscustomobject]([ordered]@{
                machine_state_checked = $true
                machine_state_issues = @($RefreshedResidue.machine_state_issues)
                filesystem_leftovers = @($RefreshedResidue.filesystem_leftovers)
            })
        $MachineResidueSource = "Get-YuneWindowsMachineResidue"
    }
    else {
        throw "Preflight machine-state inspection requires -CurrentResiduePath or -RefreshCurrentResidue."
    }
    $MachineStateChecked = Get-RequiredJsonBooleanProperty `
        -Object $MachineResidue `
        -Name "machine_state_checked" `
        -Context "preflight current-residue evidence"
    $MachineStateIssues = @($MachineResidue.machine_state_issues)
    $FilesystemLeftovers = @($MachineResidue.filesystem_leftovers)
    $NoMachineResidue = $MachineStateChecked -and
        $MachineStateIssues.Count -eq 0 -and
        $FilesystemLeftovers.Count -eq 0

    $Checks = [ordered]@{
        yune_runtime_exists = Test-Path -LiteralPath $RimeDll
        yune_schema_exists = Test-Path -LiteralPath $SchemaSource
        tsf_source_exists = Test-Path -LiteralPath (Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp")
        server_source_exists = Test-Path -LiteralPath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")
        build_script_exists = Test-Path -LiteralPath (Join-Path $RepoRoot "tools\build-tsf-shell.ps1")
        install_dir_clean = -not $InstallDirExists
        no_server_processes = @($ServerProcesses).Count -eq 0
        no_machine_residue = $NoMachineResidue
        is_administrator = Test-IsAdministrator
        is_sta = [Threading.Thread]::CurrentThread.ApartmentState -eq "STA"
        browser_available = $null -ne $ResolvedBrowser
    }

    $Ready = $Checks.yune_runtime_exists -and
        $Checks.yune_schema_exists -and
        $Checks.tsf_source_exists -and
        $Checks.server_source_exists -and
        $Checks.build_script_exists -and
        $Checks.install_dir_clean -and
        $Checks.no_server_processes -and
        $Checks.no_machine_residue -and
        $Checks.is_administrator
    if ($RequireBrowser) {
        $Ready = $Ready -and $Checks.is_sta -and $Checks.browser_available
    }

    return [ordered]@{
        generated_at = (Get-Date).ToString("o")
        machine_state_changed = $false
        machine_state_checked = $MachineStateChecked
        machine_residue_source = $MachineResidueSource
        machine_state_issues = $MachineStateIssues
        filesystem_leftovers = $FilesystemLeftovers
        ready_for_live_smoke = [bool]$Ready
        install_dir = $InstallRoot
        install_dir_exists = $InstallDirExists
        server_process_count = @($ServerProcesses).Count
        yune_root = [System.IO.Path]::GetFullPath($YuneRoot)
        yune_runtime_path = $RimeDll
        yune_schema_path = $SchemaSource
        browser_path = $ResolvedBrowser
        yune_runtime_exists = $Checks.yune_runtime_exists
        yune_schema_exists = $Checks.yune_schema_exists
        tsf_source_exists = $Checks.tsf_source_exists
        server_source_exists = $Checks.server_source_exists
        build_script_exists = $Checks.build_script_exists
        is_administrator = $Checks.is_administrator
        is_sta = $Checks.is_sta
        browser_available = $Checks.browser_available
    }
}

function Assert-M01PreflightReady {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [string]$Context = "M01 live preflight"
    )

    $Issues = [System.Collections.Generic.List[string]]::new()
    foreach ($RequiredProperty in @(
            "ready_for_live_smoke",
            "machine_state_changed",
            "machine_state_checked",
            "machine_state_issues",
            "filesystem_leftovers",
            "install_dir_exists",
            "server_process_count",
            "yune_runtime_exists",
            "yune_schema_exists",
            "tsf_source_exists",
            "server_source_exists",
            "build_script_exists",
            "is_administrator",
            "is_sta",
            "browser_available",
            "browser_path"
        )) {
        if (-not $Report.PSObject.Properties.Name.Contains($RequiredProperty)) {
            $Issues.Add("$RequiredProperty missing")
        }
    }

    $ExpectedBooleanProperties = [ordered]@{
        ready_for_live_smoke = $true
        machine_state_changed = $false
        machine_state_checked = $true
        install_dir_exists = $false
        yune_runtime_exists = $true
        yune_schema_exists = $true
        tsf_source_exists = $true
        server_source_exists = $true
        build_script_exists = $true
        is_administrator = $true
        is_sta = $true
        browser_available = $true
    }
    foreach ($Name in $ExpectedBooleanProperties.Keys) {
        if (-not $Report.PSObject.Properties.Name.Contains($Name)) {
            continue
        }
        $Value = $Report.PSObject.Properties[$Name].Value
        if ($Value -isnot [bool]) {
            $Issues.Add("$Name must be a JSON boolean")
            continue
        }
        $Expected = $ExpectedBooleanProperties[$Name]
        if ($Value -ne $Expected) {
            $Suffix = if ($Expected) { "false" } else { "true" }
            $Issues.Add("$Name=$Suffix")
        }
    }

    if ($Report.PSObject.Properties.Name.Contains("browser_path")) {
        try {
            Assert-ConcreteChromiumBrowserPath `
                -PathValue $Report.PSObject.Properties["browser_path"].Value `
                -Source "$Context browser_path"
            $ResolvedBrowserPath = [System.IO.Path]::GetFullPath(
                [string]$Report.PSObject.Properties["browser_path"].Value)
            if (-not (Test-Path -LiteralPath $ResolvedBrowserPath -PathType Leaf)) {
                $Issues.Add("$Context browser_path must provide a concrete Chromium browser path: an existing absolute .exe path.")
            }
            else {
                Assert-YuneWindowsChromiumBrowserArchitecture `
                    -Path $ResolvedBrowserPath `
                    -Source "$Context browser_path"
            }
        }
        catch {
            $Issues.Add($_.Exception.Message)
        }
    }

    if (@($Report.machine_state_issues).Count -gt 0) {
        $Issues.Add("machine_state_issues present")
    }
    if (@($Report.filesystem_leftovers).Count -gt 0) {
        $Issues.Add("filesystem_leftovers present")
    }
    if ($Report.PSObject.Properties.Name.Contains("server_process_count")) {
        $ServerProcessCount = $Report.PSObject.Properties["server_process_count"].Value
        if ((($ServerProcessCount -isnot [byte]) -and
                ($ServerProcessCount -isnot [int16]) -and
                ($ServerProcessCount -isnot [int]) -and
                ($ServerProcessCount -isnot [long]))) {
            $Issues.Add("server_process_count must be a JSON number")
        }
        elseif ($ServerProcessCount -ne 0) {
            $Issues.Add("server_process_count=$ServerProcessCount")
        }
    }

    if ($Issues.Count -gt 0) {
        throw "$Context is not ready: $($Issues -join '; ')"
    }
}

function Write-M01PreflightReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
        [string]$InstallDir = "$env:LOCALAPPDATA\Yune\WindowsIme",
        [string]$BrowserPath = "",
        [bool]$RequireBrowser = $false,
        [string]$CurrentResiduePath = "",
        [switch]$RefreshCurrentResidue,
        [string]$ApprovalNote = ""
    )

    $ResolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath)) {
        $ResolvedCurrentResiduePath = [System.IO.Path]::GetFullPath($CurrentResiduePath)
        if ([string]::Equals(
                $ResolvedPath,
                $ResolvedCurrentResiduePath,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Preflight output path must not also be the current-residue input: $ResolvedPath"
        }
    }

    $Report = New-M01PreflightReport `
        -YuneRoot $YuneRoot `
        -InstallDir $InstallDir `
        -BrowserPath $BrowserPath `
        -RequireBrowser $RequireBrowser `
        -CurrentResiduePath $CurrentResiduePath `
        -RefreshCurrentResidue:$($RefreshCurrentResidue.IsPresent) `
        -ApprovalNote $ApprovalNote
    New-Item -ItemType Directory -Force (Split-Path -Parent $ResolvedPath) | Out-Null
    $Report | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $ResolvedPath -Encoding utf8
    Write-Output $ResolvedPath
}
