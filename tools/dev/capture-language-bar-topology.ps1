param()

$ErrorActionPreference = "Stop"

if (-not ("YuneWindows.Dev.ToolbarTopologyNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace YuneWindows.Dev {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct ToolbarRect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ToolbarGuiThreadInfo {
        public uint cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public ToolbarRect rcCaret;
    }

    public static class ToolbarTopologyNative {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetClassNameW(IntPtr hWnd, StringBuilder className, int maxCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out ToolbarRect rect);

        [DllImport("user32.dll")]
        public static extern IntPtr GetWindow(IntPtr hWnd, uint command);

        [DllImport("user32.dll")]
        public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetGUIThreadInfo(uint threadId, ref ToolbarGuiThreadInfo info);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
        private static extern int GetWindowLong32(IntPtr hWnd, int index);

        public static uint GetExtendedWindowStyle(IntPtr hWnd) {
            if (IntPtr.Size == 8) {
                return unchecked((uint)GetWindowLongPtr64(hWnd, -20).ToInt64());
            }
            return unchecked((uint)GetWindowLong32(hWnd, -20));
        }

        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(
            IntPtr hWnd,
            uint attribute,
            out ToolbarRect value,
            uint valueSize);
    }
}
"@
}

$RuntimeClassName = "YuneWindowsLanguageBar"
$SuffixedClassPattern = "YuneWindowsLanguageBar_*"
$GwOwner = [uint32]4
$GaRoot = [uint32]2
$GaRootOwner = [uint32]3
$DwmwaExtendedFrameBounds = [uint32]9

$ExtendedStyleNames = [ordered]@{
    WS_EX_DLGMODALFRAME = [uint32]0x00000001
    WS_EX_NOPARENTNOTIFY = [uint32]0x00000004
    WS_EX_TOPMOST = [uint32]0x00000008
    WS_EX_ACCEPTFILES = [uint32]0x00000010
    WS_EX_TRANSPARENT = [uint32]0x00000020
    WS_EX_MDICHILD = [uint32]0x00000040
    WS_EX_TOOLWINDOW = [uint32]0x00000080
    WS_EX_WINDOWEDGE = [uint32]0x00000100
    WS_EX_CLIENTEDGE = [uint32]0x00000200
    WS_EX_CONTEXTHELP = [uint32]0x00000400
    WS_EX_RIGHT = [uint32]0x00001000
    WS_EX_LEFTSCROLLBAR = [uint32]0x00004000
    WS_EX_CONTROLPARENT = [uint32]0x00010000
    WS_EX_STATICEDGE = [uint32]0x00020000
    WS_EX_APPWINDOW = [uint32]0x00040000
    WS_EX_LAYERED = [uint32]0x00080000
    WS_EX_NOINHERITLAYOUT = [uint32]0x00100000
    WS_EX_NOREDIRECTIONBITMAP = [uint32]0x00200000
    WS_EX_LAYOUTRTL = [uint32]0x00400000
    WS_EX_COMPOSITED = [uint32]0x02000000
    WS_EX_NOACTIVATE = [uint32]0x08000000
}

function ConvertTo-HandleValue {
    param([Parameter(Mandatory = $true)][IntPtr]$Handle)

    return $Handle.ToInt64()
}

function Format-Handle {
    param([Parameter(Mandatory = $true)][IntPtr]$Handle)

    $Width = [IntPtr]::Size * 2
    return "0x$($Handle.ToString("X$Width"))"
}

function New-RectSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Rect,
        [Parameter(Mandatory = $true)][bool]$Available
    )

    if (-not $Available) {
        return [pscustomobject][ordered]@{
            available = $false
            left = $null
            top = $null
            right = $null
            bottom = $null
            width = $null
            height = $null
        }
    }

    return [pscustomobject][ordered]@{
        available = $true
        left = $Rect.Left
        top = $Rect.Top
        right = $Rect.Right
        bottom = $Rect.Bottom
        width = $Rect.Right - $Rect.Left
        height = $Rect.Bottom - $Rect.Top
    }
}

function Get-ExtendedStyleFlags {
    param([Parameter(Mandatory = $true)][uint32]$Style)

    $Names = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in $ExtendedStyleNames.GetEnumerator()) {
        if (($Style -band [uint32]$Entry.Value) -ne 0) {
            $Names.Add([string]$Entry.Key)
        }
    }
    return @($Names)
}

function Get-ProcessNameSafely {
    param([Parameter(Mandatory = $true)][uint32]$ProcessId)

    try {
        return [string](Get-Process -Id $ProcessId -ErrorAction Stop).ProcessName
    }
    catch {
        return ""
    }
}

$ForegroundWindow = [YuneWindows.Dev.ToolbarTopologyNative]::GetForegroundWindow()
$ForegroundRoot = if ($ForegroundWindow -eq [IntPtr]::Zero) {
    [IntPtr]::Zero
}
else {
    [YuneWindows.Dev.ToolbarTopologyNative]::GetAncestor($ForegroundWindow, $GaRoot)
}
$ForegroundRootOwner = if ($ForegroundWindow -eq [IntPtr]::Zero) {
    [IntPtr]::Zero
}
else {
    [YuneWindows.Dev.ToolbarTopologyNative]::GetAncestor($ForegroundWindow, $GaRootOwner)
}

$Windows = [System.Collections.Generic.List[object]]::new()
$Callback = [YuneWindows.Dev.EnumWindowsProc] {
    param([IntPtr]$Window, [IntPtr]$Param)

    $ClassNameBuffer = [System.Text.StringBuilder]::new(256)
    $ClassNameLength = [YuneWindows.Dev.ToolbarTopologyNative]::GetClassNameW(
        $Window,
        $ClassNameBuffer,
        $ClassNameBuffer.Capacity)
    if ($ClassNameLength -le 0) {
        return $true
    }

    $ClassName = $ClassNameBuffer.ToString()
    if ($ClassName -ne $RuntimeClassName -and $ClassName -notlike $SuffixedClassPattern) {
        return $true
    }

    $ProcessId = [uint32]0
    $ThreadId = [YuneWindows.Dev.ToolbarTopologyNative]::GetWindowThreadProcessId(
        $Window,
        [ref]$ProcessId)

    $WindowRect = [YuneWindows.Dev.ToolbarRect]::new()
    $WindowRectAvailable = [YuneWindows.Dev.ToolbarTopologyNative]::GetWindowRect(
        $Window,
        [ref]$WindowRect)

    $DwmFrame = [YuneWindows.Dev.ToolbarRect]::new()
    $DwmHResult = [YuneWindows.Dev.ToolbarTopologyNative]::DwmGetWindowAttribute(
        $Window,
        $DwmwaExtendedFrameBounds,
        [ref]$DwmFrame,
        [uint32][Runtime.InteropServices.Marshal]::SizeOf([type][YuneWindows.Dev.ToolbarRect]))
    $DwmFrameAvailable = ($DwmHResult -eq 0)

    $Owner = [YuneWindows.Dev.ToolbarTopologyNative]::GetWindow($Window, $GwOwner)
    $Root = [YuneWindows.Dev.ToolbarTopologyNative]::GetAncestor($Window, $GaRoot)
    $RootOwner = [YuneWindows.Dev.ToolbarTopologyNative]::GetAncestor($Window, $GaRootOwner)

    $GuiThreadInfo = [YuneWindows.Dev.ToolbarGuiThreadInfo]::new()
    $GuiThreadInfo.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf(
        [type][YuneWindows.Dev.ToolbarGuiThreadInfo])
    $GuiThreadInfoAvailable = if ($ThreadId -ne 0) {
        [YuneWindows.Dev.ToolbarTopologyNative]::GetGUIThreadInfo($ThreadId, [ref]$GuiThreadInfo)
    }
    else {
        $false
    }
    $CaptureWindow = if ($GuiThreadInfoAvailable) {
        $GuiThreadInfo.hwndCapture
    }
    else {
        [IntPtr]::Zero
    }

    $ExtendedStyle = [YuneWindows.Dev.ToolbarTopologyNative]::GetExtendedWindowStyle($Window)
    $Windows.Add([pscustomobject][ordered]@{
            hwnd = ConvertTo-HandleValue $Window
            hwnd_hex = Format-Handle $Window
            class_name = $ClassName
            process_id = $ProcessId
            thread_id = $ThreadId
            process_name = Get-ProcessNameSafely $ProcessId
            visible = [bool][YuneWindows.Dev.ToolbarTopologyNative]::IsWindowVisible($Window)
            rect = New-RectSnapshot -Rect $WindowRect -Available $WindowRectAvailable
            dwm_frame = [pscustomobject][ordered]@{
                hresult = "0x$($DwmHResult.ToString("X8"))"
                bounds = New-RectSnapshot -Rect $DwmFrame -Available $DwmFrameAvailable
            }
            ownership = [pscustomobject][ordered]@{
                owner_hwnd = ConvertTo-HandleValue $Owner
                owner_hwnd_hex = Format-Handle $Owner
                root_hwnd = ConvertTo-HandleValue $Root
                root_hwnd_hex = Format-Handle $Root
                root_owner_hwnd = ConvertTo-HandleValue $RootOwner
                root_owner_hwnd_hex = Format-Handle $RootOwner
            }
            foreground = [pscustomobject][ordered]@{
                hwnd = ConvertTo-HandleValue $ForegroundWindow
                hwnd_hex = Format-Handle $ForegroundWindow
                root_hwnd = ConvertTo-HandleValue $ForegroundRoot
                root_hwnd_hex = Format-Handle $ForegroundRoot
                root_owner_hwnd = ConvertTo-HandleValue $ForegroundRootOwner
                root_owner_hwnd_hex = Format-Handle $ForegroundRootOwner
                is_foreground_window = ($Window -eq $ForegroundWindow)
                root_owner_matches_foreground_root = (
                    $RootOwner -ne [IntPtr]::Zero -and
                    $ForegroundRootOwner -ne [IntPtr]::Zero -and
                    $RootOwner -eq $ForegroundRootOwner)
                root_owner_matches_foreground_root_owner = (
                    $RootOwner -ne [IntPtr]::Zero -and
                    $ForegroundRootOwner -ne [IntPtr]::Zero -and
                    $RootOwner -eq $ForegroundRootOwner)
            }
            extended_style = [pscustomobject][ordered]@{
                value = $ExtendedStyle
                hex = "0x$($ExtendedStyle.ToString("X8"))"
                flags = @(Get-ExtendedStyleFlags $ExtendedStyle)
            }
            capture = [pscustomobject][ordered]@{
                gui_thread_info_available = [bool]$GuiThreadInfoAvailable
                hwnd = ConvertTo-HandleValue $CaptureWindow
                hwnd_hex = Format-Handle $CaptureWindow
                is_this_window = ($CaptureWindow -eq $Window)
            }
        })

    return $true
}

if (-not [YuneWindows.Dev.ToolbarTopologyNative]::EnumWindows($Callback, [IntPtr]::Zero)) {
    $ErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "EnumWindows failed with Win32 error $ErrorCode."
}

$SortedWindows = @($Windows | Sort-Object process_id, thread_id, hwnd)
$Report = [pscustomobject][ordered]@{
    schema_version = 1
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
    class_names = @($RuntimeClassName, $SuffixedClassPattern)
    privacy_note = "Captures window topology only; no window titles, text content, or keystrokes are read."
    foreground = [pscustomobject][ordered]@{
        hwnd = ConvertTo-HandleValue $ForegroundWindow
        hwnd_hex = Format-Handle $ForegroundWindow
        root_hwnd = ConvertTo-HandleValue $ForegroundRoot
        root_hwnd_hex = Format-Handle $ForegroundRoot
        root_owner_hwnd = ConvertTo-HandleValue $ForegroundRootOwner
        root_owner_hwnd_hex = Format-Handle $ForegroundRootOwner
    }
    window_count = $SortedWindows.Count
    windows = $SortedWindows
}

$Report | ConvertTo-Json -Depth 8
