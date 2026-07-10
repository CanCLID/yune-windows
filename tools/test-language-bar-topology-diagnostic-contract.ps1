param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Diagnostic = Join-Path $RepoRoot "tools\dev\capture-language-bar-topology.ps1"
if (-not (Test-Path -LiteralPath $Diagnostic -PathType Leaf)) {
    throw "Language-bar topology diagnostic is missing: $Diagnostic"
}

$Source = Get-Content -Raw -LiteralPath $Diagnostic
foreach ($Required in @(
        'YuneWindowsLanguageBar',
        'EnumWindows',
        'GetClassNameW',
        'GetWindowThreadProcessId',
        'GetWindowRect',
        'DwmGetWindowAttribute',
        'GetWindowLongPtrW',
        'GetAncestor',
        'GetForegroundWindow',
        'GetGUIThreadInfo',
        'captured_at_utc',
        'process_name',
        'dwm_frame',
        'root_owner_hwnd',
        'root_owner_matches_foreground_root_owner',
        'extended_style',
        'capture'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "Language-bar topology diagnostic is missing required pattern: $Required"
    }
}

foreach ($Forbidden in @(
        'GetWindowText',
        'GetWindowTextLength',
        'MainWindowTitle',
        'SendMessage',
        'PostMessage',
        'SetWindowPos',
        'MoveWindow',
        'ShowWindow',
        'SetForegroundWindow',
        'SetCapture',
        'ReleaseCapture',
        'keybd_event',
        'SendInput'
    )) {
    if ($Source -match [regex]::Escape($Forbidden)) {
        throw "Language-bar topology diagnostic must remain privacy-safe and read-only: $Forbidden"
    }
}

$Tokens = $null
$ParseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $Diagnostic,
    [ref]$Tokens,
    [ref]$ParseErrors)
if ($ParseErrors.Count -ne 0) {
    throw "Language-bar topology diagnostic has PowerShell parse errors: $($ParseErrors -join '; ')"
}

$Json = (& $Diagnostic | Out-String).Trim()
try {
    $Report = $Json | ConvertFrom-Json
}
catch {
    throw "Language-bar topology diagnostic did not emit valid JSON: $($_.Exception.Message)"
}

foreach ($Property in @(
        'schema_version',
        'captured_at_utc',
        'class_names',
        'privacy_note',
        'foreground',
        'window_count',
        'windows'
    )) {
    if ($Report.PSObject.Properties.Name -notcontains $Property) {
        throw "Language-bar topology report is missing property: $Property"
    }
}

$CapturedAt = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse(
        [string]$Report.captured_at_utc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$CapturedAt)) {
    throw "Language-bar topology report timestamp is not an ISO-8601 round-trip value."
}

$Windows = @($Report.windows)
if ([int]$Report.window_count -ne $Windows.Count) {
    throw "Language-bar topology report window_count does not match windows array."
}

foreach ($Property in @('hwnd', 'root_hwnd', 'root_owner_hwnd')) {
    if ($Report.foreground.PSObject.Properties.Name -notcontains $Property) {
        throw "Language-bar topology foreground entry is missing property: $Property"
    }
}

foreach ($Window in $Windows) {
    foreach ($Property in @(
            'hwnd',
            'hwnd_hex',
            'class_name',
            'process_id',
            'thread_id',
            'process_name',
            'visible',
            'rect',
            'dwm_frame',
            'ownership',
            'foreground',
            'extended_style',
            'capture'
        )) {
        if ($Window.PSObject.Properties.Name -notcontains $Property) {
            throw "Language-bar topology window entry is missing property: $Property"
        }
    }

    if ($Window.class_name -ne 'YuneWindowsLanguageBar' -and
        $Window.class_name -notlike 'YuneWindowsLanguageBar_*') {
        throw "Language-bar topology report included an unexpected class: $($Window.class_name)"
    }

    foreach ($Property in @('owner_hwnd', 'root_hwnd', 'root_owner_hwnd')) {
        if ($Window.ownership.PSObject.Properties.Name -notcontains $Property) {
            throw "Language-bar topology ownership entry is missing property: $Property"
        }
    }
    foreach ($Property in @(
            'root_owner_hwnd',
            'root_owner_matches_foreground_root',
            'root_owner_matches_foreground_root_owner'
        )) {
        if ($Window.foreground.PSObject.Properties.Name -notcontains $Property) {
            throw "Language-bar topology foreground comparison is missing property: $Property"
        }
    }
    if ([bool]$Window.foreground.root_owner_matches_foreground_root -ne
        [bool]$Window.foreground.root_owner_matches_foreground_root_owner) {
        throw "Compatibility foreground-root match must use foreground root-owner semantics."
    }
    foreach ($Property in @('value', 'hex', 'flags')) {
        if ($Window.extended_style.PSObject.Properties.Name -notcontains $Property) {
            throw "Language-bar topology extended_style entry is missing property: $Property"
        }
    }
    foreach ($Property in @('gui_thread_info_available', 'hwnd', 'hwnd_hex', 'is_this_window')) {
        if ($Window.capture.PSObject.Properties.Name -notcontains $Property) {
            throw "Language-bar topology capture entry is missing property: $Property"
        }
    }
}

if ($Json -match '"(?:title|text|keystrokes?)"\s*:') {
    throw "Language-bar topology report must not expose title, text, or keystroke fields."
}

Write-Host "Language-bar topology diagnostic emits privacy-safe read-only JSON for $($Windows.Count) matching window(s)."
