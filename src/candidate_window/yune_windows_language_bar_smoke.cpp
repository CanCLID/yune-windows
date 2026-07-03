#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <objbase.h>

#include <iostream>
#include <string>

#include "yune_windows_candidate_window.h"

namespace {

bool g_clicked = false;
bool g_position_changed = false;
int g_position_x = 0;
int g_position_y = 0;

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

std::filesystem::path ModuleDirectory() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(nullptr, module_path, ARRAYSIZE(module_path))) {
        return {};
    }
    return std::filesystem::path(module_path).parent_path();
}

void ClickHandler(yune_windows::LanguageBarSegment segment, void*) {
    if (segment == yune_windows::LanguageBarSegment::AsciiMode) {
        g_clicked = true;
    }
}

void PositionChangedHandler(int x, int y, void*) {
    g_position_changed = true;
    g_position_x = x;
    g_position_y = y;
}

LRESULT CALLBACK OwnerProc(HWND hwnd, UINT message, WPARAM wparam,
                           LPARAM lparam) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

BOOL CALLBACK FindLanguageBarWindowProc(HWND hwnd, LPARAM lparam) {
    wchar_t class_name[128] = {};
    GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name));
    if (std::wstring(class_name) == L"YuneWindowsLanguageBar") {
        *reinterpret_cast<HWND*>(lparam) = hwnd;
        return FALSE;
    }
    return TRUE;
}

HWND FindLanguageBarWindowForCurrentThread() {
    HWND found = nullptr;
    EnumThreadWindows(GetCurrentThreadId(), &FindLanguageBarWindowProc,
                      reinterpret_cast<LPARAM>(&found));
    return found;
}

bool RegisterOwnerClass() {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpfnWndProc = OwnerProc;
    wc.lpszClassName = L"YuneWindowsLanguageBarSmokeOwner";
    ATOM atom = RegisterClassExW(&wc);
    return atom != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

int SelfTest() {
    (void)CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    const std::filesystem::path module_dir = ModuleDirectory();
    const yune_windows::ToolbarSkin default_skin =
        yune_windows::LoadToolbarSkin(module_dir, L"default");
    if (default_skin.name.empty() || default_skin.min_width < 180) {
        std::cerr << "default skin did not load or fall back cleanly\n";
        return 1;
    }
    const yune_windows::ToolbarSkin fallback_skin =
        yune_windows::LoadToolbarSkin(module_dir, L"missing-skin");
    if (fallback_skin.name != L"default") {
        std::cerr << "missing skin did not use compiled-in default fallback\n";
        return 1;
    }

    RECT offscreen = {-50000, -50000, -49700, -49940};
    RECT clamped = yune_windows::ClampToolbarRectToVisibleMonitor(offscreen, 144);
    if (clamped.right <= clamped.left || clamped.bottom <= clamped.top ||
        clamped.left == offscreen.left || clamped.top == offscreen.top) {
        std::cerr << "toolbar monitor clamp failed\n";
        return 1;
    }

    if (!RegisterOwnerClass()) {
        std::cerr << "failed to register smoke owner window\n";
        return 1;
    }

    HWND owner = CreateWindowExW(0, L"YuneWindowsLanguageBarSmokeOwner",
                                 L"Yune language bar smoke", WS_OVERLAPPEDWINDOW,
                                 80, 80, 320, 160, nullptr, nullptr,
                                 GetModuleHandleW(nullptr), nullptr);
    if (!owner) {
        std::cerr << "failed to create smoke owner window\n";
        return 1;
    }
    ShowWindow(owner, SW_SHOWNORMAL);
    UpdateWindow(owner);
    SetForegroundWindow(owner);
    Sleep(50);

    yune_windows::LanguageBarWindow toolbar;
    toolbar.SetClickHandler(&ClickHandler, nullptr);
    toolbar.SetPositionChangedHandler(&PositionChangedHandler, nullptr);

    yune_windows::LanguageBarState state;
    state.ascii_mode = false;
    state.full_shape = false;
    state.output_standard = L"hong_kong_traditional";
    state.schema_id = L"jyut6ping3";
    state.anchor = {120, 120, 140, 150};
    state.owner = nullptr;
    state.dpi = GetDpiForWindow(owner);
    state.skin_name = L"default";

    if (!toolbar.Update(state, true)) {
        std::cerr << "language bar failed to update\n";
        DestroyWindow(owner);
        return 1;
    }

    HWND bar_hwnd = FindLanguageBarWindowForCurrentThread();
    if (!bar_hwnd) {
        std::cerr << "language bar window was not created\n";
        DestroyWindow(owner);
        return 1;
    }
    const LONG_PTR ex_style = GetWindowLongPtrW(bar_hwnd, GWL_EXSTYLE);
    if ((ex_style & WS_EX_NOACTIVATE) == 0 || (ex_style & WS_EX_LAYERED) == 0) {
        std::cerr << "language bar missing no-activate layered styles\n";
        DestroyWindow(owner);
        return 1;
    }

    RECT before = {};
    GetWindowRect(bar_hwnd, &before);
    HWND foreground_before = GetForegroundWindow();

    const LPARAM drag_start =
        MAKELPARAM(Scale(10, state.dpi), Scale(18, state.dpi));
    const LPARAM drag_move =
        MAKELPARAM(Scale(70, state.dpi), Scale(42, state.dpi));
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, drag_start);
    SendMessageW(bar_hwnd, WM_MOUSEMOVE, MK_LBUTTON, drag_move);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, drag_move);

    RECT after = {};
    GetWindowRect(bar_hwnd, &after);
    HWND foreground_after = GetForegroundWindow();
    if (!g_position_changed || (after.left == before.left && after.top == before.top)) {
        std::cerr << "language bar drag did not move or report position\n";
        DestroyWindow(owner);
        return 1;
    }
    if (foreground_after == bar_hwnd ||
        (foreground_before && foreground_after != foreground_before)) {
        std::cerr << "language bar stole foreground focus during drag\n";
        DestroyWindow(owner);
        return 1;
    }
    if (g_position_x != after.left || g_position_y != after.top) {
        std::cerr << "drag callback reported a stale toolbar position\n";
        DestroyWindow(owner);
        return 1;
    }

    const LPARAM click_point =
        MAKELPARAM(Scale(42, state.dpi), Scale(18, state.dpi));
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, click_point);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, click_point);
    if (!g_clicked) {
        std::cerr << "language bar click did not route to segment handler\n";
        DestroyWindow(owner);
        return 1;
    }

    toolbar.Hide();
    DestroyWindow(owner);
    std::cout << "language bar smoke passed\n";
    return 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && std::wstring(argv[1]) == L"--self-test") {
        return SelfTest();
    }
    std::cerr << "usage: YuneWindowsLanguageBarSmoke.exe --self-test\n";
    return 2;
}
