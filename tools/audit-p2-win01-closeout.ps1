param(
    [string]$JsonPath = "",
    [string]$MarkdownPath = "",
    [string]$EvidenceRoot = "",
    [string]$SourceRoot = "",
    [switch]$RequireComplete
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($SourceRoot -eq "") {
    $SourceRoot = $RepoRoot
} else {
    $SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
}
if ($EvidenceRoot -eq "") {
    $EvidenceRoot = Join-Path $RepoRoot "docs\evidence"
} else {
    $EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
}
if ($JsonPath -eq "") {
    $JsonPath = Join-Path $RepoRoot "docs\evidence\p2-win01-closeout\audit.json"
}
if ($MarkdownPath -eq "") {
    $MarkdownPath = Join-Path $RepoRoot "docs\evidence\p2-win01-closeout\audit.md"
}

function Repo-Path([string]$RelativePath) {
    $normalized = $RelativePath -replace '/', '\'
    $evidence_prefix = "docs\evidence\"
    if ($normalized.StartsWith($evidence_prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $EvidenceRoot $normalized.Substring($evidence_prefix.Length)
    }
    return Join-Path $RepoRoot $RelativePath
}

function Has-Path([string]$RelativePath) {
    return Test-Path -LiteralPath (Repo-Path $RelativePath)
}

function Test-ExactEvidencePath([object]$Value, [string]$ExpectedRelativePath) {
    if ($null -eq $Value) {
        return $false
    }

    $Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $NormalizedText = $Text -replace '/', '\'
    if ([string]::Equals(
            $NormalizedText,
            $ExpectedRelativePath,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    try {
        $ExpectedFullPath = [System.IO.Path]::GetFullPath((Repo-Path $ExpectedRelativePath))
        if ([System.IO.Path]::IsPathRooted($Text)) {
            $ActualFullPath = [System.IO.Path]::GetFullPath($Text)
        }
        else {
            $ActualFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Text))
        }
        return [string]::Equals(
            $ActualFullPath,
            $ExpectedFullPath,
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-CleanupPlanEvidencePath([object]$Value) {
    return Test-ExactEvidencePath `
        -Value $Value `
        -ExpectedRelativePath "docs\evidence\p2-win01-installer\machine-cleanup-plan.json"
}

function Get-IsoDateEvidenceValue([string]$RelativePath) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $Lines = @(Get-Content -LiteralPath $Path)
    foreach ($Line in $Lines) {
        $Match = [regex]::Match($Line, '^Date:\s*(?<date>\d{4}-\d{2}-\d{2}T\S+)')
        if (-not $Match.Success) {
            continue
        }

        try {
            return [System.DateTimeOffset]::Parse(
                $Match.Groups["date"].Value,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
        catch {
            return $null
        }
    }

    return $null
}

function Has-IsoDateEvidence([string]$RelativePath) {
    return $null -ne (Get-IsoDateEvidenceValue $RelativePath)
}

function Has-LiveResultDateEvidence([string]$RelativePath) {
    $ResultDate = Get-IsoDateEvidenceValue $RelativePath
    if ($null -eq $ResultDate) {
        return $false
    }

    $ApprovalDate = Get-IsoDateEvidenceValue "docs\evidence\p2-win01-installer\approval.md"
    if ($null -eq $ApprovalDate) {
        return $false
    }

    return $ResultDate -ge $ApprovalDate
}

function Test-StructuralEventText {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)]
        [string]$EventName
    )

    $EscapedEvent = [regex]::Escape($EventName)
    return $Text -match "(^|\s)event=$EscapedEvent(?=\s|$)"
}

function Test-StructuralCandidateUpdateText {
    param(
        [AllowEmptyString()][string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }

    foreach ($Line in @($Text -split "\r?\n")) {
        if (-not (Test-StructuralEventText -Text $Line -EventName "candidate_update")) {
            continue
        }

        $Match = [regex]::Match($Line, "(^|\s)candidate_count=(?<value>\d+)(?=\s|$)")
        if (-not $Match.Success) {
            continue
        }

        $CandidateCount = [int64]0
        if (([int64]::TryParse($Match.Groups["value"].Value, [ref]$CandidateCount)) -and
            ($CandidateCount -gt 0)) {
            return $true
        }
    }

    return $false
}

function Test-DiagnosticsLogContainsTypedContent {
    param(
        [AllowEmptyString()][string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }

    $ApprovedSmokeInput = "ngohaig"
    $ExpectedCommit = -join ([char[]](0x6211, 0x4fc2, 0x500b))
    $TypedContentFieldPattern = '(?i)(^|\s)(input|raw_input|preedit|typed_text|commit|committed|committed_text|candidate_text|text)=[^\s]+'
    return (($Text -match [regex]::Escape($ApprovedSmokeInput)) -or
        ($Text -match [regex]::Escape($ExpectedCommit)) -or
        ($Text -match $TypedContentFieldPattern))
}

function ConvertTo-IsoDateTimeOffset([object]$Value) {
    if ($null -eq $Value) {
        return $null
    }
    $Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return [System.DateTimeOffset]::Parse(
            $Text,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        return $null
    }
}

function File-Contains([string]$RelativePath, [string]$Pattern) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    return [bool](Select-String -Path $Path -Pattern $Pattern -Quiet)
}

function Get-JsonBooleanSchemaIssueNames {
    param(
        [object]$Evidence,
        [string[]]$Names
    )

    $Issues = [System.Collections.Generic.List[string]]::new()
    foreach ($Name in $Names) {
        $Property = $Evidence.PSObject.Properties[$Name]
        if (($null -eq $Property) -or ($Property.Value -isnot [bool])) {
            $Issues.Add($Name) | Out-Null
        }
    }
    return @($Issues)
}

function Get-FirstMatchingLineIndexAfter([string]$RelativePath, [string]$Pattern, [int]$AfterIndex) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return -1
    }
    $Lines = @(Get-Content -LiteralPath $Path)
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Index -le $AfterIndex) {
            continue
        }
        if ($Lines[$Index] -match $Pattern) {
            return $Index
        }
    }
    return -1
}

function Has-OrderedCommandTranscript([string]$RelativePath, [string[]]$Patterns) {
    $PreviousIndex = -1
    foreach ($Pattern in $Patterns) {
        $Index = Get-FirstMatchingLineIndexAfter `
            -RelativePath $RelativePath `
            -Pattern $Pattern `
            -AfterIndex $PreviousIndex
        if ($Index -lt 0) {
            return $false
        }
        $PreviousIndex = $Index
    }
    return $true
}

function Has-NoFailedCommandTranscript([string]$RelativePath) {
    return (-not (File-Contains $RelativePath "^FAIL\s+"))
}

function Has-NoFailedCommandTranscriptBeforeCompletedPatterns([string]$RelativePath, [string[]]$Patterns) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $Lines = @(Get-Content -LiteralPath $Path)
    $PreviousIndex = -1
    foreach ($Pattern in $Patterns) {
        $Index = Get-FirstMatchingLineIndexAfter `
            -RelativePath $RelativePath `
            -Pattern $Pattern `
            -AfterIndex $PreviousIndex
        if ($Index -lt 0) {
            return $false
        }
        $PreviousIndex = $Index
    }

    for ($Index = 0; $Index -le $PreviousIndex; $Index++) {
        if ($Lines[$Index] -match "^FAIL\s+") {
            return $false
        }
    }
    return $true
}

function Get-FailedCommandTranscriptLines([string]$RelativePath) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    return @(Get-Content -LiteralPath $Path | Where-Object { $_ -match "^FAIL\s+" })
}

$GenericApprovalNoteTranscriptPattern = "-ApprovalNote\s+'(?=(?:[^']|'')*[^'\s])(?:[^']|'')+'"
$script:CachedApprovalNoteTranscriptPattern = $null
$script:CachedInstallDirTranscriptPattern = $null
$script:CachedDiagnosticsOutputDirTranscriptPattern = $null
$script:CachedBrowserPathTranscriptPattern = $null
$script:CachedLivePreflightPathTranscriptPattern = $null

function Get-ApprovalEvidenceField {
    param(
        [string]$RelativePath,
        [string]$Name
    )

    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $EscapedName = [regex]::Escape($Name)
    foreach ($Line in @(Get-Content -LiteralPath $Path)) {
        $Match = [regex]::Match($Line, "^$EscapedName\:\s*(?<value>.+)$")
        if (-not $Match.Success) {
            continue
        }

        $Value = $Match.Groups["value"].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $null
        }
        return $Value
    }

    return $null
}

function Test-IsPlaceholderApprovalNote {
    param([string]$ApprovalNote)

    if ([string]::IsNullOrWhiteSpace($ApprovalNote)) {
        return $false
    }

    return $ApprovalNote.Trim() -match '^<current-session(?:\s+cleanup)?\s+approval note>$'
}

function Test-IsConcreteWindowsPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $TrimmedPath = $Path.Trim()
    if ($TrimmedPath -match '^\(') {
        return $false
    }

    return $TrimmedPath -match '^(?:[A-Za-z]:\\|\\\\)'
}

function Test-SameWindowsPath {
    param(
        [string]$First,
        [string]$Second
    )

    if ((-not (Test-IsConcreteWindowsPath -Path $First)) -or
        (-not (Test-IsConcreteWindowsPath -Path $Second))) {
        return $false
    }

    try {
        $FirstFullPath = [System.IO.Path]::GetFullPath($First)
        $SecondFullPath = [System.IO.Path]::GetFullPath($Second)
        return [string]::Equals(
            $FirstFullPath,
            $SecondFullPath,
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-IsConcreteBrowserExecutablePath {
    param([string]$Path)

    if (-not (Test-IsConcreteWindowsPath -Path $Path)) {
        return $false
    }

    $TrimmedPath = $Path.Trim()
    if ($TrimmedPath -match '[<>"|?*]') {
        return $false
    }

    return [System.IO.Path]::GetExtension($TrimmedPath) -ieq ".exe"
}

function Test-ApprovalEvidencePathsAreConcrete {
    param([string]$Evidence)

    foreach ($Name in @("Install dir", "Yune root")) {
        $Value = Get-ApprovalEvidenceField $Evidence $Name
        if (-not (Test-IsConcreteWindowsPath -Path $Value)) {
            return $false
        }
    }

    $BrowserPath = Get-ApprovalEvidenceField $Evidence "Browser path"
    if (-not (Test-IsConcreteBrowserExecutablePath -Path $BrowserPath)) {
        return $false
    }
    try {
        $ResolvedBrowserPath = [System.IO.Path]::GetFullPath($BrowserPath)
    }
    catch {
        return $false
    }
    if (-not (Test-Path -LiteralPath $ResolvedBrowserPath -PathType Leaf)) {
        return $false
    }

    return $true
}

function Get-LiveApprovalField {
    param([string]$Name)

    return Get-ApprovalEvidenceField "docs\evidence\p2-win01-installer\approval.md" $Name
}

function Get-LiveApprovalNote {
    return Get-LiveApprovalField "Approval note"
}

function Get-LiveApprovalInstallDir {
    return Get-LiveApprovalField "Install dir"
}

function Get-LiveApprovalYuneRoot {
    return Get-LiveApprovalField "Yune root"
}

function Get-LiveApprovalBrowserPath {
    return Get-LiveApprovalField "Browser path"
}

function ConvertTo-CommandValuePattern([string]$SwitchName, [string]$Value) {
    $CommandValue = "'" + ($Value -replace "'", "''") + "'"
    return [regex]::Escape($SwitchName) + "\s+" + [regex]::Escape($CommandValue)
}

function Get-ApprovalNoteTranscriptPattern {
    if ($null -ne $script:CachedApprovalNoteTranscriptPattern) {
        return $script:CachedApprovalNoteTranscriptPattern
    }

    $ApprovalNote = Get-LiveApprovalNote
    if ([string]::IsNullOrWhiteSpace($ApprovalNote)) {
        $script:CachedApprovalNoteTranscriptPattern = $GenericApprovalNoteTranscriptPattern
    } else {
        $script:CachedApprovalNoteTranscriptPattern = ConvertTo-CommandValuePattern "-ApprovalNote" $ApprovalNote
    }
    return $script:CachedApprovalNoteTranscriptPattern
}

function Get-InstallDirTranscriptPattern {
    if ($null -ne $script:CachedInstallDirTranscriptPattern) {
        return $script:CachedInstallDirTranscriptPattern
    }

    $InstallDir = Get-LiveApprovalInstallDir
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        $script:CachedInstallDirTranscriptPattern = "-InstallDir"
    } else {
        $script:CachedInstallDirTranscriptPattern = ConvertTo-CommandValuePattern "-InstallDir" $InstallDir
    }
    return $script:CachedInstallDirTranscriptPattern
}

function Get-YuneRootTranscriptPattern {
    if ($null -ne $script:CachedYuneRootTranscriptPattern) {
        return $script:CachedYuneRootTranscriptPattern
    }

    $YuneRoot = Get-LiveApprovalYuneRoot
    if ([string]::IsNullOrWhiteSpace($YuneRoot)) {
        $script:CachedYuneRootTranscriptPattern = "-YuneRoot"
    } else {
        $script:CachedYuneRootTranscriptPattern = ConvertTo-CommandValuePattern "-YuneRoot" $YuneRoot
    }
    return $script:CachedYuneRootTranscriptPattern
}

function Get-BrowserPathTranscriptPattern {
    if ($null -ne $script:CachedBrowserPathTranscriptPattern) {
        return $script:CachedBrowserPathTranscriptPattern
    }

    $BrowserPath = Get-LiveApprovalBrowserPath
    if ([string]::IsNullOrWhiteSpace($BrowserPath)) {
        $script:CachedBrowserPathTranscriptPattern = "-BrowserPath"
    } else {
        $script:CachedBrowserPathTranscriptPattern = ConvertTo-CommandValuePattern "-BrowserPath" $BrowserPath
    }
    return $script:CachedBrowserPathTranscriptPattern
}

function Get-DiagnosticsOutputDirTranscriptPattern {
    if ($null -ne $script:CachedDiagnosticsOutputDirTranscriptPattern) {
        return $script:CachedDiagnosticsOutputDirTranscriptPattern
    }

    $DiagnosticsOutputDir = Repo-Path "docs\evidence\p2-win01-settings\registered-session-diagnostics"
    $script:CachedDiagnosticsOutputDirTranscriptPattern = ConvertTo-CommandValuePattern "-OutputDir" $DiagnosticsOutputDir
    return $script:CachedDiagnosticsOutputDirTranscriptPattern
}

function Get-LivePreflightPathTranscriptPattern {
    if ($null -ne $script:CachedLivePreflightPathTranscriptPattern) {
        return $script:CachedLivePreflightPathTranscriptPattern
    }

    $LivePreflightPath = Repo-Path "docs\evidence\p2-win01-installer\live-preflight.json"
    $script:CachedLivePreflightPathTranscriptPattern = ConvertTo-CommandValuePattern "-PreflightPath" $LivePreflightPath
    return $script:CachedLivePreflightPathTranscriptPattern
}

function Get-InstallSmokeCommandPatterns {
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $YuneRootTranscriptPattern = Get-YuneRootTranscriptPattern
    $BrowserPathTranscriptPattern = Get-BrowserPathTranscriptPattern
    $LivePreflightPathTranscriptPattern = Get-LivePreflightPathTranscriptPattern
    return @(
        "run-p2-win01-live-smoke\.ps1(?=.*-PreflightOnly)(?=.*$LivePreflightPathTranscriptPattern)(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)",
        "install-yune-windows-ime\.ps1(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)",
        "run-notepad-smoke\.ps1(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)",
        "run-chromium-smoke\.ps1(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)"
    )
}

function Get-CompletedInstallSmokeCommandPatterns {
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $YuneRootTranscriptPattern = Get-YuneRootTranscriptPattern
    $BrowserPathTranscriptPattern = Get-BrowserPathTranscriptPattern
    $LivePreflightPathTranscriptPattern = Get-LivePreflightPathTranscriptPattern
    return @(
        "^PASS\s+.*run-p2-win01-live-smoke\.ps1(?=.*-PreflightOnly)(?=.*$LivePreflightPathTranscriptPattern)(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)",
        "^PASS\s+.*install-yune-windows-ime\.ps1(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)",
        "^PASS\s+.*run-notepad-smoke\.ps1(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)",
        "^PASS\s+.*run-chromium-smoke\.ps1(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)"
    )
}

function Get-LivePreflightCommandPattern {
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $YuneRootTranscriptPattern = Get-YuneRootTranscriptPattern
    $BrowserPathTranscriptPattern = Get-BrowserPathTranscriptPattern
    $LivePreflightPathTranscriptPattern = Get-LivePreflightPathTranscriptPattern
    return "run-p2-win01-live-smoke\.ps1(?=.*-PreflightOnly)(?=.*$LivePreflightPathTranscriptPattern)(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)"
}

function Get-CompletedLivePreflightCommandPattern {
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $YuneRootTranscriptPattern = Get-YuneRootTranscriptPattern
    $BrowserPathTranscriptPattern = Get-BrowserPathTranscriptPattern
    $LivePreflightPathTranscriptPattern = Get-LivePreflightPathTranscriptPattern
    return "^PASS\s+.*run-p2-win01-live-smoke\.ps1(?=.*-PreflightOnly)(?=.*$LivePreflightPathTranscriptPattern)(?=.*$YuneRootTranscriptPattern)(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)"
}

function Has-CompletedLivePreflightCommandTranscript([string]$RelativePath) {
    $Patterns = @(
        (Get-LivePreflightCommandPattern),
        (Get-CompletedLivePreflightCommandPattern)
    )
    return (Has-OrderedCommandTranscript `
            -RelativePath $RelativePath `
            -Patterns $Patterns) -and
        (Has-NoFailedCommandTranscriptBeforeCompletedPatterns `
            -RelativePath $RelativePath `
            -Patterns $Patterns)
}

function Get-NotepadSmokeCommandPatterns {
    $Patterns = @(Get-InstallSmokeCommandPatterns)
    return @($Patterns[0], $Patterns[1], $Patterns[2])
}

function Get-CompletedNotepadSmokeCommandPatterns {
    $Patterns = @(Get-CompletedInstallSmokeCommandPatterns)
    return @($Patterns[0], $Patterns[1], $Patterns[2])
}

function Has-OrderedNotepadSmokeCommandTranscript([string]$RelativePath) {
    return Has-OrderedCommandTranscript `
        -RelativePath $RelativePath `
        -Patterns (Get-NotepadSmokeCommandPatterns)
}

function Has-CompletedNotepadSmokeCommandTranscript([string]$RelativePath) {
    $Patterns = Get-CompletedNotepadSmokeCommandPatterns
    return (Has-OrderedCommandTranscript `
            -RelativePath $RelativePath `
            -Patterns $Patterns) -and
        (Has-NoFailedCommandTranscriptBeforeCompletedPatterns `
            -RelativePath $RelativePath `
            -Patterns $Patterns)
}

function Has-OrderedInstallSmokeCommandTranscript([string]$RelativePath) {
    return Has-OrderedCommandTranscript `
        -RelativePath $RelativePath `
        -Patterns (Get-InstallSmokeCommandPatterns)
}

function Has-CompletedInstallSmokeCommandTranscript([string]$RelativePath) {
    $Patterns = Get-CompletedInstallSmokeCommandPatterns
    return (Has-OrderedCommandTranscript `
            -RelativePath $RelativePath `
            -Patterns $Patterns) -and
        (Has-NoFailedCommandTranscriptBeforeCompletedPatterns `
            -RelativePath $RelativePath `
            -Patterns $Patterns)
}

function Has-OrderedLiveCommandTranscript([string]$RelativePath) {
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $DiagnosticsOutputDirTranscriptPattern = Get-DiagnosticsOutputDirTranscriptPattern
    $Patterns = @(Get-InstallSmokeCommandPatterns) + @(
        "export-yune-windows-diagnostics\.ps1(?=.*$DiagnosticsOutputDirTranscriptPattern)(?=.*$InstallDirTranscriptPattern)",
        "uninstall-yune-windows-ime\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)"
    )
    return Has-OrderedCommandTranscript `
        -RelativePath $RelativePath `
        -Patterns $Patterns
}

function Has-CompletedLiveCommandTranscript([string]$RelativePath) {
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $DiagnosticsOutputDirTranscriptPattern = Get-DiagnosticsOutputDirTranscriptPattern
    $Patterns = @(Get-CompletedInstallSmokeCommandPatterns) + @(
        "^PASS\s+.*export-yune-windows-diagnostics\.ps1(?=.*$DiagnosticsOutputDirTranscriptPattern)(?=.*$InstallDirTranscriptPattern)",
        "^PASS\s+.*uninstall-yune-windows-ime\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)"
    )
    if ((Has-NoFailedCommandTranscript $RelativePath) -and
        (Has-OrderedCommandTranscript `
            -RelativePath $RelativePath `
            -Patterns $Patterns)) {
        return $true
    }

    return Has-RecoveredDelayedDeleteLiveCommandTranscript -RelativePath $RelativePath
}

function Has-RecoveredDelayedDeleteLiveCommandTranscript([string]$RelativePath) {
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $DiagnosticsOutputDirTranscriptPattern = Get-DiagnosticsOutputDirTranscriptPattern
    $Patterns = @(Get-CompletedInstallSmokeCommandPatterns) + @(
        "^PASS\s+.*export-yune-windows-diagnostics\.ps1(?=.*$DiagnosticsOutputDirTranscriptPattern)(?=.*$InstallDirTranscriptPattern)",
        "uninstall-yune-windows-ime\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)"
    )
    if (-not (Has-OrderedCommandTranscript -RelativePath $RelativePath -Patterns $Patterns)) {
        return $false
    }
    if (-not (Has-NoFailedCommandTranscriptBeforeCompletedPatterns -RelativePath $RelativePath -Patterns $Patterns)) {
        return $false
    }

    $FailedLines = @(Get-FailedCommandTranscriptLines -RelativePath $RelativePath)
    if ($FailedLines.Count -ne 1) {
        return $false
    }
    return ($FailedLines[0] -match "^FAIL\s+.*uninstall-yune-windows-ime\.ps1") -and
        ($FailedLines[0] -match "locked YuneWindowsTSF\.dll")
}

function Has-AnyFile([string]$RelativePath, [string]$Filter) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    return $null -ne (Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction SilentlyContinue |
        Select-Object -First 1)
}

function Get-TextFilesForClaimAudit {
    $Files = [System.Collections.Generic.List[string]]::new()

    foreach ($RelativePath in @(
            "README.md",
            "AGENTS.md",
            "docs\roadmap.md",
            "docs\requirements.md",
            "docs\decisions.md",
            "docs\reference",
            "docs\plans\active",
            "docs\evidence")) {
        $Path = if ($RelativePath -eq "docs\evidence") { $EvidenceRoot } else { Repo-Path $RelativePath }
        if (-not (Test-Path -LiteralPath $Path)) {
            continue
        }

        $Item = Get-Item -LiteralPath $Path
        if (-not $Item.PSIsContainer) {
            $Files.Add($Item.FullName)
            continue
        }

        Get-ChildItem -LiteralPath $Item.FullName -Recurse -File |
            Where-Object {
                ($_.Extension -in @(".md", ".txt", ".json")) -and
                ($_.FullName -notmatch '[\\/]p2-win01-closeout[\\/]audit\.(json|md)$')
            } |
            ForEach-Object { $Files.Add($_.FullName) }
    }

    return @($Files | Select-Object -Unique)
}

function Has-ForbiddenProductEngineClaim {
    $Patterns = @(
        "\bWindows\s+product\s+evidence\s+(?:closes|closed|completes|completed|proves|proved)\s+(?:Yune\s+)?M38\b",
        "\bWindows\s+product\s+proof\s+(?:closes|closed|completes|completed|proves|proved)\s+(?:Yune\s+)?M38\b",
        "\bProduct/frontend\s+performance\s+evidence\s+(?:closes|closed|completes|completed|proves|proved)\s+(?:Yune\s+)?M38\b",
        "\b(?:Yune\s+)?M38\s+(?:is\s+)?(?:complete|closed|done|passed)\s+because\s+of\s+Windows\s+product\b"
    )

    foreach ($Path in Get-TextFilesForClaimAudit) {
        $Text = Get-Content -Raw -LiteralPath $Path
        foreach ($Pattern in $Patterns) {
            if ($Text -match $Pattern) {
                return $true
            }
        }
    }

    return $false
}

function Has-PngEvidence([string]$RelativePath) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $File = Get-Item -LiteralPath $Path
    if ($File.Length -lt 64) {
        return $false
    }
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        $Header = [byte[]]::new(24)
        $Read = $Stream.Read($Header, 0, $Header.Length)
        if ($Read -ne $Header.Length) {
            return $false
        }
        $Expected = [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
        for ($Index = 0; $Index -lt $Expected.Length; $Index++) {
            if ($Header[$Index] -ne $Expected[$Index]) {
                return $false
            }
        }
        $ChunkType = [System.Text.Encoding]::ASCII.GetString($Header, 12, 4)
        if ($ChunkType -ne "IHDR") {
            return $false
        }

        $Width = ([uint32]$Header[16] -shl 24) -bor
            ([uint32]$Header[17] -shl 16) -bor
            ([uint32]$Header[18] -shl 8) -bor
            [uint32]$Header[19]
        $Height = ([uint32]$Header[20] -shl 24) -bor
            ([uint32]$Header[21] -shl 16) -bor
            ([uint32]$Header[22] -shl 8) -bor
            [uint32]$Header[23]

        return ($Width -ge 320) -and ($Height -ge 180)
    }
    finally {
        $Stream.Dispose()
    }
}

function Has-DistinctPngEvidence([string]$FirstPath, [string]$SecondPath) {
    if ((-not (Has-PngEvidence $FirstPath)) -or (-not (Has-PngEvidence $SecondPath))) {
        return $false
    }

    $FirstHash = (Get-FileHash -LiteralPath (Repo-Path $FirstPath) -Algorithm SHA256).Hash
    $SecondHash = (Get-FileHash -LiteralPath (Repo-Path $SecondPath) -Algorithm SHA256).Hash
    return $FirstHash -ne $SecondHash
}

function Read-ZipEntryText([System.IO.Compression.ZipArchive]$Archive, [string[]]$EntryNames) {
    foreach ($Name in $EntryNames) {
        $Entry = $Archive.GetEntry($Name)
        if ($null -eq $Entry) {
            continue
        }

        $Stream = $Entry.Open()
        $Reader = [System.IO.StreamReader]::new($Stream)
        try {
            return $Reader.ReadToEnd()
        }
        finally {
            $Reader.Dispose()
            $Stream.Dispose()
        }
    }

    $NormalizedNames = @($EntryNames | ForEach-Object { $_ -replace '\\', '/' })
    foreach ($Entry in $Archive.Entries) {
        $NormalizedEntry = $Entry.FullName -replace '\\', '/'
        if ($NormalizedNames -contains $NormalizedEntry) {
            $Stream = $Entry.Open()
            $Reader = [System.IO.StreamReader]::new($Stream)
            try {
                return $Reader.ReadToEnd()
            }
            finally {
                $Reader.Dispose()
                $Stream.Dispose()
            }
        }
    }

    return $null
}

function Read-ZipLogEntryTexts([System.IO.Compression.ZipArchive]$Archive) {
    $Texts = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in $Archive.Entries) {
        $NormalizedEntry = $Entry.FullName -replace '\\', '/'
        if ((-not $NormalizedEntry.StartsWith("logs/", [System.StringComparison]::OrdinalIgnoreCase)) -or
            (-not $NormalizedEntry.EndsWith(".log", [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }

        $Stream = $Entry.Open()
        $Reader = [System.IO.StreamReader]::new($Stream)
        try {
            $Texts.Add($Reader.ReadToEnd()) | Out-Null
        }
        finally {
            $Reader.Dispose()
            $Stream.Dispose()
        }
    }

    return @($Texts)
}

function Has-DiagnosticsBundleEvidence([string]$RelativePath) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $File = Get-Item -LiteralPath $Path
    if ($File.Length -lt 64) {
        return $false
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = $null
    try {
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $ManifestEntry = $Archive.GetEntry("manifest.json")
        if ($null -eq $ManifestEntry) {
            return $false
        }
        $Stream = $ManifestEntry.Open()
        $Reader = [System.IO.StreamReader]::new($Stream)
        try {
            $Manifest = $Reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $Reader.Dispose()
            $Stream.Dispose()
        }

        $GeneratedAt = ConvertTo-IsoDateTimeOffset $Manifest.generated_at
        $ApprovalDate = Get-IsoDateEvidenceValue "docs\evidence\p2-win01-installer\approval.md"
        if (($null -eq $GeneratedAt) -or ($null -eq $ApprovalDate) -or ($GeneratedAt -lt $ApprovalDate)) {
            return $false
        }

        if ((-not (Has-BooleanJsonProperty $Manifest.machine_state "registry_collected")) -or
            (-not (Has-BooleanJsonProperty $Manifest.sensitive_context "typed_content_logs")) -or
            (-not (Has-BooleanJsonProperty $Manifest.sensitive_context "ai_staging")) -or
            (-not (Has-BooleanJsonProperty $Manifest.diagnostics_logs "included")) -or
            (-not (Has-IntegerJsonProperty $Manifest.diagnostics_logs "file_count")) -or
            (-not (Has-BooleanJsonProperty $Manifest.diagnostics_logs "typed_content_logs")) -or
            (-not (Has-BooleanJsonProperty $Manifest.diagnostics_logs "structural_events_only"))) {
            return $false
        }

        $LogText = Read-ZipEntryText $Archive @("logs/tsf-events.log", "logs\tsf-events.log")
        if ([string]::IsNullOrWhiteSpace($LogText)) {
            return $false
        }
        $BundledLogTexts = @(Read-ZipLogEntryTexts $Archive)
        $ManifestLogCount = [int64]$Manifest.diagnostics_logs.file_count
        if (($ManifestLogCount -le 0) -or ($BundledLogTexts.Count -ne $ManifestLogCount)) {
            return $false
        }
        foreach ($BundledLogText in $BundledLogTexts) {
            if (Test-DiagnosticsLogContainsTypedContent -Text $BundledLogText) {
                return $false
            }
            if (Test-StructuralEventText -Text $BundledLogText -EventName "candidate_window_failed") {
                return $false
            }
        }

        return ($Manifest.product -eq "Yune Windows") -and
            ($Manifest.machine_state.registry_collected -eq $false) -and
            ($Manifest.sensitive_context.typed_content_logs -eq $false) -and
            ($Manifest.sensitive_context.ai_staging -eq $false) -and
            ($Manifest.diagnostics_logs.included -eq $true) -and
            ($ManifestLogCount -gt 0) -and
            ($Manifest.diagnostics_logs.typed_content_logs -eq $false) -and
            ($Manifest.diagnostics_logs.structural_events_only -eq $true) -and
            ($LogText -match "event=") -and
            (Test-StructuralCandidateUpdateText -Text $LogText) -and
            (Test-StructuralEventText -Text $LogText -EventName "commit_text") -and
            ($LogText -match "sequence=") -and
            (($LogText -match "buffer_length=") -or ($LogText -match "candidate_count="))
    }
    catch {
        return $false
    }
    finally {
        if ($Archive) {
            $Archive.Dispose()
        }
    }
}

function Get-DiagnosticsBundleGeneratedAt([string]$RelativePath) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = $null
    try {
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $ManifestEntry = $Archive.GetEntry("manifest.json")
        if ($null -eq $ManifestEntry) {
            return $null
        }

        $Stream = $ManifestEntry.Open()
        $Reader = [System.IO.StreamReader]::new($Stream)
        try {
            $Manifest = $Reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $Reader.Dispose()
            $Stream.Dispose()
        }

        return ConvertTo-IsoDateTimeOffset $Manifest.generated_at
    }
    catch {
        return $null
    }
    finally {
        if ($Archive) {
            $Archive.Dispose()
        }
    }
}

function Read-JsonEvidence([string]$RelativePath) {
    $Path = Repo-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Has-JsonProperty([object]$Value, [string]$Name) {
    return ($null -ne $Value) -and ($null -ne $Value.PSObject.Properties[$Name])
}

function Has-BooleanJsonProperty([object]$Value, [string]$Name) {
    if (-not (Has-JsonProperty $Value $Name)) {
        return $false
    }
    return $Value.PSObject.Properties[$Name].Value -is [bool]
}

function Has-BooleanJsonValue([object]$Value, [string]$Name, [bool]$Expected) {
    if (-not (Has-BooleanJsonProperty $Value $Name)) {
        return $false
    }
    return $Value.PSObject.Properties[$Name].Value -eq $Expected
}

function Has-IntegerJsonProperty([object]$Value, [string]$Name) {
    if (-not (Has-JsonProperty $Value $Name)) {
        return $false
    }
    $PropertyValue = $Value.PSObject.Properties[$Name].Value
    return ($PropertyValue -is [byte]) -or
        ($PropertyValue -is [int16]) -or
        ($PropertyValue -is [int]) -or
        ($PropertyValue -is [long])
}

function Has-FreshStateSnapshotTimestamp([object]$Snapshot) {
    if (-not (Has-JsonProperty $Snapshot "captured_at")) {
        return $false
    }

    $CapturedAt = ConvertTo-IsoDateTimeOffset $Snapshot.captured_at
    $ApprovalDate = Get-IsoDateEvidenceValue "docs\evidence\p2-win01-installer\approval.md"
    if (($null -eq $CapturedAt) -or ($null -eq $ApprovalDate)) {
        return $false
    }

    return $CapturedAt -ge $ApprovalDate
}

function Get-StateSnapshotCapturedAt([string]$SnapshotPath) {
    $Snapshot = Read-JsonEvidence $SnapshotPath
    if ($null -eq $Snapshot) {
        return $null
    }
    if (-not (Has-JsonProperty $Snapshot "captured_at")) {
        return $null
    }

    $CapturedAt = ConvertTo-IsoDateTimeOffset $Snapshot.captured_at
    if ($null -eq $CapturedAt) {
        return $null
    }

    return $CapturedAt
}

function Has-StateSnapshotCapturedNoLaterThan([string]$SnapshotPath, [object]$LatestDate) {
    if ($LatestDate -isnot [System.DateTimeOffset]) {
        return $false
    }

    $CapturedAt = Get-StateSnapshotCapturedAt $SnapshotPath
    return ($null -ne $CapturedAt) -and ($CapturedAt -le ([System.DateTimeOffset]$LatestDate))
}

function Has-StateSnapshotCapturedNoEarlierThan([string]$SnapshotPath, [object]$EarliestDate) {
    if ($EarliestDate -isnot [System.DateTimeOffset]) {
        return $false
    }

    $CapturedAt = Get-StateSnapshotCapturedAt $SnapshotPath
    return ($null -ne $CapturedAt) -and ($CapturedAt -ge ([System.DateTimeOffset]$EarliestDate))
}

function Get-LatestIsoDateEvidenceValue([string[]]$RelativePaths) {
    $LatestDate = $null
    foreach ($RelativePath in $RelativePaths) {
        $Date = Get-IsoDateEvidenceValue $RelativePath
        if ($null -eq $Date) {
            return $null
        }
        if (($null -eq $LatestDate) -or ($Date -gt $LatestDate)) {
            $LatestDate = $Date
        }
    }
    return $LatestDate
}

function Get-EarliestIsoDateEvidenceValue([string[]]$RelativePaths) {
    $EarliestDate = $null
    foreach ($RelativePath in $RelativePaths) {
        $Date = Get-IsoDateEvidenceValue $RelativePath
        if ($null -eq $Date) {
            return $null
        }
        if (($null -eq $EarliestDate) -or ($Date -lt $EarliestDate)) {
            $EarliestDate = $Date
        }
    }
    return $EarliestDate
}

function Has-NonEmptyJsonStringProperty([object]$Value, [string]$Name) {
    if (-not (Has-JsonProperty $Value $Name)) {
        return $false
    }
    return -not [string]::IsNullOrWhiteSpace([string]$Value.PSObject.Properties[$Name].Value)
}

function Has-PreflightReportEvidence(
    [string]$RelativePath,
    [bool]$RequireBrowser,
    [bool]$RequireGeneratedAtAfterApproval = $false
) {
    $Report = Read-JsonEvidence $RelativePath
    if ($null -eq $Report) {
        return $false
    }

    foreach ($RequiredString in @("generated_at", "install_dir", "yune_root", "yune_runtime_path", "yune_schema_path")) {
        if (-not (Has-NonEmptyJsonStringProperty $Report $RequiredString)) {
            return $false
        }
    }
    $GeneratedAt = ConvertTo-IsoDateTimeOffset $Report.generated_at
    if ($null -eq $GeneratedAt) {
        return $false
    }
    if ($RequireGeneratedAtAfterApproval) {
        $ApprovalPath = "docs\evidence\p2-win01-installer\approval.md"
        $ApprovalDate = Get-IsoDateEvidenceValue $ApprovalPath
        if (Has-Path $ApprovalPath) {
            if (($null -eq $ApprovalDate) -or ($GeneratedAt -lt $ApprovalDate)) {
                return $false
            }
        }
    }
    if (-not (Has-NonEmptyJsonStringProperty $Report "machine_residue_source")) {
        return $false
    }
    $MachineResidueSource = [string]$Report.machine_residue_source
    try {
        $ReportPath = [System.IO.Path]::GetFullPath((Repo-Path $RelativePath))
        $MachineResidueSourcePath = [System.IO.Path]::GetFullPath($MachineResidueSource)
        if ([string]::Equals(
                $ReportPath,
                $MachineResidueSourcePath,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    catch {
        return $false
    }

    foreach ($RequiredBoolean in @(
            "machine_state_changed",
            "machine_state_checked",
            "ready_for_live_smoke",
            "install_dir_exists",
            "yune_runtime_exists",
            "yune_schema_exists",
            "tsf_source_exists",
            "server_source_exists",
            "build_script_exists",
            "is_administrator",
            "is_sta",
            "browser_available"
        )) {
        if (-not (Has-BooleanJsonProperty $Report $RequiredBoolean)) {
            return $false
        }
    }

    if (-not (Has-IntegerJsonProperty $Report "server_process_count")) {
        return $false
    }

    if ($Report.machine_state_changed -ne $false) {
        return $false
    }
    if ($Report.machine_state_checked -ne $true) {
        return $false
    }
    if (-not (Has-JsonProperty $Report "machine_state_issues")) {
        return $false
    }
    if (@($Report.machine_state_issues).Count -ne 0) {
        return $false
    }
    if (-not (Has-JsonProperty $Report "filesystem_leftovers")) {
        return $false
    }
    if (@($Report.filesystem_leftovers).Count -ne 0) {
        return $false
    }
    if ($Report.install_dir_exists -ne $false) {
        return $false
    }
    if ($Report.server_process_count -ne 0) {
        return $false
    }
    if ($Report.yune_runtime_exists -ne $true) {
        return $false
    }
    if ($Report.yune_schema_exists -ne $true) {
        return $false
    }
    if ($Report.tsf_source_exists -ne $true) {
        return $false
    }
    if ($Report.server_source_exists -ne $true) {
        return $false
    }
    if ($Report.build_script_exists -ne $true) {
        return $false
    }
    if ($Report.ready_for_live_smoke -ne $true) {
        return $false
    }
    if ($Report.is_administrator -ne $true) {
        return $false
    }
    if ($RequireBrowser -and $Report.is_sta -ne $true) {
        return $false
    }

    if ($RequireBrowser) {
        if ($Report.browser_available -ne $true) {
            return $false
        }
        if (-not (Has-NonEmptyJsonStringProperty $Report "browser_path")) {
            return $false
        }
        if (-not (Test-IsConcreteBrowserExecutablePath -Path ([string]$Report.browser_path))) {
            return $false
        }
        try {
            $BrowserPath = [System.IO.Path]::GetFullPath([string]$Report.browser_path)
        }
        catch {
            return $false
        }
        if (-not (Test-Path -LiteralPath $BrowserPath -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Get-LivePreflightStatus {
    $LivePath = "docs\evidence\p2-win01-installer\live-preflight.json"
    $InstallPath = "docs\evidence\p2-win01-installer\install-preflight.json"
    $CommandsPath = "docs\evidence\p2-win01-installer\commands.txt"
    $ApprovalPath = "docs\evidence\p2-win01-installer\approval.md"
    if ((-not (Has-Path $LivePath)) -or (-not (Has-Path $InstallPath))) {
        return "missing"
    }

    if ((Has-PreflightReportEvidence `
            -RelativePath $LivePath `
            -RequireBrowser $true `
            -RequireGeneratedAtAfterApproval $true) -and
        (Has-PreflightReportEvidence -RelativePath $InstallPath -RequireBrowser $false)) {
        if ((Has-Path $ApprovalPath) -and
            (-not (Has-CompletedLivePreflightCommandTranscript $CommandsPath))) {
            return "invalid"
        }
        return "complete"
    }

    return "invalid"
}

function Get-PreflightResidueCounts {
    $MachineStateIssues = @{}
    $FilesystemLeftovers = @{}

    foreach ($RelativePath in @(
            "docs\evidence\p2-win01-installer\live-preflight.json",
            "docs\evidence\p2-win01-installer\install-preflight.json")) {
        $Report = Read-JsonEvidence $RelativePath
        if ($null -eq $Report) {
            continue
        }
        if (Has-JsonProperty $Report "machine_state_issues") {
            foreach ($Issue in @($Report.machine_state_issues)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$Issue)) {
                    $MachineStateIssues[[string]$Issue] = $true
                }
            }
        }
        if (Has-JsonProperty $Report "filesystem_leftovers") {
            foreach ($Leftover in @($Report.filesystem_leftovers)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$Leftover)) {
                    $FilesystemLeftovers[[string]$Leftover] = $true
                }
            }
        }
    }

    return [pscustomobject]@{
        machine_state_issues = $MachineStateIssues.Count
        filesystem_leftovers = $FilesystemLeftovers.Count
    }
}

function Get-LivePreflightNotes([string]$Status) {
    if ($Status -eq "complete") {
        return "Preflight evidence records clean fresh-target readiness without install/register/browser automation."
    }
    if ($Status -eq "missing") {
        return "Install/live preflight evidence is missing."
    }

    $ResidueCounts = Get-PreflightResidueCounts
    if (($ResidueCounts.machine_state_issues -gt 0) -or
        ($ResidueCounts.filesystem_leftovers -gt 0)) {
        return "Preflight evidence is invalid: machine-state residue issues: $($ResidueCounts.machine_state_issues); filesystem leftovers: $($ResidueCounts.filesystem_leftovers). Cleanup remains approval-gated."
    }

    if ((Has-Path "docs\evidence\p2-win01-installer\approval.md") -and
        (-not (Has-CompletedLivePreflightCommandTranscript "docs\evidence\p2-win01-installer\commands.txt"))) {
        return "Preflight evidence is invalid; commands.txt must record live-preflight start and PASS entries after approval."
    }

    return "Preflight evidence is invalid; expected non-mutating fresh-target readiness with clean machine-residue fields."
}

function Read-ProfileState([object]$Snapshot) {
    if ($null -eq $Snapshot) {
        return $null
    }
    if (-not (Has-BooleanJsonValue $Snapshot "profile_state_verified" $true)) {
        return $null
    }

    if (-not (Has-JsonProperty $Snapshot "profile_state")) {
        return $null
    }
    $ProfileStateValue = $Snapshot.PSObject.Properties["profile_state"].Value
    if ($ProfileStateValue -isnot [string]) {
        return $null
    }
    $ProfileText = $ProfileStateValue
    if ([string]::IsNullOrWhiteSpace($ProfileText)) {
        return $null
    }

    try {
        $Profile = $ProfileText | ConvertFrom-Json
    }
    catch {
        return $null
    }
    if ((-not (Has-BooleanJsonProperty $Profile "registered")) -or
        (-not (Has-BooleanJsonProperty $Profile "active"))) {
        return $null
    }

    return $Profile
}

function Has-ProfileSnapshotEvidence(
    [string]$SnapshotPath,
    [bool]$RequireInstalledFiles,
    [bool]$RequireRegistered,
    [bool]$RequireActive
) {
    $Snapshot = Read-JsonEvidence $SnapshotPath
    if ($null -eq $Snapshot) {
        return $false
    }
    if (-not (Has-FreshStateSnapshotTimestamp $Snapshot)) {
        return $false
    }

    if ($RequireInstalledFiles) {
        if (-not (Has-BooleanJsonValue $Snapshot "install_dir_exists" $true)) {
            return $false
        }
        if (-not (Has-BooleanJsonValue $Snapshot "profile_tool_exists" $true)) {
            return $false
        }
    }

    $Profile = Read-ProfileState $Snapshot
    if ($null -eq $Profile) {
        return $false
    }

    if ($RequireRegistered -and (-not (Has-BooleanJsonValue $Profile "registered" $true))) {
        return $false
    }
    if ($RequireActive -and (-not (Has-BooleanJsonValue $Profile "active" $true))) {
        return $false
    }

    return $true
}

function Has-MachineRegistrationSnapshotEvidence(
    [string]$SnapshotPath,
    [bool]$RequireInstalledFiles
) {
    $Snapshot = Read-JsonEvidence $SnapshotPath
    if ($null -eq $Snapshot) {
        return $false
    }
    if (-not (Has-FreshStateSnapshotTimestamp $Snapshot)) {
        return $false
    }

    if ($RequireInstalledFiles) {
        if (-not (Has-BooleanJsonValue $Snapshot "install_dir_exists" $true)) {
            return $false
        }
        if (-not (Has-BooleanJsonValue $Snapshot "profile_tool_exists" $true)) {
            return $false
        }
    }

    foreach ($Name in @(
            "machine_registration_checked",
            "machine_registration_verified",
            "machine_registration_registered",
            "machine_registration_dll_path_matches"
        )) {
        if (-not (Has-BooleanJsonValue $Snapshot $Name $true)) {
            return $false
        }
    }

    if (@($Snapshot.machine_registration_missing_keys).Count -ne 0) {
        return $false
    }
    if (@($Snapshot.machine_registration_registry_check_errors).Count -ne 0) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Snapshot.machine_registration_dll_path)) {
        return $false
    }

    return $true
}

function Has-CleanPreInstallEvidence([string]$SnapshotPath) {
    $Snapshot = Read-JsonEvidence $SnapshotPath
    if ($null -eq $Snapshot) {
        return $false
    }
    if (-not (Has-FreshStateSnapshotTimestamp $Snapshot)) {
        return $false
    }

    if (-not (Has-BooleanJsonValue $Snapshot "install_dir_exists" $false)) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Snapshot "profile_tool_exists" $false)) {
        return $false
    }
    if (@($Snapshot.server_processes).Count -ne 0) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Snapshot "machine_state_checked" $true)) {
        return $false
    }
    if (@($Snapshot.machine_state_issues).Count -ne 0) {
        return $false
    }
    if (@($Snapshot.filesystem_leftovers).Count -ne 0) {
        return $false
    }

    $Profile = Read-ProfileState $Snapshot
    if ($null -eq $Profile) {
        return $false
    }
    if ((-not (Has-BooleanJsonValue $Profile "registered" $false)) -or
        (-not (Has-BooleanJsonValue $Profile "active" $false))) {
        return $false
    }

    return $true
}

function Has-InstallActivationEvidence {
    $PreInstallState = "docs\evidence\p2-win01-installer\pre-install-state.json"
    $PostInstallState = "docs\evidence\p2-win01-installer\post-install-state.json"
    $PreInstallIsClean = Has-CleanPreInstallEvidence `
        -SnapshotPath $PreInstallState
    $InstallIsRegistered = Has-MachineRegistrationSnapshotEvidence `
        -SnapshotPath $PostInstallState `
        -RequireInstalledFiles $true
    $ProfileWasActivated = (Has-ProfileSnapshotEvidence `
            -SnapshotPath "docs\evidence\p2-win01-tsf-smoke\notepad-post-state.json" `
            -RequireInstalledFiles $true `
            -RequireRegistered $true `
            -RequireActive $true) -or
        (Has-ProfileSnapshotEvidence `
            -SnapshotPath "docs\evidence\p2-win01-tsf-smoke\chromium-post-state.json" `
            -RequireInstalledFiles $true `
            -RequireRegistered $true `
            -RequireActive $true)
    $EarliestAppSmokeResultDate = Get-EarliestIsoDateEvidenceValue @(
        "docs\evidence\p2-win01-tsf-smoke\notepad-smoke-result.md",
        "docs\evidence\p2-win01-tsf-smoke\chromium-smoke-result.md"
    )
    $InstallTimelineIsValid = (Has-StateSnapshotCapturedNoLaterThan `
            -SnapshotPath $PreInstallState `
            -LatestDate (Get-StateSnapshotCapturedAt $PostInstallState)) -and
        (Has-StateSnapshotCapturedNoLaterThan `
            -SnapshotPath $PostInstallState `
            -LatestDate $EarliestAppSmokeResultDate)

    return $PreInstallIsClean -and $InstallIsRegistered -and $ProfileWasActivated -and $InstallTimelineIsValid
}

function Has-CleanupEvidence([string]$ValidationPath, [string]$SnapshotPath) {
    $ValidationFullPath = Repo-Path $ValidationPath
    $SnapshotFullPath = Repo-Path $SnapshotPath
    if ((-not (Test-Path -LiteralPath $ValidationFullPath)) -or
        (-not (Test-Path -LiteralPath $SnapshotFullPath))) {
        return $false
    }

    try {
        $Validation = Get-Content -Raw -LiteralPath $ValidationFullPath | ConvertFrom-Json
        $Snapshot = Get-Content -Raw -LiteralPath $SnapshotFullPath | ConvertFrom-Json
    }
    catch {
        return $false
    }

    if (-not (Has-FreshStateSnapshotTimestamp $Snapshot)) {
        return $false
    }
    $ValidationGeneratedAt = ConvertTo-IsoDateTimeOffset $Validation.generated_at
    $ApprovalDate = Get-IsoDateEvidenceValue "docs\evidence\p2-win01-installer\approval.md"
    if (($null -eq $ValidationGeneratedAt) -or
        ($null -eq $ApprovalDate) -or
        ($ValidationGeneratedAt -lt $ApprovalDate)) {
        return $false
    }
    $SnapshotCapturedAt = ConvertTo-IsoDateTimeOffset $Snapshot.captured_at
    if (($null -eq $SnapshotCapturedAt) -or
        ($ValidationGeneratedAt -lt $SnapshotCapturedAt)) {
        return $false
    }
    if ((-not (Has-BooleanJsonProperty $Validation "pass")) -or
        ($Validation.pass -ne $true)) {
        return $false
    }
    if (@($Validation.issues).Count -ne 0) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Snapshot "install_dir_exists" $false)) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Snapshot "profile_tool_exists" $false)) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Snapshot "profile_state_verified" $true)) {
        return $false
    }
    if (@($Snapshot.server_processes).Count -ne 0) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Snapshot "machine_state_checked" $true)) {
        return $false
    }
    if (@($Snapshot.machine_state_issues).Count -ne 0) {
        return $false
    }
    if (@($Snapshot.filesystem_leftovers).Count -ne 0) {
        return $false
    }

    $Profile = Read-ProfileState $Snapshot
    if ($null -eq $Profile) {
        return $false
    }
    return (Has-BooleanJsonValue $Profile "registered" $false) -and
        (Has-BooleanJsonValue $Profile "active" $false)
}

function Has-CleanupResultDateNoEarlierThanValidation([string]$ResultPath, [string]$ValidationPath) {
    $ResultDate = Get-IsoDateEvidenceValue $ResultPath
    $Validation = Read-JsonEvidence $ValidationPath
    if (($null -eq $ResultDate) -or ($null -eq $Validation)) {
        return $false
    }

    $ValidationGeneratedAt = ConvertTo-IsoDateTimeOffset $Validation.generated_at
    return ($null -ne $ValidationGeneratedAt) -and ($ResultDate -ge $ValidationGeneratedAt)
}

function Has-ResultDateNoEarlierThanEvidence([string]$ResultPath, [string]$EarlierEvidencePath) {
    $ResultDate = Get-IsoDateEvidenceValue $ResultPath
    $EarlierDate = Get-IsoDateEvidenceValue $EarlierEvidencePath
    return ($null -ne $ResultDate) -and
        ($null -ne $EarlierDate) -and
        ($ResultDate -ge $EarlierDate)
}

function Get-ExpectedP2Win01CommitText {
    return -join ([char[]](0x6211, 0x4fc2, 0x500b))
}

function Get-ObservedClipboardText([string]$ResultPath) {
    $Path = Repo-Path $ResultPath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $Text = Get-Content -Raw -LiteralPath $Path
    $Pattern = "Observed clipboard text after select-all/copy:\s*````text\s*(?<observed>.*?)\s*````"
    $Match = [regex]::Match(
        $Text,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $Match.Success) {
        return $null
    }

    return $Match.Groups["observed"].Value.Trim()
}

function Get-DiagnosticsBundlePathFromInstallResult([string]$ResultPath) {
    $Path = Repo-Path $ResultPath
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $Text = Get-Content -Raw -LiteralPath $Path
    $Match = [regex]::Match(
        $Text,
        "Diagnostics bundle:\s*````text\s*(?<path>.*?)\s*````",
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $Match.Success) {
        return $null
    }

    $Value = $Match.Groups["path"].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    return $Value
}

function Get-RelativeDiagnosticsBundlePathFromInstallResult([string]$ResultPath) {
    $BundlePath = Get-DiagnosticsBundlePathFromInstallResult $ResultPath
    if (-not (Test-IsConcreteWindowsPath -Path $BundlePath)) {
        return $null
    }

    try {
        $FullBundlePath = [System.IO.Path]::GetFullPath($BundlePath)
        $DiagnosticsDir = [System.IO.Path]::GetFullPath(
            (Repo-Path "docs\evidence\p2-win01-settings\registered-session-diagnostics"))
    }
    catch {
        return $null
    }

    $DiagnosticsDir = $DiagnosticsDir.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not $FullBundlePath.StartsWith(
            $DiagnosticsDir + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if ([System.IO.Path]::GetExtension($FullBundlePath) -ne ".zip") {
        return $null
    }

    if (-not (Test-Path -LiteralPath $FullBundlePath -PathType Leaf)) {
        return $null
    }

    $DiagnosticsRootPrefix = $DiagnosticsDir + [System.IO.Path]::DirectorySeparatorChar
    $RelativeBundle = $FullBundlePath.Substring($DiagnosticsRootPrefix.Length)
    return Join-Path "docs\evidence\p2-win01-settings\registered-session-diagnostics" $RelativeBundle
}

function Has-DiagnosticsBundleResultPath([string]$ResultPath) {
    $RelativeBundle = Get-RelativeDiagnosticsBundlePathFromInstallResult $ResultPath
    return ($null -ne $RelativeBundle) -and (Has-DiagnosticsBundleEvidence $RelativeBundle)
}

function Has-PassingTextSmoke([string]$ResultPath) {
    $Observed = Get-ObservedClipboardText $ResultPath
    return (Has-LiveResultDateEvidence $ResultPath) -and
        (File-Contains $ResultPath "^Status:\s*passed\s*$") -and
        (-not (File-Contains $ResultPath "^Status:\s*failed\s*$")) -and
        (File-Contains $ResultPath "^Pass:\s*True\s*$") -and
        (File-Contains $ResultPath "^Raw ASCII observed:\s*False\s*$") -and
        (File-Contains $ResultPath "^Foreground target verified before typing:\s*True\s*$") -and
        (File-Contains $ResultPath "^Active profile verified before typing:\s*True\s*$") -and
        (File-Contains $ResultPath "^Input method:\s*Win32 virtual-key typed test input\.\s*$") -and
        (File-Contains $ResultPath "^Clipboard cleared before typing:\s*True\s*$") -and
        (File-Contains $ResultPath "^Clipboard cleared after capture:\s*True\s*$") -and
        (File-Contains $ResultPath "^Candidate-display screenshot captured:\s*True\s*$") -and
        (File-Contains $ResultPath "^Commit screenshot captured:\s*True\s*$") -and
        (File-Contains $ResultPath "^Candidate/commit screenshots distinct:\s*True\s*$") -and
        (File-Contains $ResultPath "^Matches expected Yune commit:\s*True\s*$") -and
        (File-Contains $ResultPath "^Structural candidate update observed:\s*True\s*$") -and
        (File-Contains $ResultPath "^Structural candidate update candidate count positive:\s*True\s*$") -and
        (File-Contains $ResultPath "^Structural commit event observed:\s*True\s*$") -and
        (File-Contains $ResultPath "^Structural candidate window failure observed:\s*False\s*$") -and
        (File-Contains $ResultPath "^Structural event matcher:\s*exact event tokens\s*$") -and
        (File-Contains $ResultPath "^Structural new log lines:\s*[1-9][0-9]*\s*$") -and
        ($Observed -eq (Get-ExpectedP2Win01CommitText))
}

function Has-ChromiumTextareaFocusEvidence([string]$ResultPath) {
    return File-Contains $ResultPath "^Chromium textarea focus verified before typing:\s*True\s*$"
}

function Has-ChromiumTextFieldClickEvidence([string]$ResultPath) {
    return File-Contains $ResultPath "^Chromium text-field click verified before typing:\s*True\s*$"
}

function Has-ActiveInstalledProfileState([string]$SnapshotPath) {
    return Has-ProfileSnapshotEvidence `
        -SnapshotPath $SnapshotPath `
        -RequireInstalledFiles $true `
        -RequireRegistered $true `
        -RequireActive $true
}

function Has-TextSmokePostStateForResult([string]$SnapshotPath, [string]$ResultPath) {
    return (Has-ActiveInstalledProfileState $SnapshotPath) -and
        (Has-StateSnapshotCapturedNoLaterThan `
            -SnapshotPath $SnapshotPath `
            -LatestDate (Get-IsoDateEvidenceValue $ResultPath))
}

function Get-NotepadSmokeStatus {
    $result = "docs\evidence\p2-win01-tsf-smoke\notepad-smoke-result.md"
    $commands = "docs\evidence\p2-win01-installer\commands.txt"
    if (-not (Has-Path $result)) {
        return "missing"
    }
    if ((Has-PassingTextSmoke $result) -and
        (Has-Path $commands) -and
        (Has-OrderedNotepadSmokeCommandTranscript $commands) -and
        (Has-CompletedNotepadSmokeCommandTranscript $commands) -and
        (Has-TextSmokePostStateForResult `
            "docs\evidence\p2-win01-tsf-smoke\notepad-post-state.json" `
            $result) -and
        (Has-DistinctPngEvidence `
            "docs\evidence\p2-win01-tsf-smoke\candidate-display-notepad.png" `
            "docs\evidence\p2-win01-tsf-smoke\notepad-commit.png")) {
        return "complete"
    }
    return "invalid"
}

function Get-ChromiumSmokeStatus {
    $result = "docs\evidence\p2-win01-tsf-smoke\chromium-smoke-result.md"
    $commands = "docs\evidence\p2-win01-installer\commands.txt"
    if (-not (Has-Path $result)) {
        return "missing"
    }
    if ((Has-PassingTextSmoke $result) -and
        (Has-ChromiumTextFieldClickEvidence $result) -and
        (Has-ChromiumTextareaFocusEvidence $result) -and
        (Has-Path $commands) -and
        (Has-OrderedInstallSmokeCommandTranscript $commands) -and
        (Has-CompletedInstallSmokeCommandTranscript $commands) -and
        (Has-TextSmokePostStateForResult `
            "docs\evidence\p2-win01-tsf-smoke\chromium-post-state.json" `
            $result) -and
        (Has-DistinctPngEvidence `
            "docs\evidence\p2-win01-tsf-smoke\candidate-display-chromium.png" `
            "docs\evidence\p2-win01-tsf-smoke\chromium-commit.png")) {
        return "complete"
    }
    return "invalid"
}

function Get-CandidateDisplayStatus([string]$NotepadStatus, [string]$ChromiumStatus) {
    $has_build_preflight = Has-Path "docs\evidence\p2-win01-candidate-window\build-preflight.md"
    if ($NotepadStatus -eq "complete" -and $ChromiumStatus -eq "complete") {
        return "complete"
    }
    if ($NotepadStatus -eq "invalid" -or $ChromiumStatus -eq "invalid") {
        return "invalid"
    }
    if ($has_build_preflight) {
        return "preflight"
    }
    return "missing"
}

function Get-TsfServerIpcStatus([string]$NotepadStatus) {
    $has_preflight = (Has-Path "docs\evidence\p2-win01-tsf-smoke\server-ipc-smoke.md") -and
        (Has-Path "src\tsf\yune_windows_tsf.cpp") -and
        (Has-Path "src\server\yune_windows_server.cpp")
    if (-not $has_preflight) {
        return "missing"
    }
    if ($NotepadStatus -eq "complete") {
        return "complete"
    }
    return "preflight"
}

function Get-InstallActivationStatus {
    $result = "docs\evidence\p2-win01-installer\result.md"
    $commands = "docs\evidence\p2-win01-installer\commands.txt"
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $BrowserPathTranscriptPattern = Get-BrowserPathTranscriptPattern
    if (-not (Has-Path $result)) {
        return "missing"
    }
    if ((Has-Path $commands) -and
        (File-Contains $commands "install-yune-windows-ime\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)") -and
        (File-Contains $commands "run-notepad-smoke\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)") -and
        (File-Contains $commands "run-chromium-smoke\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*$BrowserPathTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)") -and
        (Has-OrderedInstallSmokeCommandTranscript $commands) -and
        (Has-CompletedInstallSmokeCommandTranscript $commands) -and
        (Has-InstallActivationEvidence) -and
        (Has-LiveResultDateEvidence $result) -and
        (Has-ResultDateNoEarlierThanEvidence `
            $result `
            "docs\evidence\p2-win01-installer\cleanup-result.md") -and
        (File-Contains $result "^Status:\s*passed\s*$") -and
        (-not (File-Contains $result "^Status:\s*failed\s*$")) -and
        (File-Contains $result "Fresh install") -and
        (File-Contains $result "Notepad smoke") -and
        (File-Contains $result "Chromium smoke") -and
        (Has-DiagnosticsBundleResultPath $result)) {
        return "complete"
    }
    return "invalid"
}

function Get-DiagnosticsStatus {
    $Commands = "docs\evidence\p2-win01-installer\commands.txt"
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    $DiagnosticsOutputDirTranscriptPattern = Get-DiagnosticsOutputDirTranscriptPattern
    $DiagnosticsPreState = "docs\evidence\p2-win01-settings\diagnostics-pre-state.json"
    $DiagnosticsDir = "docs\evidence\p2-win01-settings\registered-session-diagnostics"
    $LatestAppSmokeResultDate = Get-LatestIsoDateEvidenceValue @(
        "docs\evidence\p2-win01-tsf-smoke\notepad-smoke-result.md",
        "docs\evidence\p2-win01-tsf-smoke\chromium-smoke-result.md"
    )
    $DiagnosticsPath = Repo-Path $DiagnosticsDir
    if (Test-Path -LiteralPath $DiagnosticsPath) {
        $RelativeBundle = Get-RelativeDiagnosticsBundlePathFromInstallResult `
            "docs\evidence\p2-win01-installer\result.md"
        if (($null -ne $RelativeBundle) -and
            (Has-Path $Commands) -and
            (File-Contains $Commands "export-yune-windows-diagnostics\.ps1(?=.*$DiagnosticsOutputDirTranscriptPattern)(?=.*$InstallDirTranscriptPattern)") -and
            (Has-OrderedLiveCommandTranscript $Commands) -and
            (Has-CompletedLiveCommandTranscript $Commands) -and
            (Has-ProfileSnapshotEvidence `
                -SnapshotPath $DiagnosticsPreState `
                -RequireInstalledFiles $true `
                -RequireRegistered $true `
                -RequireActive $true) -and
            (Has-DiagnosticsBundleEvidence $RelativeBundle) -and
            (Has-StateSnapshotCapturedNoEarlierThan `
                -SnapshotPath $DiagnosticsPreState `
                -EarliestDate $LatestAppSmokeResultDate) -and
            (Has-StateSnapshotCapturedNoLaterThan `
                -SnapshotPath $DiagnosticsPreState `
                -LatestDate (Get-DiagnosticsBundleGeneratedAt $RelativeBundle))) {
            return "complete"
        }
        return "invalid"
    }
    if ((Has-Path "docs\evidence\p2-win01-settings\diagnostics-export.md") -and
        (Has-Path "tools\export-yune-windows-diagnostics.ps1")) {
        return "preflight"
    }
    return "missing"
}

function Get-CleanupStatus {
    $result = "docs\evidence\p2-win01-installer\cleanup-result.md"
    $commands = "docs\evidence\p2-win01-installer\commands.txt"
    $ApprovalNoteTranscriptPattern = Get-ApprovalNoteTranscriptPattern
    $InstallDirTranscriptPattern = Get-InstallDirTranscriptPattern
    if (-not (Has-Path $result)) {
        return "missing"
    }
    if ((Has-Path $commands) -and
        (File-Contains $commands "uninstall-yune-windows-ime\.ps1(?=.*$InstallDirTranscriptPattern)(?=.*ApprovedMachineStateChange)(?=.*$ApprovalNoteTranscriptPattern)") -and
        (Has-OrderedLiveCommandTranscript $commands) -and
        (Has-CompletedLiveCommandTranscript $commands) -and
        (Has-CleanupEvidence `
            "docs\evidence\p2-win01-installer\cleanup-validation.json" `
            "docs\evidence\p2-win01-installer\post-cleanup-state.json") -and
        (Has-CleanupResultDateNoEarlierThanValidation `
            $result `
            "docs\evidence\p2-win01-installer\cleanup-validation.json") -and
        (Has-LiveResultDateEvidence $result) -and
        (File-Contains $result "^Status:\s*passed\s*$") -and
        (-not (File-Contains $result "^Status:\s*failed\s*$")) -and
        (File-Contains $result "^Pass:\s*True\s*$")) {
        return "complete"
    }
    return "invalid"
}

function Get-LiveApprovalEvidenceStatus {
    $Evidence = "docs\evidence\p2-win01-installer\approval.md"
    if (-not (Has-Path $Evidence)) {
        return "missing"
    }

    $RequiredPatterns = @(
        'Date:\s*\d{4}-\d{2}-\d{2}T',
        'Approval note:\s*\S',
        'Machine state changed before approval evidence:\s*false',
        'Administrator:\s*True',
        'STA:\s*True',
        'Install dir:\s*\S',
        'Yune root:\s*\S',
        'Browser path:\s*\S'
    )
    foreach ($Pattern in $RequiredPatterns) {
        if (-not (File-Contains $Evidence $Pattern)) {
            return "invalid"
        }
    }

    if ($null -eq (Get-IsoDateEvidenceValue $Evidence)) {
        return "invalid"
    }

    $ApprovalNote = Get-LiveApprovalNote
    if (Test-IsPlaceholderApprovalNote -ApprovalNote $ApprovalNote) {
        return "invalid"
    }

    if (-not (Test-ApprovalEvidencePathsAreConcrete -Evidence $Evidence)) {
        return "invalid"
    }

    return "complete"
}

function Has-MachineCleanupSnapshotEvidence(
    [object]$Result,
    [System.DateTimeOffset]$ApprovalDate,
    [System.DateTimeOffset]$GeneratedAt
) {
    $BeforeSnapshotPath = "docs\evidence\p2-win01-installer\machine-cleanup-before.json"
    $AfterSnapshotPath = "docs\evidence\p2-win01-installer\machine-cleanup-after.json"

    if (-not (Test-ExactEvidencePath `
            -Value $Result.before_snapshot `
            -ExpectedRelativePath $BeforeSnapshotPath)) {
        return $false
    }
    if (-not (Test-ExactEvidencePath `
            -Value $Result.after_snapshot `
            -ExpectedRelativePath $AfterSnapshotPath)) {
        return $false
    }

    $BeforeSnapshot = Read-JsonEvidence $BeforeSnapshotPath
    $AfterSnapshot = Read-JsonEvidence $AfterSnapshotPath
    if (($null -eq $BeforeSnapshot) -or ($null -eq $AfterSnapshot)) {
        return $false
    }

    $BeforeCapturedAt = ConvertTo-IsoDateTimeOffset $BeforeSnapshot.captured_at
    $AfterCapturedAt = ConvertTo-IsoDateTimeOffset $AfterSnapshot.captured_at
    if (($null -eq $BeforeCapturedAt) -or
        ($null -eq $AfterCapturedAt) -or
        ($BeforeCapturedAt -lt $ApprovalDate) -or
        ($BeforeCapturedAt -gt $GeneratedAt) -or
        ($AfterCapturedAt -lt $BeforeCapturedAt) -or
        ($AfterCapturedAt -gt $GeneratedAt)) {
        return $false
    }

    if ((-not (Has-BooleanJsonValue $BeforeSnapshot "machine_state_checked" $true)) -or
        (-not (Has-BooleanJsonValue $AfterSnapshot "machine_state_checked" $true))) {
        return $false
    }

    foreach ($PropertyName in @("machine_state_issues", "filesystem_leftovers")) {
        if ((-not (Has-JsonProperty $BeforeSnapshot $PropertyName)) -or
            (-not (Has-JsonProperty $AfterSnapshot $PropertyName))) {
            return $false
        }
    }

    $BeforeResidueCount = @($BeforeSnapshot.machine_state_issues |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count +
        @($BeforeSnapshot.filesystem_leftovers |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    if ($BeforeResidueCount -le 0) {
        return $false
    }

    if (@($AfterSnapshot.machine_state_issues).Count -ne 0) {
        return $false
    }
    if (@($AfterSnapshot.filesystem_leftovers).Count -ne 0) {
        return $false
    }

    return $true
}

function Has-ActionableCleanupPlanResidueGroups([object]$CleanupPlan) {
    if ((-not (Has-JsonProperty $CleanupPlan "residue_groups")) -or
        ($null -eq $CleanupPlan.residue_groups)) {
        return $false
    }

    $ResidueGroups = @($CleanupPlan.residue_groups)
    if ($ResidueGroups.Count -lt 1) {
        return $false
    }

    foreach ($Group in $ResidueGroups) {
        if ([string]::IsNullOrWhiteSpace([string]$Group.affected_path)) {
            return $false
        }
        if (-not (Has-BooleanJsonValue $Group "approval_required" $true)) {
            return $false
        }

        $ResidueEntryCount = @($Group.pending_rename_entries).Count +
            @($Group.registry_entries).Count +
            @($Group.registry_check_failures).Count +
            @($Group.machine_state_entries).Count +
            @($Group.filesystem_leftovers).Count
        if ($ResidueEntryCount -le 0) {
            return $false
        }
    }

    return $true
}

function Add-NonEmptyResidueItemsToSet(
    [System.Collections.Generic.HashSet[string]]$Set,
    [object[]]$Items
) {
    foreach ($Item in @($Items)) {
        $Text = [string]$Item
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            [void]$Set.Add($Text)
        }
    }
}

function Test-CleanupPlanCoversSnapshotResidue(
    [object]$CleanupPlan,
    [object]$BeforeSnapshot
) {
    if (($null -eq $CleanupPlan) -or ($null -eq $BeforeSnapshot)) {
        return $false
    }

    $MachineResidue = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $FilesystemResidue = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    Add-NonEmptyResidueItemsToSet `
        -Set $MachineResidue `
        -Items @($CleanupPlan.machine_state_issues)
    Add-NonEmptyResidueItemsToSet `
        -Set $FilesystemResidue `
        -Items @($CleanupPlan.filesystem_leftovers)

    foreach ($Group in @($CleanupPlan.residue_groups)) {
        Add-NonEmptyResidueItemsToSet -Set $MachineResidue -Items @($Group.pending_rename_entries)
        Add-NonEmptyResidueItemsToSet -Set $MachineResidue -Items @($Group.registry_entries)
        Add-NonEmptyResidueItemsToSet -Set $MachineResidue -Items @($Group.registry_check_failures)
        Add-NonEmptyResidueItemsToSet -Set $MachineResidue -Items @($Group.machine_state_entries)
        Add-NonEmptyResidueItemsToSet -Set $FilesystemResidue -Items @($Group.filesystem_leftovers)
    }

    foreach ($Issue in @($BeforeSnapshot.machine_state_issues)) {
        $Text = [string]$Issue
        if ((-not [string]::IsNullOrWhiteSpace($Text)) -and
            (-not $MachineResidue.Contains($Text))) {
            return $false
        }
    }

    foreach ($Leftover in @($BeforeSnapshot.filesystem_leftovers)) {
        $Text = [string]$Leftover
        if ((-not [string]::IsNullOrWhiteSpace($Text)) -and
            (-not $FilesystemResidue.Contains($Text))) {
            return $false
        }
    }

    $SnapshotMachineResidue = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $SnapshotFilesystemResidue = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    Add-NonEmptyResidueItemsToSet -Set $SnapshotMachineResidue -Items @($BeforeSnapshot.machine_state_issues)
    Add-NonEmptyResidueItemsToSet -Set $SnapshotFilesystemResidue -Items @($BeforeSnapshot.filesystem_leftovers)

    foreach ($Issue in $MachineResidue) {
        if (-not $SnapshotMachineResidue.Contains($Issue)) {
            return $false
        }
    }

    foreach ($Leftover in $FilesystemResidue) {
        if (-not $SnapshotFilesystemResidue.Contains($Leftover)) {
            return $false
        }
    }

    return $true
}

function Has-MachineCleanupCurrentResidueCoverage(
    [string]$ResultJsonPath,
    [System.DateTimeOffset]$ApprovalDate,
    [string]$ApprovalInstallDir
) {
    $ResultFullPath = Repo-Path $ResultJsonPath
    if (-not (Test-Path -LiteralPath $ResultFullPath)) {
        return $false
    }

    try {
        $Result = Get-Content -Raw -LiteralPath $ResultFullPath | ConvertFrom-Json
    }
    catch {
        return $false
    }

    if ($Result.status -ne "passed") {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Result "machine_state_changed_before_approval" $false)) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $Result "approval_required" $true)) {
        return $false
    }
    if (@($Result.remaining_machine_state_issues).Count -ne 0) {
        return $false
    }
    if (@($Result.remaining_filesystem_leftovers).Count -ne 0) {
        return $false
    }
    if (@($Result.errors).Count -ne 0) {
        return $false
    }

    $GeneratedAt = ConvertTo-IsoDateTimeOffset $Result.generated_at
    if (($null -eq $GeneratedAt) -or ($GeneratedAt -lt $ApprovalDate)) {
        return $false
    }
    if (-not (Has-MachineCleanupSnapshotEvidence `
            -Result $Result `
            -ApprovalDate $ApprovalDate `
            -GeneratedAt $GeneratedAt)) {
        return $false
    }

    $CleanupPlanPath = "docs\evidence\p2-win01-installer\machine-cleanup-plan.json"
    if (-not (Test-CleanupPlanEvidencePath $Result.cleanup_plan)) {
        return $false
    }

    $CleanupPlan = Read-JsonEvidence $CleanupPlanPath
    if ($null -eq $CleanupPlan) {
        return $false
    }

    $CleanupPlanGeneratedAt = ConvertTo-IsoDateTimeOffset $CleanupPlan.generated_at
    $ResultCleanupPlanGeneratedAt = ConvertTo-IsoDateTimeOffset $Result.cleanup_plan_generated_at
    if (($null -eq $CleanupPlanGeneratedAt) -or
        ($null -eq $ResultCleanupPlanGeneratedAt) -or
        ($CleanupPlanGeneratedAt -gt $GeneratedAt) -or
        ($ResultCleanupPlanGeneratedAt -ne $CleanupPlanGeneratedAt)) {
        return $false
    }

    if ([string]$CleanupPlan.residue_detector -ne "Get-YuneWindowsMachineResidue") {
        return $false
    }
    if ([string]$Result.cleanup_plan_residue_detector -ne [string]$CleanupPlan.residue_detector) {
        return $false
    }

    if (-not (Test-SameWindowsPath `
            -First ([string]$CleanupPlan.install_dir) `
            -Second $ApprovalInstallDir)) {
        return $false
    }

    if (-not (Has-BooleanJsonValue $CleanupPlan "machine_state_changed" $false)) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $CleanupPlan "machine_state_checked" $true)) {
        return $false
    }
    if (-not (Has-BooleanJsonValue $CleanupPlan "requires_current_session_approval" $true)) {
        return $false
    }
    if ((-not (Has-JsonProperty $CleanupPlan "residue_groups")) -or
        ($null -eq $CleanupPlan.residue_groups)) {
        return $false
    }
    if (-not (Has-ActionableCleanupPlanResidueGroups $CleanupPlan)) {
        return $false
    }

    $BeforeSnapshot = Read-JsonEvidence "docs\evidence\p2-win01-installer\machine-cleanup-before.json"
    if (-not (Test-CleanupPlanCoversSnapshotResidue `
            -CleanupPlan $CleanupPlan `
            -BeforeSnapshot $BeforeSnapshot)) {
        return $false
    }

    if (-not (Has-IntegerJsonProperty $Result "cleanup_plan_residue_group_count")) {
        return $false
    }
    $ResidueGroupCount = [long]$Result.PSObject.Properties["cleanup_plan_residue_group_count"].Value
    if ($ResidueGroupCount -lt 1) {
        return $false
    }
    $PlanResidueGroupCount = @($CleanupPlan.residue_groups).Count
    if ($ResidueGroupCount -ne $PlanResidueGroupCount) {
        return $false
    }

    if (-not (Has-BooleanJsonProperty $Result "cleanup_plan_current_residue_covered")) {
        return $false
    }

    return $Result.PSObject.Properties["cleanup_plan_current_residue_covered"].Value -eq $true
}

function Get-MachineCleanupApprovalEvidenceStatus {
    $Result = "docs\evidence\p2-win01-installer\machine-cleanup-result.md"
    if (-not (Has-Path $Result)) {
        return "missing"
    }

    $Evidence = "docs\evidence\p2-win01-installer\machine-cleanup-approval.md"
    if (-not (Has-Path $Evidence)) {
        return "invalid"
    }

    $RequiredPatterns = @(
        'Date:\s*\d{4}-\d{2}-\d{2}T',
        'Approval note:\s*\S',
        'Machine state changed before approval evidence:\s*false',
        'Administrator:\s*True',
        'STA:\s*True',
        'Install dir:\s*\S',
        'Yune root:\s*\S',
        'Browser path:\s*\S'
    )
    foreach ($Pattern in $RequiredPatterns) {
        if (-not (File-Contains $Evidence $Pattern)) {
            return "invalid"
        }
    }

    $ApprovalNote = Get-ApprovalEvidenceField $Evidence "Approval note"
    if (Test-IsPlaceholderApprovalNote -ApprovalNote $ApprovalNote) {
        return "invalid"
    }

    if (-not (Test-ApprovalEvidencePathsAreConcrete -Evidence $Evidence)) {
        return "invalid"
    }

    $ResultDate = Get-IsoDateEvidenceValue $Result
    $ApprovalDate = Get-IsoDateEvidenceValue $Evidence
    if (($null -eq $ResultDate) -or
        ($null -eq $ApprovalDate) -or
        ($ResultDate -lt $ApprovalDate)) {
        return "invalid"
    }
    if ((-not (File-Contains $Result "^Status:\s*passed\s*$")) -or
        (File-Contains $Result "^Status:\s*failed\s*$")) {
        return "invalid"
    }

    $ResultJsonPath = "docs\evidence\p2-win01-installer\machine-cleanup-result.json"
    $ResultJson = Read-JsonEvidence $ResultJsonPath
    if ($null -eq $ResultJson) {
        return "invalid"
    }
    $ResultJsonGeneratedAt = ConvertTo-IsoDateTimeOffset $ResultJson.generated_at
    if (($null -eq $ResultJsonGeneratedAt) -or ($ResultDate -lt $ResultJsonGeneratedAt)) {
        return "invalid"
    }

    if (-not (Has-MachineCleanupCurrentResidueCoverage `
            $ResultJsonPath `
            $ApprovalDate `
            (Get-ApprovalEvidenceField $Evidence "Install dir"))) {
        return "invalid"
    }

    return "complete"
}

function Get-ApprovalDisciplineStatus {
    $Evidence = "docs\evidence\p2-win01-tsf-smoke\machine-state-gates.md"
    if (-not (Has-Path $Evidence)) {
        return "missing"
    }

    $RequiredPatterns = @(
        'Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs',
        'install-yune-windows-ime\.ps1',
        'uninstall-yune-windows-ime\.ps1',
        'clear-yune-windows-machine-residue\.ps1',
        'run-notepad-smoke\.ps1',
        'run-chromium-smoke\.ps1',
        'run-p2-win01-live-smoke\.ps1',
        'without.*ApprovedMachineStateChange',
        'before registration',
        'Notepad automation',
        'Chromium automation',
        'full live-sequence orchestration',
        'machine residue cleanup',
        'blank or approval-brief placeholder approval notes',
        'without.*ApprovalNote',
        'full live sequence.*blank or approval-brief placeholder approval notes',
        'post-approval context checks',
        'command transcript writes',
        'cleanup'
    )

    foreach ($Pattern in $RequiredPatterns) {
        if (-not (File-Contains $Evidence $Pattern)) {
            return "invalid"
        }
    }

    $MachineCleanupApprovalStatus = Get-MachineCleanupApprovalEvidenceStatus
    if ($MachineCleanupApprovalStatus -eq "invalid") {
        return "invalid"
    }

    $LiveApprovalStatus = Get-LiveApprovalEvidenceStatus
    if ($LiveApprovalStatus -eq "missing") {
        return "preflight"
    }
    if ($LiveApprovalStatus -ne "complete") {
        return "invalid"
    }

    return "complete"
}

function Get-ApprovalBriefAdvisoryIssue {
    $BriefPath = "docs\evidence\p2-win01-installer\approval-brief.md"
    if (-not (Has-Path $BriefPath)) {
        return ""
    }

    $Issues = [System.Collections.Generic.List[string]]::new()
    $BriefDate = Get-IsoDateEvidenceValue $BriefPath
    $PrepValidationPath = "docs\evidence\p2-win01-installer\elevated-live-smoke-prep-validation-result.json"
    $PrepValidation = Read-JsonEvidence $PrepValidationPath
    if ($null -ne $PrepValidation) {
        $PrepGeneratedAt = ConvertTo-IsoDateTimeOffset $PrepValidation.generated_at
        if (($null -ne $BriefDate) -and
            ($null -ne $PrepGeneratedAt) -and
            ($BriefDate -lt $PrepGeneratedAt)) {
            $Issues.Add("approval brief is stale relative to latest prep validation")
        }

        $PrepBooleanIssueNames = Get-JsonBooleanSchemaIssueNames `
            -Evidence $PrepValidation `
            -Names @(
                "approved_machine_state_change",
                "elevated_process_started",
                "transcript_exists",
                "machine_state_changed_before_elevated_process"
            )
        if ($PrepBooleanIssueNames.Count -gt 0) {
            $Issues.Add("latest prep-validation boolean fields are not JSON booleans: $($PrepBooleanIssueNames -join ', ')")
        }

        $PrepStatus = [string]$PrepValidation.status
        if ((-not [string]::IsNullOrWhiteSpace($PrepStatus)) -and
            ($PrepStatus -ne "prep-preflight-ready") -and
            (File-Contains $BriefPath "Prep validation status:\s*prep-preflight-ready")) {
            $Issues.Add("approval brief prep-validation status disagrees with latest prep validation")
        }
    }

    if (File-Contains $BriefPath "Current residue source:\s*.*live-preflight\.json") {
        $Issues.Add("approval brief uses live-preflight.json as current-residue evidence")
    }

    $LiveLauncherPath = "docs\evidence\p2-win01-installer\elevated-live-smoke-launch-result.json"
    $LiveLauncher = Read-JsonEvidence $LiveLauncherPath
    if ($null -ne $LiveLauncher) {
        $LauncherGeneratedAt = ConvertTo-IsoDateTimeOffset $LiveLauncher.generated_at
        if (($null -ne $BriefDate) -and
            ($null -ne $LauncherGeneratedAt) -and
            ($BriefDate -lt $LauncherGeneratedAt)) {
            $Issues.Add("approval brief is stale relative to latest single-UAC launcher")
        }

        $LauncherStatus = [string]$LiveLauncher.status
        $LauncherBooleanIssueNames = Get-JsonBooleanSchemaIssueNames `
            -Evidence $LiveLauncher `
            -Names @(
                "approved_machine_state_change",
                "elevated_process_started",
                "transcript_exists",
                "machine_state_changed_before_elevated_process"
            )
        if ($LauncherBooleanIssueNames.Count -gt 0) {
            $Issues.Add("latest single-UAC launcher boolean fields are not JSON booleans: $($LauncherBooleanIssueNames -join ', ')")
        }
        $StartedProperty = $LiveLauncher.PSObject.Properties["elevated_process_started"]
        $StartedFalse = ($null -ne $StartedProperty) -and
            ($StartedProperty.Value -is [bool]) -and
            ($StartedProperty.Value -eq $false)
        $StartedTrue = ($null -ne $StartedProperty) -and
            ($StartedProperty.Value -is [bool]) -and
            ($StartedProperty.Value -eq $true)
        $TranscriptExistsProperty = $LiveLauncher.PSObject.Properties["transcript_exists"]
        $TranscriptExists = $false
        if (($null -ne $TranscriptExistsProperty) -and
            ($TranscriptExistsProperty.Value -is [bool])) {
            $TranscriptExists = [bool]$TranscriptExistsProperty.Value
        } else {
            $TranscriptPath = [string]$LiveLauncher.transcript_path
            if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
                try {
                    $ResolvedTranscriptPath = if ([System.IO.Path]::IsPathRooted($TranscriptPath)) {
                        [System.IO.Path]::GetFullPath($TranscriptPath)
                    } else {
                        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $TranscriptPath))
                    }
                    $TranscriptExists = Test-Path -LiteralPath $ResolvedTranscriptPath -PathType Leaf
                }
                catch {
                    $TranscriptExists = $false
                }
            }
        }
        if ($StartedFalse -and ($LauncherStatus -in @("elevation-canceled", "failed-to-start"))) {
            $Issues.Add("latest single-UAC launcher did not start; fresh approval is required before retry")
        }
        if ((-not $StartedTrue) -and
            (-not $StartedFalse) -and
            ($LauncherStatus -in @("elevation-canceled", "failed-to-start"))) {
            $Issues.Add("latest single-UAC launcher did not start; fresh approval is required before retry")
        }
        if ($StartedTrue -and (-not $TranscriptExists)) {
            $Issues.Add("latest single-UAC launcher started without transcript evidence")
        }
    }

    if ($Issues.Count -eq 0) {
        return ""
    }

    return "Approval-brief advisory issue: $($Issues -join '; ')."
}

function Get-ApprovalDisciplineNotes([string]$Status) {
    $RefusalEvidence = "Unapproved install, uninstall, Notepad smoke, Chromium smoke, live sequence, and machine residue cleanup runs refuse; standalone approved scripts and the full live sequence reject blank or approval-brief placeholder approval notes before post-approval context checks or machine-state work"
    $ApprovalBriefIssue = Get-ApprovalBriefAdvisoryIssue
    $ApprovalBriefSuffix = if ([string]::IsNullOrWhiteSpace($ApprovalBriefIssue)) { "" } else { " $ApprovalBriefIssue" }
    if ($Status -eq "complete") {
        return "$RefusalEvidence; approved live evidence records current-session approval plus administrator/STA context before machine-state work.$ApprovalBriefSuffix"
    }
    if ($Status -eq "invalid") {
        return "$RefusalEvidence; approval evidence is incomplete, stale, placeholder, path-invalid, or mismatched with approved cleanup/live result evidence.$ApprovalBriefSuffix"
    }
    if ($Status -eq "missing") {
        return "Missing machine-state refusal evidence for unapproved install, uninstall, cleanup, Notepad, Chromium, and live sequence commands.$ApprovalBriefSuffix"
    }

    return "$RefusalEvidence; Complete approval-discipline closeout requires approved live evidence in approval.md to record current-session approval plus administrator/STA context before machine-state work. Approved cleanup result evidence, when present, must have matching machine-cleanup-approval.md before cleanup work.$ApprovalBriefSuffix"
}

$Gates = @()
function Add-Gate(
    [string]$Id,
    [string]$Requirement,
    [string]$Status,
    [string]$Evidence,
    [string]$Notes
) {
    $script:Gates += [ordered]@{
        id = $Id
        requirement = $Requirement
        status = $Status
        evidence = $Evidence
        notes = $Notes
    }
}

$NotepadSmokeStatus = Get-NotepadSmokeStatus
$ChromiumSmokeStatus = Get-ChromiumSmokeStatus
$CandidateDisplayStatus = Get-CandidateDisplayStatus `
    -NotepadStatus $NotepadSmokeStatus `
    -ChromiumStatus $ChromiumSmokeStatus
$TsfServerIpcStatus = Get-TsfServerIpcStatus -NotepadStatus $NotepadSmokeStatus
$InstallActivationStatus = Get-InstallActivationStatus
$DiagnosticsStatus = Get-DiagnosticsStatus
$CleanupStatus = Get-CleanupStatus
$ApprovalDisciplineStatus = Get-ApprovalDisciplineStatus
$LivePreflightStatus = Get-LivePreflightStatus

Add-Gate `
    "repo-reference-audit" `
    "repo state, reference audit, process model, and first smoke target" `
    ($(if ((Has-Path "docs\evidence\p2-win01-bootstrap\repo-state.md") -and
           (Has-Path "docs\evidence\p2-win01-bootstrap\reference-audit.md") -and
           (Has-Path "docs\evidence\p2-win01-bootstrap\process-model.md") -and
           (Has-Path "docs\evidence\p2-win01-bootstrap\first-smoke-target.md")) { "complete" } else { "missing" })) `
    "docs/evidence/p2-win01-bootstrap/" `
    "Task 0/1 evidence."

Add-Gate `
    "yune-host-smoke" `
    "packaged Yune host processes ngohaig with jyut6ping3" `
    ($(if ((Has-Path "docs\evidence\p2-win01-yune-host\result.json") -and
           (File-Contains "docs\evidence\p2-win01-yune-host\result.json" '"schema_id": "jyut6ping3"')) { "complete" } else { "missing" })) `
    "docs/evidence/p2-win01-yune-host/result.json" `
    "Task 2 host smoke evidence."

Add-Gate `
    "tsf-server-ipc-preflight" `
    "shared server returns non-raw Yune candidate over IPC" `
    $TsfServerIpcStatus `
    "docs/evidence/p2-win01-tsf-smoke/server-ipc-smoke.md" `
    ($(if ($TsfServerIpcStatus -eq "complete") { "Preflight is backed by approved live Notepad commit evidence." } else { "Non-elevated preflight only; does not close TSF registration." }))

Add-Gate `
    "tsf-notepad-smoke" `
    "Notepad receives committed candidate text from Yune after profile activation" `
    $NotepadSmokeStatus `
    "docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md" `
    ($(if ($NotepadSmokeStatus -eq "complete") { "Approved installed Notepad smoke passed after profile activation." } else { "Requires approved install/register/profile activation." }))

Add-Gate `
    "candidate-display-live" `
    "native candidate display and candidate commit are proven live" `
    $CandidateDisplayStatus `
    "docs/evidence/p2-win01-candidate-window/" `
    ($(if ($CandidateDisplayStatus -eq "complete") { "Live Notepad and Chromium evidence includes candidate display screenshots and committed text." } else { "Build preflight exists; live display proof is still needed." }))

Add-Gate `
    "chromium-text-field-smoke" `
    "one Chromium-based text field accepts committed Yune candidate text" `
    $ChromiumSmokeStatus `
    "docs/evidence/p2-win01-tsf-smoke/chromium-smoke-result.md" `
    ($(if ($ChromiumSmokeStatus -eq "complete") { "Approved installed Chromium smoke passed after profile activation." } else { "Harness exists; approved browser/profile automation still pending." }))

Add-Gate `
    "fresh-install-registration-activation" `
    "fresh install, TSF registration, and YuneWindows profile activation are proven" `
    $InstallActivationStatus `
    "docs/evidence/p2-win01-installer/result.md" `
    ($(if ($InstallActivationStatus -eq "complete") { "Approved install/register/profile activation evidence is recorded." } else { "Requires approved install/register smoke." }))

Add-Gate `
    "diagnostics-export" `
    "diagnostics/log export produces a support bundle" `
    $DiagnosticsStatus `
    "docs/evidence/p2-win01-settings/diagnostics-export.md" `
    ($(if ($DiagnosticsStatus -eq "complete") { "Registered-session diagnostics bundle is recorded." } else { "Non-elevated diagnostics export preflight exists; live registered-session export still pending." }))

Add-Gate `
    "uninstall-cleanup" `
    "uninstall and cleanup verification leave no YuneWindows machine state" `
    $CleanupStatus `
    "docs/evidence/p2-win01-installer/cleanup-result.md" `
    ($(if ($CleanupStatus -eq "complete") { "Approved uninstall plus post-reboot cleanup validation left no residue." } else { "Requires approved unregister/uninstall/cleanup smoke." }))

Add-Gate `
    "settings-decision" `
    "settings/WebView2 decision is evidence-backed and exposes no placeholder controls" `
    ($(if ((Has-Path "docs\evidence\p2-win01-settings\webview2-spike.md") -and
           (File-Contains "docs\evidence\p2-win01-settings\webview2-spike.md" 'Decision: `defer-settings`')) { "complete" } else { "missing" })) `
    "docs/evidence/p2-win01-settings/webview2-spike.md" `
    "Decision is defer-settings for P2-WIN01."

Add-Gate `
    "approval-discipline" `
    "machine-state scripts require explicit approval" `
    $ApprovalDisciplineStatus `
    "docs/evidence/p2-win01-tsf-smoke/machine-state-gates.md; docs/evidence/p2-win01-installer/approval.md; docs/evidence/p2-win01-installer/machine-cleanup-approval.md" `
    (Get-ApprovalDisciplineNotes $ApprovalDisciplineStatus)

Add-Gate `
    "live-preflight" `
    "non-mutating install/live-smoke preflight evidence is captured" `
    $LivePreflightStatus `
    "docs/evidence/p2-win01-installer/live-preflight.json" `
    (Get-LivePreflightNotes $LivePreflightStatus)

$SourceText = ""
foreach ($Root in @("src", "tools")) {
    $Path = Join-Path $SourceRoot $Root
    if (Test-Path -LiteralPath $Path) {
        $SourceText += (Get-ChildItem -LiteralPath $Path -Recurse -File |
            Where-Object {
                $_.Extension -in @(".cpp", ".h", ".ps1") -and
                $_.Name -notlike "test-*" -and
                $_.Name -notlike "audit-*"
            } |
            ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
    }
}
$HasLibrimeFallback = $SourceText -match "librime"
$HasDefaultAbiWidening = $SourceText -match "rime_get_api\(\).*YuneWindows"
$HasForbiddenProductEngineClaim = Has-ForbiddenProductEngineClaim

Add-Gate `
    "engine-boundary" `
    "Yune remains the only runtime engine, with no librime fallback or default ABI widening" `
    ($(if (-not $HasLibrimeFallback -and -not $HasDefaultAbiWidening) { "complete" } else { "missing" })) `
    "src/ and tools/ search" `
    "Audit checks implementation sources for librime fallback/default ABI widening markers."

Add-Gate `
    "product-engine-claim-split" `
    "Windows product evidence does not close Yune M38 engine work" `
    ($(if (-not $HasForbiddenProductEngineClaim) { "complete" } else { "invalid" })) `
    "docs/ and docs/evidence/ search" `
    "Audit rejects claims that misattribute Yune M38 closeout to Windows product evidence."

$OverallStatus = if (@($Gates | Where-Object { $_.status -ne "complete" }).Count -eq 0) {
    "complete"
} else {
    "incomplete"
}

$GeneratedAt = (Get-Date).ToString("o")
$Result = [ordered]@{
    generated_at = $GeneratedAt
    status = $OverallStatus
    gates = $Gates
}

New-Item -ItemType Directory -Force (Split-Path -Parent $JsonPath) | Out-Null
New-Item -ItemType Directory -Force (Split-Path -Parent $MarkdownPath) | Out-Null
$Result | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $JsonPath -Encoding utf8

$Lines = @(
    "# P2-WIN01 Closeout Audit",
    "",
    "Date: $GeneratedAt",
    "",
    "Status: $OverallStatus.",
    "",
    "| Gate | Status | Evidence | Notes |",
    "| --- | --- | --- | --- |"
)
foreach ($Gate in $Gates) {
    $Lines += "| $($Gate.id) | $($Gate.status) | $($Gate.evidence) | $($Gate.notes) |"
}
$Lines += ""
if ($OverallStatus -eq "complete") {
    $Lines += "P2-WIN01 closeout gates are complete."
} else {
    $Lines += "P2-WIN01 must remain open until every gate is complete."
}
$Lines | Out-File -LiteralPath $MarkdownPath -Encoding utf8

Write-Output $JsonPath
Write-Output $MarkdownPath

if ($RequireComplete -and $OverallStatus -ne "complete") {
    $IncompleteGates = @($Gates |
        Where-Object { $_.status -ne "complete" } |
        ForEach-Object { "$($_.id)=$($_.status)" })
    throw "P2-WIN01 closeout audit incomplete: $($IncompleteGates -join ', ')"
}
