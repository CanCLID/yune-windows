// yune_windows_glass_spike.cpp - throwaway M11 Slice C spike.
//
// Compares the candidate toolbar-glass backdrop mechanisms on the real machine so
// we can pick one before migrating the working toolbar off UpdateLayeredWindow.
// Drag it over an editor / a colored window; press 1-4 to switch material; Esc to
// quit. Screenshot each mode. NOT a product binary - it never ships.
//
//   1  DWM Desktop Acrylic  (DWMSBT_TRANSIENTWINDOW; supported; blurs WALLPAPER)
//   2  Accent acrylic       (SetWindowCompositionAttribute; undocumented; LIVE)
//   3  Accent blur-behind   (SetWindowCompositionAttribute; undocumented; LIVE)
//   4  DWM Mica             (DWMSBT_MAINWINDOW; supported; wallpaper tint)

#include <windows.h>
#include <dwmapi.h>
#include <uxtheme.h>
#include <string>

#pragma comment(lib, "dwmapi.lib")

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

enum SpikeAccentState {
    kAccentDisabled = 0,
    kAccentBlurBehind = 3,
    kAccentAcrylicBlurBehind = 4,
};
struct SpikeAccentPolicy {
    int state;
    int flags;
    unsigned int gradient_color;  // 0xAABBGGRR
    int animation_id;
};
struct SpikeWcaData {
    int attribute;  // 19 = WCA_ACCENT_POLICY
    void* data;
    size_t size;
};
typedef BOOL(WINAPI* SetWindowCompositionAttributeProc)(HWND, SpikeWcaData*);

static int g_mode = 1;
static const wchar_t* g_names[] = {
    L"",
    L"1  DWM Desktop Acrylic (supported; blurs WALLPAPER)",
    L"2  Accent acrylic (undocumented; blurs LIVE content)",
    L"3  Accent blur-behind (undocumented; blurs LIVE content)",
    L"4  DWM Mica (supported; wallpaper tint)",
};

static SetWindowCompositionAttributeProc ResolveSwca() {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    return user32 ? reinterpret_cast<SetWindowCompositionAttributeProc>(
                        GetProcAddress(user32, "SetWindowCompositionAttribute"))
                  : nullptr;
}

static void ApplyMode(HWND hwnd, int mode) {
    // Reset every backdrop source before applying the selected one.
    if (auto swca = ResolveSwca()) {
        SpikeAccentPolicy off = {kAccentDisabled, 0, 0, 0};
        SpikeWcaData data = {19, &off, sizeof(off)};
        swca(hwnd, &data);
    }
    DWORD none = 1;  // DWMSBT_NONE
    DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &none, sizeof(none));
    MARGINS reset = {0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &reset);

    const MARGINS sheet = {-1, -1, -1, -1};
    if (mode == 1 || mode == 4) {
        DwmExtendFrameIntoClientArea(hwnd, &sheet);
        DWORD backdrop = (mode == 1) ? 3 /*TRANSIENTWINDOW*/ : 2 /*MAINWINDOW=Mica*/;
        DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop,
                              sizeof(backdrop));
    } else if (auto swca = ResolveSwca()) {
        SpikeAccentPolicy accent = {};
        accent.state = (mode == 2) ? kAccentAcrylicBlurBehind : kAccentBlurBehind;
        accent.flags = 0;
        accent.gradient_color = 0x60303030;  // ~38% dark tint over the blur
        SpikeWcaData data = {19, &accent, sizeof(accent)};
        swca(hwnd, &data);
    }
    InvalidateRect(hwnd, nullptr, TRUE);
}

static void DrawShadowText(HDC dc, const std::wstring& text, RECT rect, UINT fmt) {
    SetBkMode(dc, TRANSPARENT);
    RECT shadow = rect;
    OffsetRect(&shadow, 1, 1);
    SetTextColor(dc, RGB(0, 0, 0));
    DrawTextW(dc, text.c_str(), -1, &shadow, fmt);
    SetTextColor(dc, RGB(255, 255, 255));
    DrawTextW(dc, text.c_str(), -1, &rect, fmt);
}

static LRESULT CALLBACK Proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_ERASEBKGND:
            return 1;  // let the backdrop material show instead of erasing
        case WM_KEYDOWN:
            if (wp == VK_ESCAPE) {
                PostQuitMessage(0);
            } else if (wp >= '1' && wp <= '4') {
                g_mode = static_cast<int>(wp - '0');
                ApplyMode(hwnd, g_mode);
            }
            return 0;
        case WM_LBUTTONDOWN:
            ReleaseCapture();
            SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(hwnd, &ps);
            RECT rc;
            GetClientRect(hwnd, &rc);
            HFONT big = CreateFontW(-30, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                    CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                    DEFAULT_PITCH, L"Microsoft JhengHei UI");
            HFONT small_font = CreateFontW(
                -17, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                DEFAULT_PITCH, L"Microsoft JhengHei UI");
            HGDIOBJ old = SelectObject(dc, big);
            RECT top = rc;
            top.bottom = rc.top + (rc.bottom - rc.top) / 2;
            DrawShadowText(
                dc, L"\x65b0\x97fb   \x4e2d  \x5168  \x50b3  \x7cb5   \x2699",
                top, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOCLIP);
            SelectObject(dc, small_font);
            RECT bottom = rc;
            bottom.top = rc.top + (rc.bottom - rc.top) / 2;
            std::wstring info = g_names[(g_mode >= 1 && g_mode <= 4) ? g_mode : 1];
            info += L"\n1-4 switch  ·  drag to move  ·  Esc quit";
            DrawShadowText(dc, info, bottom, DT_CENTER | DT_TOP | DT_NOCLIP);
            SelectObject(dc, old);
            DeleteObject(big);
            DeleteObject(small_font);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = Proc;
    wc.hInstance = instance;
    wc.lpszClassName = L"YuneGlassSpike";
    wc.hCursor = LoadCursorW(nullptr, IDC_SIZEALL);
    wc.hbrBackground = nullptr;
    RegisterClassW(&wc);

    const int width = 560;
    const int height = 220;
    const int x = (GetSystemMetrics(SM_CXSCREEN) - width) / 2;
    const int y = (GetSystemMetrics(SM_CYSCREEN) - height) / 3;
    HWND hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_APPWINDOW, wc.lpszClassName,
                               L"Yune Glass Spike", WS_POPUP, x, y, width, height,
                               nullptr, nullptr, instance, nullptr);
    if (!hwnd) {
        return 1;
    }
    DWORD round = 2;  // DWMWCP_ROUND
    DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &round,
                          sizeof(round));
    ApplyMode(hwnd, g_mode);
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}
