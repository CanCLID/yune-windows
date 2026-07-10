param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateSet("initial", "minimum", "minimum_scrolled", "larger", "reopened")]
    [string]$Phase = "initial",

    [ValidateSet("unknown", "light", "dark")]
    [string]$Theme = "unknown",

    [ValidateSet("pending", "pass", "fail")]
    [string]$InitialViewportUsable = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$AllControlsReachable = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$NoOverlapOrClipping = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$TypographyLegibleAndCrisp = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$CantoneseOnly = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$NativeEffectOrFlatFallbackUsable = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$NoFocusTheft = "pending",

    [ValidateSet("pending", "pass", "fail")]
    [string]$CloseReopenStableNoOrphan = "pending",

    [string]$OperatorNote = ""
)

$ErrorActionPreference = "Stop"

$FullOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($FullOutputPath) -ne ".json") {
    throw "-OutputPath must name a .json file."
}
$OutputDirectory = Split-Path -Parent $FullOutputPath
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw "-OutputPath must include a parent directory."
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

if (-not ("YuneWindows.Dev.M10SettingsGeometryNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace YuneWindows.Dev {
    public delegate bool M10EnumWindowsProc(IntPtr hwnd, IntPtr lparam);

    [StructLayout(LayoutKind.Sequential)]
    public struct M10Rect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct M10Point {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct M10ScrollInfo {
        public uint cbSize;
        public uint fMask;
        public int nMin;
        public int nMax;
        public uint nPage;
        public int nPos;
        public int nTrackPos;
    }

    public static class M10SettingsGeometryNative {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(M10EnumWindowsProc callback, IntPtr lparam);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumChildWindows(IntPtr parent, M10EnumWindowsProc callback, IntPtr lparam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetClassNameW(IntPtr hwnd, StringBuilder className, int maxCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowEnabled(IntPtr hwnd);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hwnd, out M10Rect rect);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetClientRect(IntPtr hwnd, out M10Rect rect);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ClientToScreen(IntPtr hwnd, ref M10Point point);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32.dll")]
        public static extern uint GetDpiForWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLong32(IntPtr hwnd, int index);

        public static long GetWindowLongValue(IntPtr hwnd, int index) {
            return IntPtr.Size == 8
                ? GetWindowLongPtr64(hwnd, index).ToInt64()
                : GetWindowLong32(hwnd, index);
        }

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetScrollInfo(IntPtr hwnd, int bar, ref M10ScrollInfo info);
    }
}
"@
}

$SettingsClassName = "YuneWindowsSettingsWindow"
$GwlStyle = -16
$GwlExStyle = -20
$SbHorz = 0
$SbVert = 1
$SifAll = [uint32]0x17
$WsThickFrame = [int64]0x00040000
$WsMaximizeBox = [int64]0x00010000
$WsHScroll = [int64]0x00100000
$WsVScroll = [int64]0x00200000
$ForegroundWindow = [YuneWindows.Dev.M10SettingsGeometryNative]::GetForegroundWindow()

function Format-Handle([IntPtr]$Handle) {
    if ($Handle -eq [IntPtr]::Zero) {
        return "0x0"
    }
    return "0x$($Handle.ToInt64().ToString('X'))"
}

function New-RectSnapshot(
    [YuneWindows.Dev.M10Rect]$Rect,
    [bool]$Available) {
    return [pscustomobject][ordered]@{
        available = $Available
        left = if ($Available) { $Rect.Left } else { 0 }
        top = if ($Available) { $Rect.Top } else { 0 }
        right = if ($Available) { $Rect.Right } else { 0 }
        bottom = if ($Available) { $Rect.Bottom } else { 0 }
        width = if ($Available) { $Rect.Right - $Rect.Left } else { 0 }
        height = if ($Available) { $Rect.Bottom - $Rect.Top } else { 0 }
    }
}

function Get-ProcessNameSafely([uint32]$ProcessId) {
    try {
        return [string](Get-Process -Id $ProcessId -ErrorAction Stop).ProcessName
    }
    catch {
        return ""
    }
}

function Get-ScrollSnapshot([IntPtr]$Window, [int]$Bar) {
    $Info = [YuneWindows.Dev.M10ScrollInfo]::new()
    $Info.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf(
        [type][YuneWindows.Dev.M10ScrollInfo])
    $Info.fMask = $SifAll
    $Available = [YuneWindows.Dev.M10SettingsGeometryNative]::GetScrollInfo(
        $Window,
        $Bar,
        [ref]$Info)
    $CanScroll = [bool](
        $Available -and
        ($Info.nMax - $Info.nMin + 1) -gt [int64]$Info.nPage)
    $MaximumPosition = if ($Available) {
        [Math]::Max($Info.nMin, $Info.nMax - [int]$Info.nPage + 1)
    }
    else {
        0
    }
    return [pscustomobject][ordered]@{
        available = [bool]$Available
        minimum = if ($Available) { $Info.nMin } else { 0 }
        maximum = if ($Available) { $Info.nMax } else { 0 }
        page = if ($Available) { $Info.nPage } else { 0 }
        position = if ($Available) { $Info.nPos } else { 0 }
        track_position = if ($Available) { $Info.nTrackPos } else { 0 }
        can_scroll = $CanScroll
        maximum_position = $MaximumPosition
        at_end = [bool]($CanScroll -and $Info.nPos -ge $MaximumPosition)
    }
}

$Windows = [Collections.Generic.List[object]]::new()
$Callback = [YuneWindows.Dev.M10EnumWindowsProc] {
    param([IntPtr]$Window, [IntPtr]$LParam)

    $ClassNameBuilder = [Text.StringBuilder]::new(256)
    $ClassLength = [YuneWindows.Dev.M10SettingsGeometryNative]::GetClassNameW(
        $Window,
        $ClassNameBuilder,
        $ClassNameBuilder.Capacity)
    if ($ClassLength -le 0 -or $ClassNameBuilder.ToString() -ne $SettingsClassName) {
        return $true
    }

    $ProcessId = [uint32]0
    $ThreadId = [YuneWindows.Dev.M10SettingsGeometryNative]::GetWindowThreadProcessId(
        $Window,
        [ref]$ProcessId)
    $WindowRect = [YuneWindows.Dev.M10Rect]::new()
    $WindowRectAvailable = [YuneWindows.Dev.M10SettingsGeometryNative]::GetWindowRect(
        $Window,
        [ref]$WindowRect)
    $ClientRect = [YuneWindows.Dev.M10Rect]::new()
    $ClientRectAvailable = [YuneWindows.Dev.M10SettingsGeometryNative]::GetClientRect(
        $Window,
        [ref]$ClientRect)
    $ClientOrigin = [YuneWindows.Dev.M10Point]::new()
    $ClientOriginAvailable = [YuneWindows.Dev.M10SettingsGeometryNative]::ClientToScreen(
        $Window,
        [ref]$ClientOrigin)

    $VisibleChildren = [Collections.Generic.List[object]]::new()
    $ChildCallback = [YuneWindows.Dev.M10EnumWindowsProc] {
        param([IntPtr]$Child, [IntPtr]$ChildLParam)

        if (-not [YuneWindows.Dev.M10SettingsGeometryNative]::IsWindowVisible($Child)) {
            return $true
        }
        $ChildClassBuilder = [Text.StringBuilder]::new(256)
        [void][YuneWindows.Dev.M10SettingsGeometryNative]::GetClassNameW(
            $Child,
            $ChildClassBuilder,
            $ChildClassBuilder.Capacity)
        $ChildRect = [YuneWindows.Dev.M10Rect]::new()
        $ChildRectAvailable = [YuneWindows.Dev.M10SettingsGeometryNative]::GetWindowRect(
            $Child,
            [ref]$ChildRect)
        $FullyWithinClient = $false
        if ($ChildRectAvailable -and $ClientRectAvailable -and $ClientOriginAvailable) {
            $ClientRight = $ClientOrigin.X + ($ClientRect.Right - $ClientRect.Left)
            $ClientBottom = $ClientOrigin.Y + ($ClientRect.Bottom - $ClientRect.Top)
            $FullyWithinClient =
                $ChildRect.Left -ge $ClientOrigin.X -and
                $ChildRect.Top -ge $ClientOrigin.Y -and
                $ChildRect.Right -le $ClientRight -and
                $ChildRect.Bottom -le $ClientBottom
        }
        $VisibleChildren.Add([pscustomobject][ordered]@{
                hwnd_hex = Format-Handle $Child
                class_name = $ChildClassBuilder.ToString()
                enabled = [bool][YuneWindows.Dev.M10SettingsGeometryNative]::IsWindowEnabled($Child)
                rect = New-RectSnapshot -Rect $ChildRect -Available $ChildRectAvailable
                fully_within_client = [bool]$FullyWithinClient
            })
        return $true
    }
    [void][YuneWindows.Dev.M10SettingsGeometryNative]::EnumChildWindows(
        $Window,
        $ChildCallback,
        [IntPtr]::Zero)

    $Style = [YuneWindows.Dev.M10SettingsGeometryNative]::GetWindowLongValue(
        $Window,
        $GwlStyle)
    $ExtendedStyle = [YuneWindows.Dev.M10SettingsGeometryNative]::GetWindowLongValue(
        $Window,
        $GwlExStyle)
    $Windows.Add([pscustomobject][ordered]@{
            hwnd_hex = Format-Handle $Window
            process_id = $ProcessId
            thread_id = $ThreadId
            process_name = Get-ProcessNameSafely $ProcessId
            visible = [bool][YuneWindows.Dev.M10SettingsGeometryNative]::IsWindowVisible($Window)
            foreground = ($Window -eq $ForegroundWindow)
            dpi = [int][YuneWindows.Dev.M10SettingsGeometryNative]::GetDpiForWindow($Window)
            window_rect = New-RectSnapshot -Rect $WindowRect -Available $WindowRectAvailable
            client_rect = New-RectSnapshot -Rect $ClientRect -Available $ClientRectAvailable
            style = [pscustomobject][ordered]@{
                value = $Style
                hex = "0x$($Style.ToString('X'))"
                resizable = [bool](($Style -band $WsThickFrame) -ne 0)
                maximizable = [bool](($Style -band $WsMaximizeBox) -ne 0)
                horizontal_scroll = [bool](($Style -band $WsHScroll) -ne 0)
                vertical_scroll = [bool](($Style -band $WsVScroll) -ne 0)
            }
            extended_style = [pscustomobject][ordered]@{
                value = $ExtendedStyle
                hex = "0x$($ExtendedStyle.ToString('X'))"
            }
            scroll = [pscustomobject][ordered]@{
                horizontal = Get-ScrollSnapshot -Window $Window -Bar $SbHorz
                vertical = Get-ScrollSnapshot -Window $Window -Bar $SbVert
            }
            visible_child_count = $VisibleChildren.Count
            visible_children_fully_within_client = @(
                $VisibleChildren | Where-Object { [bool]$_.fully_within_client }).Count
            visible_children = @($VisibleChildren)
        })
    return $true
}

if (-not [YuneWindows.Dev.M10SettingsGeometryNative]::EnumWindows(
        $Callback,
        [IntPtr]::Zero)) {
    $ErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "EnumWindows failed with Win32 error $ErrorCode."
}

$Report = [pscustomobject][ordered]@{
    schema_version = 1
    evidence_kind = "m10_settings_geometry"
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    privacy_note = "Captures settings-window handles, process identity, DPI, styles, scrollbar state, and control geometry only. It does not read window or control titles, typed content, composition content, or keystrokes."
    phase = $Phase
    theme_reported_by_operator = $Theme
    window_count = $Windows.Count
    windows = @($Windows | Sort-Object process_id, thread_id, hwnd_hex)
    operator_report = [pscustomobject][ordered]@{
        provenance = "manually reported; not inferred from geometry"
        initial_viewport_usable = $InitialViewportUsable
        all_controls_reachable = $AllControlsReachable
        no_overlap_or_clipping = $NoOverlapOrClipping
        typography_legible_and_crisp = $TypographyLegibleAndCrisp
        cantonese_only = $CantoneseOnly
        native_effect_or_flat_fallback_usable = $NativeEffectOrFlatFallbackUsable
        no_focus_theft = $NoFocusTheft
        close_reopen_stable_no_orphan = $CloseReopenStableNoOrphan
        note = $OperatorNote
    }
}

$Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $FullOutputPath -Encoding utf8
Write-Host "M10 settings geometry written to $FullOutputPath"
Write-Host "Phase=$Phase theme=$Theme windows=$($Windows.Count)"
