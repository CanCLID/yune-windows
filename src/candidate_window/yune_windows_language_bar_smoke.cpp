#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <iostream>
#include <string>
#include <vector>

#include "yune_windows_candidate_window.h"

namespace {

int g_ascii_click_count = 0;
int g_settings_click_count = 0;
int g_position_change_count = 0;
int g_position_x = 0;
int g_position_y = 0;

constexpr DWORD kSystemBackdropAttribute = 38;
constexpr DWORD kBackdropNone = 1;
constexpr DWORD kBackdropTransientWindow = 3;
constexpr UINT_PTR kToolbarForegroundTimerForSmoke = 0x59554e45;
constexpr const wchar_t* kToolbarSupersededMessageName =
    L"YuneWindows.ToolbarSuperseded.v1";

struct BackdropCallTrace {
    HRESULT transient_result = S_OK;
    HRESULT frame_result = S_OK;
    std::vector<DWORD> system_backdrops;
    std::vector<std::array<int, 4>> frame_margins;
};

BackdropCallTrace g_backdrop_trace;

HRESULT RecordBackdropAttribute(HWND, DWORD attribute, const void* value,
                                DWORD value_size) {
    if (attribute != kSystemBackdropAttribute || !value ||
        value_size < sizeof(DWORD)) {
        return S_OK;
    }
    const DWORD backdrop = *static_cast<const DWORD*>(value);
    g_backdrop_trace.system_backdrops.push_back(backdrop);
    return backdrop == kBackdropTransientWindow
               ? g_backdrop_trace.transient_result
               : S_OK;
}

HRESULT RecordFrameExtension(HWND, int left, int right, int top, int bottom) {
    g_backdrop_trace.frame_margins.push_back({left, right, top, bottom});
    return g_backdrop_trace.frame_result;
}

void ResetBackdropTrace(HRESULT transient_result = S_OK,
                        HRESULT frame_result = S_OK) {
    g_backdrop_trace = {};
    g_backdrop_trace.transient_result = transient_result;
    g_backdrop_trace.frame_result = frame_result;
}

bool HasFrameMargins(const std::array<int, 4>& expected) {
    return std::find(g_backdrop_trace.frame_margins.begin(),
                     g_backdrop_trace.frame_margins.end(),
                     expected) != g_backdrop_trace.frame_margins.end();
}

class BackdropHookScope {
public:
    BackdropHookScope() { SetBuild(22000); }
    ~BackdropHookScope() {
        yune_windows::SetToolbarBackdropTestHooksForTesting(nullptr);
    }

    void SetBuild(DWORD build_number) {
        yune_windows::ToolbarBackdropTestHooks hooks;
        hooks.windows_build_number = build_number;
        hooks.set_window_attribute = &RecordBackdropAttribute;
        hooks.extend_frame = &RecordFrameExtension;
        yune_windows::SetToolbarBackdropTestHooksForTesting(&hooks);
    }
};

class WindowScope {
public:
    explicit WindowScope(HWND hwnd) : hwnd_(hwnd) {}
    ~WindowScope() {
        if (hwnd_) {
            DestroyWindow(hwnd_);
        }
    }
    HWND get() const { return hwnd_; }

private:
    HWND hwnd_ = nullptr;
};

class HandleScope {
public:
    explicit HandleScope(HANDLE handle = nullptr) : handle_(handle) {}
    ~HandleScope() {
        if (handle_) {
            CloseHandle(handle_);
        }
    }
    HandleScope(const HandleScope&) = delete;
    HandleScope& operator=(const HandleScope&) = delete;
    HANDLE get() const { return handle_; }

private:
    HANDLE handle_ = nullptr;
};

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

std::filesystem::path ModulePath() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(nullptr, module_path, ARRAYSIZE(module_path))) {
        return {};
    }
    return module_path;
}

void ClickHandler(yune_windows::LanguageBarSegment segment, void*) {
    if (segment == yune_windows::LanguageBarSegment::AsciiMode) {
        ++g_ascii_click_count;
    }
    if (segment == yune_windows::LanguageBarSegment::Settings) {
        ++g_settings_click_count;
    }
}

void PositionChangedHandler(int x, int y, void*) {
    ++g_position_change_count;
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
    const std::wstring name(class_name);
    if (name == L"YuneWindowsLanguageBar" ||
        name.rfind(L"YuneWindowsLanguageBar_", 0) == 0) {
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

BOOL CALLBACK CollectLanguageBarWindowProc(HWND hwnd, LPARAM lparam) {
    wchar_t class_name[128] = {};
    GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name));
    const std::wstring name(class_name);
    if (name == L"YuneWindowsLanguageBar" ||
        name.rfind(L"YuneWindowsLanguageBar_", 0) == 0) {
        reinterpret_cast<std::vector<HWND>*>(lparam)->push_back(hwnd);
    }
    return TRUE;
}

std::vector<HWND> LanguageBarWindowsForProcess(DWORD process_id) {
    std::vector<HWND> windows;
    EnumWindows(&CollectLanguageBarWindowProc,
                reinterpret_cast<LPARAM>(&windows));
    windows.erase(std::remove_if(windows.begin(), windows.end(),
                                 [process_id](HWND hwnd) {
                                     DWORD owner_process = 0;
                                     GetWindowThreadProcessId(hwnd,
                                                              &owner_process);
                                     return owner_process != process_id;
                                 }),
                  windows.end());
    return windows;
}

std::vector<HWND> LanguageBarWindowsForCurrentProcess() {
    return LanguageBarWindowsForProcess(GetCurrentProcessId());
}

int VisibleLanguageBarCountForCurrentProcess() {
    int visible = 0;
    for (HWND hwnd : LanguageBarWindowsForCurrentProcess()) {
        visible += IsWindowVisible(hwnd) ? 1 : 0;
    }
    return visible;
}

void PumpMessages(DWORD duration_ms) {
    const ULONGLONG deadline = GetTickCount64() + duration_ms;
    MSG message = {};
    while (GetTickCount64() < deadline) {
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT);
    }
}

DWORD PumpUntilHandle(HANDLE* handles, DWORD handle_count, DWORD timeout_ms) {
    const ULONGLONG deadline = GetTickCount64() + timeout_ms;
    MSG message = {};
    for (;;) {
        const ULONGLONG now = GetTickCount64();
        if (now >= deadline) {
            return WAIT_TIMEOUT;
        }
        const DWORD remaining =
            static_cast<DWORD>(std::min<ULONGLONG>(deadline - now, MAXDWORD));
        const DWORD result = MsgWaitForMultipleObjects(
            handle_count, handles, FALSE, remaining, QS_ALLINPUT);
        if (result >= WAIT_OBJECT_0 &&
            result < WAIT_OBJECT_0 + handle_count) {
            return result;
        }
        if (result == WAIT_OBJECT_0 + handle_count) {
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            continue;
        }
        return result;
    }
}

HWND RootOwner(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) {
        return nullptr;
    }
    const HWND root = GetAncestor(hwnd, GA_ROOTOWNER);
    return root ? root : hwnd;
}

bool MakeForeground(HWND hwnd, DWORD timeout_ms = 1000) {
    const ULONGLONG deadline = GetTickCount64() + timeout_ms;
    do {
        const DWORD current_thread = GetCurrentThreadId();
        const HWND previous_foreground = GetForegroundWindow();
        const DWORD foreground_thread = previous_foreground
                                            ? GetWindowThreadProcessId(
                                                  previous_foreground, nullptr)
                                            : 0;
        const bool attached =
            foreground_thread != 0 && foreground_thread != current_thread &&
            AttachThreadInput(current_thread, foreground_thread, TRUE);
        (void)BringWindowToTop(hwnd);
        (void)SetForegroundWindow(hwnd);
        (void)SetActiveWindow(hwnd);
        (void)SetFocus(hwnd);
        if (attached) {
            (void)AttachThreadInput(current_thread, foreground_thread, FALSE);
        }
        PumpMessages(20);
        if (RootOwner(GetForegroundWindow()) == RootOwner(hwnd)) {
            return true;
        }
    } while (GetTickCount64() < deadline);
    return false;
}

void SendPointerMoveAtScreen(HWND hwnd, POINT screen_point) {
    POINT client = screen_point;
    ScreenToClient(hwnd, &client);
    SendMessageW(hwnd, WM_MOUSEMOVE, MK_LBUTTON,
                 MAKELPARAM(client.x, client.y));
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

int RunSupersessionChild(const std::wstring& ready_event_name,
                         const std::wstring& stop_event_name,
                         DWORD parent_process_id) {
    const HRESULT co_init_result =
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool co_initialized = SUCCEEDED(co_init_result);
    HandleScope ready_event(OpenEventW(EVENT_MODIFY_STATE | SYNCHRONIZE, FALSE,
                                       ready_event_name.c_str()));
    HandleScope stop_event(OpenEventW(EVENT_MODIFY_STATE | SYNCHRONIZE, FALSE,
                                      stop_event_name.c_str()));
    HandleScope parent_process(
        OpenProcess(SYNCHRONIZE, FALSE, parent_process_id));
    if (!ready_event.get() || !stop_event.get() || !parent_process.get() ||
        !RegisterOwnerClass()) {
        if (co_initialized) {
            CoUninitialize();
        }
        return 10;
    }

    int result = 0;
    {
        WindowScope owner(CreateWindowExW(
            0, L"YuneWindowsLanguageBarSmokeOwner",
            L"Yune supersession child", WS_OVERLAPPEDWINDOW,
            520, 280, 320, 160, nullptr, nullptr, GetModuleHandleW(nullptr),
            nullptr));
        if (!owner.get()) {
            result = 11;
        } else {
            ShowWindow(owner.get(), SW_SHOWNORMAL);
            UpdateWindow(owner.get());
            if (!MakeForeground(owner.get(), 1500)) {
                result = 12;
            } else {
                // Best effort: the parent also has an AttachThreadInput fallback
                // for reclaiming focus, so ASFW eligibility is not a test gate.
                (void)AllowSetForegroundWindow(parent_process_id);
                yune_windows::LanguageBarWindow toolbar;
                yune_windows::LanguageBarState state;
                state.anchor = {560, 320, 580, 350};
                state.owner = owner.get();
                state.dpi = GetDpiForWindow(owner.get());
                state.skin_name = L"default";
                if (!toolbar.Update(state, true) ||
                    !toolbar.native_handle_for_testing() ||
                    !IsWindowVisible(toolbar.native_handle_for_testing())) {
                    result = 14;
                } else if (!SetEvent(ready_event.get())) {
                    result = 15;
                } else {
                    HANDLE wait_handles[] = {stop_event.get(),
                                             parent_process.get()};
                    const DWORD wait_result =
                        PumpUntilHandle(wait_handles, ARRAYSIZE(wait_handles),
                                        15000);
                    if (wait_result != WAIT_OBJECT_0 &&
                        wait_result != WAIT_OBJECT_0 + 1) {
                        result = 16;
                    }
                }
                toolbar.Hide();
            }
        }
    }
    if (co_initialized) {
        CoUninitialize();
    }
    return result;
}

bool RunCrossProcessSupersessionSmoke(
    yune_windows::LanguageBarWindow& toolbar,
    const yune_windows::LanguageBarState& state, HWND owner, HWND bar_hwnd) {
    wchar_t unique_suffix[96] = {};
    swprintf_s(unique_suffix, L"%lu.%llu", GetCurrentProcessId(),
               GetTickCount64());
    const std::wstring ready_event_name =
        std::wstring(L"Local\\YuneWindows.ToolbarSmoke.Ready.") +
        unique_suffix;
    const std::wstring stop_event_name =
        std::wstring(L"Local\\YuneWindows.ToolbarSmoke.Stop.") +
        unique_suffix;
    HandleScope ready_event(
        CreateEventW(nullptr, TRUE, FALSE, ready_event_name.c_str()));
    HandleScope stop_event(
        CreateEventW(nullptr, TRUE, FALSE, stop_event_name.c_str()));
    const std::filesystem::path module_path = ModulePath();
    if (!ready_event.get() || !stop_event.get() || module_path.empty()) {
        std::cerr << "failed to prepare cross-process supersession smoke\n";
        return false;
    }

    std::wstring command_line =
        L"\"" + module_path.wstring() + L"\" --supersession-child \"" +
        ready_event_name + L"\" \"" + stop_event_name + L"\" " +
        std::to_wstring(GetCurrentProcessId());
    std::vector<wchar_t> mutable_command(command_line.begin(),
                                         command_line.end());
    mutable_command.push_back(L'\0');
    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process_info = {};
    if (!CreateProcessW(module_path.c_str(), mutable_command.data(), nullptr,
                        nullptr, FALSE, CREATE_SUSPENDED, nullptr, nullptr,
                        &startup, &process_info)) {
        std::cerr << "failed to launch supersession helper process\n";
        return false;
    }
    HandleScope child_process(process_info.hProcess);
    HandleScope child_thread(process_info.hThread);
    (void)AllowSetForegroundWindow(process_info.dwProcessId);
    if (ResumeThread(child_thread.get()) == static_cast<DWORD>(-1)) {
        std::cerr << "failed to resume supersession helper process\n";
        (void)TerminateProcess(child_process.get(), 90);
        return false;
    }

    // Disable both independent focus-loss paths for this leg so hiding can only
    // be attributed to the registered cross-process supersession message.
    toolbar.set_ignore_activate_app_for_testing(true);
    toolbar.reset_activate_app_bypass_count_for_testing();
    (void)KillTimer(bar_hwnd, kToolbarForegroundTimerForSmoke);
    bool passed = false;
    do {
        HANDLE ready_handles[] = {ready_event.get(), child_process.get()};
        const DWORD ready_result =
            PumpUntilHandle(ready_handles, ARRAYSIZE(ready_handles), 5000);
        if (ready_result != WAIT_OBJECT_0) {
            std::cerr << "supersession helper did not become ready\n";
            break;
        }
        PumpMessages(100);
        if (toolbar.activate_app_bypass_count_for_testing() == 0) {
            std::cerr << "cross-process leg did not exercise WM_ACTIVATEAPP loss\n";
            break;
        }
        const std::vector<HWND> child_bars =
            LanguageBarWindowsForProcess(process_info.dwProcessId);
        std::vector<HWND> visible_child_bars;
        std::copy_if(child_bars.begin(), child_bars.end(),
                     std::back_inserter(visible_child_bars),
                     [](HWND hwnd) { return IsWindowVisible(hwnd) != FALSE; });
        if (visible_child_bars.size() != 1) {
            std::cerr << "supersession helper did not expose one toolbar"
                      << " total=" << child_bars.size()
                      << " visible=" << visible_child_bars.size();
            std::cerr << " foreground="
                      << reinterpret_cast<ULONG_PTR>(GetForegroundWindow())
                      << "\n";
            for (HWND child_window : child_bars) {
                wchar_t child_class[128] = {};
                (void)GetClassNameW(child_window, child_class,
                                    ARRAYSIZE(child_class));
                std::wcerr << L"  hwnd="
                           << reinterpret_cast<ULONG_PTR>(child_window)
                           << L" visible="
                           << (IsWindowVisible(child_window) ? 1 : 0)
                           << L" class=" << child_class << L"\n";
            }
            break;
        }
        const HWND child_bar = visible_child_bars.front();
        const HWND child_owner = GetWindow(child_bar, GW_OWNER);
        if (!child_owner ||
            RootOwner(child_owner) != RootOwner(GetForegroundWindow())) {
            std::cerr << "supersession helper toolbar was not foreground-owned\n";
            break;
        }
        if (IsWindowVisible(bar_hwnd)) {
            std::cerr << "cross-process supersession message did not hide old toolbar\n";
            break;
        }

        if (!MakeForeground(owner, 1500) || !toolbar.Update(state, true)) {
            std::cerr << "parent toolbar could not reclaim foreground visibility\n";
            break;
        }
        PumpMessages(100);
        if (!IsWindowVisible(bar_hwnd) || IsWindowVisible(child_bar)) {
            std::cerr << "parent reclaim did not supersede child toolbar\n";
            break;
        }

        // Re-show the stale claimant while its owner is not foreground. The
        // receiver must revalidate ownership instead of hiding the current bar.
        (void)ShowWindowAsync(child_bar, SW_SHOWNOACTIVATE);
        PumpMessages(50);
        if (!IsWindowVisible(child_bar)) {
            std::cerr << "could not stage stale supersession claimant\n";
            break;
        }
        const UINT superseded_message =
            RegisterWindowMessageW(kToolbarSupersededMessageName);
        if (!superseded_message ||
            !PostMessageW(bar_hwnd, superseded_message,
                          reinterpret_cast<WPARAM>(child_bar), 0)) {
            std::cerr << "could not post stale supersession message\n";
            break;
        }
        PumpMessages(100);
        if (!IsWindowVisible(bar_hwnd)) {
            std::cerr << "stale supersession claimant hid current toolbar\n";
            break;
        }
        (void)ShowWindowAsync(child_bar, SW_HIDE);
        passed = true;
    } while (false);

    (void)SetEvent(stop_event.get());
    HANDLE process_handle = child_process.get();
    DWORD process_wait = PumpUntilHandle(&process_handle, 1, 5000);
    if (process_wait != WAIT_OBJECT_0) {
        std::cerr << "supersession helper did not exit cleanly\n";
        (void)TerminateProcess(child_process.get(), 91);
        (void)WaitForSingleObject(child_process.get(), 1000);
        passed = false;
    } else {
        DWORD exit_code = 0;
        if (!GetExitCodeProcess(child_process.get(), &exit_code) ||
            exit_code != 0) {
            std::cerr << "supersession helper exited with code " << exit_code
                      << "\n";
            passed = false;
        }
    }

    toolbar.set_ignore_activate_app_for_testing(false);
    if (!MakeForeground(owner, 1500) || !toolbar.Update(state, true)) {
        std::cerr << "failed to restore parent toolbar after helper cleanup\n";
        return false;
    }
    PumpMessages(50);
    return passed && IsWindowVisible(bar_hwnd);
}

bool RunBackdropRegressionSmoke(HWND owner,
                                const yune_windows::ToolbarSkin& default_skin) {
    WindowScope test_window(CreateWindowExW(
        WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_NOREDIRECTIONBITMAP,
        L"YuneWindowsLanguageBarSmokeOwner", L"", WS_POPUP,
        -2000, -2000, 318, 48, owner, nullptr, GetModuleHandleW(nullptr),
        nullptr));
    if (!test_window.get()) {
        std::cerr << "failed to create backdrop regression window\n";
        return false;
    }
    ShowWindow(test_window.get(), SW_SHOWNOACTIVATE);

    BackdropHookScope hook_scope;
    yune_windows::GlassSurface surface;
    yune_windows::LanguageBarState state;
    state.dpi = 96;
    yune_windows::ToolbarSkin acrylic_skin = default_skin;
    acrylic_skin.glass_mechanism =
        yune_windows::ToolbarGlassMechanism::DwmAcrylic;
    acrylic_skin.glass_fallback =
        yune_windows::ToolbarGlassMechanism::StaticTint;
    acrylic_skin.background.a = 0.42f;
    yune_windows::ToolbarSkin static_skin = acrylic_skin;
    static_skin.glass_mechanism =
        yune_windows::ToolbarGlassMechanism::StaticTint;
    static_skin.glass_fallback =
        yune_windows::ToolbarGlassMechanism::StaticTint;

    // Windows 11 22000 must not receive DWMWA_SYSTEMBACKDROP_TYPE at all.
    ResetBackdropTrace();
    hook_scope.SetBuild(22000);
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        surface.acrylic_backdrop_active_for_testing() ||
        !g_backdrop_trace.system_backdrops.empty()) {
        std::cerr << "build 22000 attempted or recorded system acrylic\n";
        return false;
    }
    const yune_windows::ToolbarSkinColor old_build_background =
        yune_windows::EffectiveToolbarPillBackgroundForTesting(
            acrylic_skin,
            surface.acrylic_backdrop_active_for_testing());
    if (old_build_background.a != 1.0f) {
        std::cerr << "build 22000 fallback did not force an opaque pill\n";
        return false;
    }

    surface.DiscardDeviceResources();

    // On 22621, success becomes the effective state. Re-presenting the same
    // skin at the same size must render without repeating any DWM calls.
    ResetBackdropTrace();
    hook_scope.SetBuild(22621);
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        !surface.acrylic_backdrop_active_for_testing() ||
        g_backdrop_trace.system_backdrops !=
            std::vector<DWORD>{kBackdropTransientWindow} ||
        !HasFrameMargins({-1, -1, -1, -1})) {
        std::cerr << "build 22621 acrylic success was not recorded\n";
        return false;
    }
    const yune_windows::ToolbarSkinColor acrylic_background =
        yune_windows::EffectiveToolbarPillBackgroundForTesting(
            acrylic_skin,
            surface.acrylic_backdrop_active_for_testing());
    if (acrylic_background.a != acrylic_skin.background.a) {
        std::cerr << "effective acrylic did not preserve the skin alpha\n";
        return false;
    }
    const size_t unchanged_attributes =
        g_backdrop_trace.system_backdrops.size();
    const size_t unchanged_frames = g_backdrop_trace.frame_margins.size();
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        g_backdrop_trace.system_backdrops.size() != unchanged_attributes ||
        g_backdrop_trace.frame_margins.size() != unchanged_frames) {
        std::cerr << "unchanged present repeated DWM backdrop calls\n";
        return false;
    }

    // Equal-size skin transitions must explicitly clear and then reapply DWM.
    ResetBackdropTrace();
    if (!surface.PresentLanguageBar(
            test_window.get(), state, static_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        surface.acrylic_backdrop_active_for_testing() ||
        g_backdrop_trace.system_backdrops !=
            std::vector<DWORD>{kBackdropNone} ||
        !HasFrameMargins({0, 0, 0, 0})) {
        std::cerr << "same-size acrylic-to-static transition did not clear DWM\n";
        return false;
    }
    if (yune_windows::EffectiveToolbarPillBackgroundForTesting(
            static_skin,
            surface.acrylic_backdrop_active_for_testing()).a != 1.0f) {
        std::cerr << "static transition did not force an opaque pill\n";
        return false;
    }

    ResetBackdropTrace();
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        !surface.acrylic_backdrop_active_for_testing() ||
        g_backdrop_trace.system_backdrops !=
            std::vector<DWORD>{kBackdropTransientWindow} ||
        !HasFrameMargins({-1, -1, -1, -1})) {
        std::cerr << "same-size static-to-acrylic transition did not reapply DWM\n";
        return false;
    }

    // A failed 22621 acrylic request must record effective static state, clear
    // the attempted frame extension, and remain opaque on later renders.
    surface.DiscardDeviceResources();
    ResetBackdropTrace(E_FAIL);
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        surface.acrylic_backdrop_active_for_testing() ||
        g_backdrop_trace.system_backdrops !=
            std::vector<DWORD>{kBackdropTransientWindow, kBackdropNone} ||
        !HasFrameMargins({-1, -1, -1, -1}) ||
        !HasFrameMargins({0, 0, 0, 0})) {
        std::cerr << "build 22621 acrylic failure did not use effective static\n";
        return false;
    }
    if (yune_windows::EffectiveToolbarPillBackgroundForTesting(
            acrylic_skin,
            surface.acrylic_backdrop_active_for_testing()).a != 1.0f) {
        std::cerr << "failed acrylic did not force an opaque pill\n";
        return false;
    }
    const size_t failed_attributes =
        g_backdrop_trace.system_backdrops.size();
    const size_t failed_frames = g_backdrop_trace.frame_margins.size();
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        g_backdrop_trace.system_backdrops.size() != failed_attributes ||
        g_backdrop_trace.frame_margins.size() != failed_frames) {
        std::cerr << "failed acrylic state retried DWM on unchanged present\n";
        return false;
    }

    // Full-frame extension is part of the effective backdrop contract. Even if
    // the system-backdrop attribute would succeed, a frame failure must keep
    // rendering on the opaque static fallback.
    surface.DiscardDeviceResources();
    ResetBackdropTrace(S_OK, E_FAIL);
    if (!surface.PresentLanguageBar(
            test_window.get(), state, acrylic_skin,
            yune_windows::LanguageBarSegment::AsciiMode,
            yune_windows::LanguageBarSegment::AsciiMode, false, false) ||
        surface.acrylic_backdrop_active_for_testing() ||
        g_backdrop_trace.system_backdrops !=
            std::vector<DWORD>{kBackdropNone} ||
        !HasFrameMargins({-1, -1, -1, -1}) ||
        !HasFrameMargins({0, 0, 0, 0}) ||
        yune_windows::EffectiveToolbarPillBackgroundForTesting(
            acrylic_skin,
            surface.acrylic_backdrop_active_for_testing()).a != 1.0f) {
        std::cerr << "failed frame extension did not use effective static\n";
        return false;
    }

    return true;
}

int SelfTest() {
    const HRESULT co_init_result =
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool co_initialized = SUCCEEDED(co_init_result);

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

    yune_windows::ToolbarSkin custom_skin;
    custom_skin.segment_labels = {L"AA", L"SS", L"OO", L"KK", L"GG"};
    yune_windows::LanguageBarState label_state;
    label_state.ascii_mode = false;
    label_state.full_shape = false;
    label_state.output_standard = L"hong_kong_traditional";
    label_state.schema_id = L"jyut6ping3";
    if (yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::AsciiMode, label_state,
            custom_skin) != L"AA" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::FullShape, label_state,
            custom_skin) != L"SS" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::OutputStandard, label_state,
            custom_skin) != L"OO" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::Schema, label_state,
            custom_skin) != L"KK" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::Settings, label_state,
            custom_skin) != L"GG") {
        std::cerr << "toolbar segment labels did not use the skin manifest\n";
        return 1;
    }
    label_state.ascii_mode = true;
    label_state.full_shape = true;
    label_state.output_standard = L"mainland_simplified";
    label_state.schema_id = L"luna_pinyin";
    if (yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::AsciiMode, label_state,
            custom_skin) != L"\x82f1" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::FullShape, label_state,
            custom_skin) != L"\x5168" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::OutputStandard, label_state,
            custom_skin) != L"\x7b80" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::Schema, label_state,
            custom_skin) != L"\x6719" ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::Settings, label_state,
            custom_skin) != L"GG") {
        std::cerr << "toolbar state-specific labels were not preserved\n";
        return 1;
    }
    label_state.schema_id = L"luna_pinyin_octagram";
    if (yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::Schema, label_state,
            custom_skin) != L"\x6719") {
        std::cerr << "toolbar octagram schema label fell back to a Latin glyph\n";
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
    if (!MakeForeground(owner, 1500)) {
        std::cerr << "failed to foreground smoke owner\n";
        DestroyWindow(owner);
        return 1;
    }

    if (!RunBackdropRegressionSmoke(owner, default_skin)) {
        DestroyWindow(owner);
        return 1;
    }

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

    yune_windows::LanguageBarWindow ownerless_toolbar;
    if (!ownerless_toolbar.Update(state, true) ||
        ownerless_toolbar.native_handle_for_testing() != nullptr) {
        std::cerr << "ownerless language bar was not rejected fail-closed\n";
        DestroyWindow(owner);
        return 1;
    }

    state.owner = owner;

    if (!toolbar.Update(state, true)) {
        std::cerr << "language bar failed to update\n";
        DestroyWindow(owner);
        return 1;
    }

    HWND bar_hwnd = toolbar.native_handle_for_testing();
    if (!bar_hwnd) {
        std::cerr << "language bar window was not created\n";
        DestroyWindow(owner);
        return 1;
    }
    if (GetWindow(bar_hwnd, GW_OWNER) != owner) {
        std::cerr << "language bar did not retain its concrete owner\n";
        DestroyWindow(owner);
        return 1;
    }

    {
        yune_windows::LanguageBarWindow second_toolbar;
        if (!second_toolbar.Update(state, true)) {
            std::cerr << "second language bar failed to update\n";
            DestroyWindow(owner);
            return 1;
        }
        PumpMessages(100);
        const int visible_count = VisibleLanguageBarCountForCurrentProcess();
        const bool second_visible =
            IsWindowVisible(second_toolbar.native_handle_for_testing()) != FALSE;
        const bool first_visible = IsWindowVisible(bar_hwnd) != FALSE;
        if (visible_count != 1 || !second_visible || first_visible) {
            std::cerr << "same-process toolbar arbitration failed: visible="
                      << visible_count << " first=" << first_visible
                      << " second=" << second_visible
                      << " foreground=" << GetForegroundWindow()
                      << " owner=" << owner
                      << " first_owner=" << GetWindow(bar_hwnd, GW_OWNER)
                      << " second_owner="
                      << GetWindow(second_toolbar.native_handle_for_testing(),
                                   GW_OWNER)
                      << "\n";
            DestroyWindow(owner);
            return 1;
        }
        second_toolbar.Hide();
    }
    if (!toolbar.Update(state, true)) {
        std::cerr << "primary language bar did not reclaim visibility\n";
        DestroyWindow(owner);
        return 1;
    }
    PumpMessages(50);
    if (VisibleLanguageBarCountForCurrentProcess() != 1 ||
        !IsWindowVisible(bar_hwnd)) {
        std::cerr << "primary language bar visibility was not restored\n";
        DestroyWindow(owner);
        return 1;
    }
    if (!RunCrossProcessSupersessionSmoke(toolbar, state, owner, bar_hwnd)) {
        DestroyWindow(owner);
        return 1;
    }
    const LONG_PTR ex_style = GetWindowLongPtrW(bar_hwnd, GWL_EXSTYLE);
    if ((ex_style & WS_EX_NOACTIVATE) == 0 ||
        (ex_style & WS_EX_TOOLWINDOW) == 0 ||
        (ex_style & WS_EX_TOPMOST) == 0 ||
        (ex_style & WS_EX_NOREDIRECTIONBITMAP) == 0) {
        std::cerr << "language bar missing no-activate DComp popup styles\n";
        DestroyWindow(owner);
        return 1;
    }

    const HWND foreground_before = GetForegroundWindow();
    const size_t stable_toolbar_count =
        LanguageBarWindowsForCurrentProcess().size();
    for (int drag_index = 0; drag_index < 50; ++drag_index) {
        RECT before = {};
        GetWindowRect(bar_hwnd, &before);
        const POINT drag_start_client = {Scale(10, state.dpi),
                                         Scale(18, state.dpi)};
        POINT drag_start_screen = drag_start_client;
        ClientToScreen(bar_hwnd, &drag_start_screen);
        SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON,
                     MAKELPARAM(drag_start_client.x, drag_start_client.y));
        toolbar.reset_render_count_for_testing();
        const int direction = (drag_index % 2 == 0) ? 1 : -1;
        POINT final_screen = drag_start_screen;
        for (int move_index = 0; move_index < 100; ++move_index) {
            final_screen.x = drag_start_screen.x +
                             direction * (8 + (move_index * 32 / 99));
            final_screen.y = drag_start_screen.y +
                             direction * (4 + (move_index * 8 / 99));
            SendPointerMoveAtScreen(bar_hwnd, final_screen);
            if (drag_index == 0 && move_index == 20) {
                (void)toolbar.Update(state, true);
                SendMessageW(bar_hwnd, WM_PAINT, 0, 0);
            }
            if (drag_index == 0 && move_index == 40) {
                RECT suggested = {};
                GetWindowRect(bar_hwnd, &suggested);
                OffsetRect(&suggested, 4, 4);
                SendMessageW(bar_hwnd, WM_DPICHANGED,
                             MAKEWPARAM(144, 144),
                             reinterpret_cast<LPARAM>(&suggested));
            }
        }
        if (toolbar.render_count_for_testing() != 0) {
            std::cerr << "language bar rendered during drag movement\n";
            DestroyWindow(owner);
            return 1;
        }
        POINT release_client = final_screen;
        ScreenToClient(bar_hwnd, &release_client);
        const int position_count_before = g_position_change_count;
        SendMessageW(bar_hwnd, WM_LBUTTONUP, 0,
                     MAKELPARAM(release_client.x, release_client.y));
        if (toolbar.render_count_for_testing() != 1 ||
            g_position_change_count != position_count_before + 1) {
            std::cerr << "drag did not flush exactly one render/position update\n";
            DestroyWindow(owner);
            return 1;
        }
        RECT after = {};
        GetWindowRect(bar_hwnd, &after);
        if (after.left == before.left && after.top == before.top) {
            std::cerr << "language bar stress drag did not move\n";
            DestroyWindow(owner);
            return 1;
        }
        if (toolbar.native_handle_for_testing() != bar_hwnd ||
            VisibleLanguageBarCountForCurrentProcess() != 1 ||
            LanguageBarWindowsForCurrentProcess().size() !=
                stable_toolbar_count) {
            std::cerr << "drag created or exposed a duplicate toolbar HWND\n";
            DestroyWindow(owner);
            return 1;
        }
        if (g_position_x != after.left || g_position_y != after.top) {
            std::cerr << "drag callback reported a stale toolbar position\n";
            DestroyWindow(owner);
            return 1;
        }
    }
    const HWND foreground_after = GetForegroundWindow();
    if (foreground_after == bar_hwnd ||
        (foreground_before && foreground_after != foreground_before)) {
        std::cerr << "language bar stole foreground focus during drag\n";
        DestroyWindow(owner);
        return 1;
    }

    const LPARAM click_point =
        MAKELPARAM(Scale(42, state.dpi), Scale(18, state.dpi));
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, click_point);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, click_point);
    if (g_ascii_click_count != 1) {
        std::cerr << "language bar click did not route to segment handler\n";
        DestroyWindow(owner);
        return 1;
    }

    RECT client = {};
    GetClientRect(bar_hwnd, &client);
    g_ascii_click_count = 0;
    g_settings_click_count = 0;
    const LPARAM same_segment_move =
        MAKELPARAM(Scale(52, state.dpi), Scale(18, state.dpi));
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, click_point);
    SendMessageW(bar_hwnd, WM_MOUSEMOVE, MK_LBUTTON, same_segment_move);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, same_segment_move);
    if (g_ascii_click_count != 0 || g_settings_click_count != 0) {
        std::cerr << "language bar over-threshold movement still clicked\n";
        DestroyWindow(owner);
        return 1;
    }

    g_settings_click_count = 0;
    RECT before_settings_drag = {};
    GetWindowRect(bar_hwnd, &before_settings_drag);
    const LPARAM settings_drag_start =
        MAKELPARAM(client.right - Scale(18, state.dpi), Scale(18, state.dpi));
    const LPARAM settings_drag_move =
        MAKELPARAM(client.right - Scale(74, state.dpi), Scale(44, state.dpi));
    g_ascii_click_count = 0;
    g_settings_click_count = 0;
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, click_point);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, settings_drag_start);
    if (g_ascii_click_count != 0 || g_settings_click_count != 0) {
        std::cerr << "language bar cross-segment release still clicked\n";
        DestroyWindow(owner);
        return 1;
    }

    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, settings_drag_start);
    SendMessageW(bar_hwnd, WM_MOUSEMOVE, MK_LBUTTON, settings_drag_move);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, settings_drag_move);
    RECT after_settings_drag = {};
    GetWindowRect(bar_hwnd, &after_settings_drag);
    if (g_settings_click_count != 0 ||
        (after_settings_drag.left == before_settings_drag.left &&
         after_settings_drag.top == before_settings_drag.top)) {
        std::cerr << "settings segment drag clicked or failed to move toolbar\n";
        DestroyWindow(owner);
        return 1;
    }

    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, settings_drag_start);
    SendMessageW(bar_hwnd, WM_LBUTTONUP, 0, settings_drag_start);
    if (g_settings_click_count != 1) {
        std::cerr << "settings segment click did not route to handler\n";
        DestroyWindow(owner);
        return 1;
    }

    // Unexpected capture loss after movement persists once and renders once.
    const POINT capture_start_client = {Scale(10, state.dpi),
                                        Scale(18, state.dpi)};
    POINT capture_start_screen = capture_start_client;
    ClientToScreen(bar_hwnd, &capture_start_screen);
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON,
                 MAKELPARAM(capture_start_client.x, capture_start_client.y));
    toolbar.reset_render_count_for_testing();
    POINT capture_move_screen = {capture_start_screen.x + 24,
                                 capture_start_screen.y + 8};
    SendPointerMoveAtScreen(bar_hwnd, capture_move_screen);
    const int capture_position_before = g_position_change_count;
    SetCapture(owner);
    if (g_position_change_count != capture_position_before + 1 ||
        toolbar.render_count_for_testing() != 1 ||
        g_ascii_click_count != 0) {
        std::cerr << "unexpected capture loss was not finalized exactly once\n";
        ReleaseCapture();
        DestroyWindow(owner);
        return 1;
    }
    ReleaseCapture();

    // Cancel before the threshold must not persist or click.
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON,
                 MAKELPARAM(capture_start_client.x, capture_start_client.y));
    toolbar.reset_render_count_for_testing();
    const int cancel_position_before = g_position_change_count;
    SendMessageW(bar_hwnd, WM_CANCELMODE, 0, 0);
    if (g_position_change_count != cancel_position_before ||
        g_ascii_click_count != 0 ||
        toolbar.render_count_for_testing() != 1) {
        std::cerr << "pre-threshold cancel persisted, clicked, or over-rendered\n";
        DestroyWindow(owner);
        return 1;
    }

    // Cancel after the threshold must persist the final position once and
    // perform exactly one final render.
    RECT before_drag_cancel = {};
    GetWindowRect(bar_hwnd, &before_drag_cancel);
    capture_start_screen = capture_start_client;
    ClientToScreen(bar_hwnd, &capture_start_screen);
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON,
                 MAKELPARAM(capture_start_client.x, capture_start_client.y));
    toolbar.reset_render_count_for_testing();
    capture_move_screen = {capture_start_screen.x + 28,
                           capture_start_screen.y + 9};
    SendPointerMoveAtScreen(bar_hwnd, capture_move_screen);
    const int drag_cancel_position_before = g_position_change_count;
    SendMessageW(bar_hwnd, WM_CANCELMODE, 0, 0);
    RECT after_drag_cancel = {};
    GetWindowRect(bar_hwnd, &after_drag_cancel);
    if (g_position_change_count != drag_cancel_position_before + 1 ||
        toolbar.render_count_for_testing() != 1 ||
        (after_drag_cancel.left == before_drag_cancel.left &&
         after_drag_cancel.top == before_drag_cancel.top) ||
        GetCapture() == bar_hwnd) {
        std::cerr << "post-threshold cancel did not finalize movement once\n";
        DestroyWindow(owner);
        return 1;
    }

    // Hide during a drag uses the same finalizer, persists once, and does not
    // present a final frame for an invisible toolbar.
    capture_start_screen = capture_start_client;
    ClientToScreen(bar_hwnd, &capture_start_screen);
    SendMessageW(bar_hwnd, WM_LBUTTONDOWN, MK_LBUTTON,
                 MAKELPARAM(capture_start_client.x, capture_start_client.y));
    toolbar.reset_render_count_for_testing();
    capture_move_screen = {capture_start_screen.x - 26,
                           capture_start_screen.y - 8};
    SendPointerMoveAtScreen(bar_hwnd, capture_move_screen);
    const int hide_position_before = g_position_change_count;
    toolbar.Hide();
    if (g_position_change_count != hide_position_before + 1 ||
        toolbar.render_count_for_testing() != 0 || IsWindowVisible(bar_hwnd) ||
        GetCapture() == bar_hwnd) {
        std::cerr << "mid-drag hide did not finalize without presenting\n";
        DestroyWindow(owner);
        return 1;
    }
    if (!MakeForeground(owner) || !toolbar.Update(state, true) ||
        !IsWindowVisible(bar_hwnd)) {
        std::cerr << "toolbar did not recover after mid-drag hide\n";
        DestroyWindow(owner);
        return 1;
    }

    // A direct destroy must run WM_NCDESTROY cleanup and allow the same object
    // to create one clean replacement window.
    DestroyWindow(bar_hwnd);
    PumpMessages(50);
    if (toolbar.native_handle_for_testing() != nullptr ||
        VisibleLanguageBarCountForCurrentProcess() != 0) {
        std::cerr << "WM_NCDESTROY did not clear language-bar state\n";
        DestroyWindow(owner);
        return 1;
    }
    if (!MakeForeground(owner) || !toolbar.Update(state, true)) {
        std::cerr << "language bar did not recreate after WM_NCDESTROY\n";
        DestroyWindow(owner);
        return 1;
    }
    bar_hwnd = toolbar.native_handle_for_testing();
    if (!bar_hwnd || !IsWindowVisible(bar_hwnd) ||
        GetWindow(bar_hwnd, GW_OWNER) != owner ||
        VisibleLanguageBarCountForCurrentProcess() != 1) {
        std::cerr << "recreated language bar was not cleanly owned and unique\n";
        DestroyWindow(owner);
        return 1;
    }

    // An ownerless refresh must fail closed without detaching the existing HWND.
    state.owner = nullptr;
    if (!toolbar.Update(state, true) || IsWindowVisible(bar_hwnd) ||
        GetWindow(bar_hwnd, GW_OWNER) != owner) {
        std::cerr << "ownerless refresh detached or exposed the toolbar\n";
        DestroyWindow(owner);
        return 1;
    }
    state.owner = owner;
    (void)MakeForeground(owner, 1500);
    if (!toolbar.Update(state, true)) {
        std::cerr << "owned toolbar did not recover after ownerless refresh\n";
        DestroyWindow(owner);
        return 1;
    }

    HWND other_owner = CreateWindowExW(
        0, L"YuneWindowsLanguageBarSmokeOwner", L"Yune second smoke owner",
        WS_OVERLAPPEDWINDOW, 460, 80, 320, 160, nullptr, nullptr,
        GetModuleHandleW(nullptr), nullptr);
    if (!other_owner) {
        std::cerr << "failed to create second smoke owner\n";
        DestroyWindow(owner);
        return 1;
    }
    ShowWindow(other_owner, SW_SHOWNORMAL);
    UpdateWindow(other_owner);
    (void)MakeForeground(other_owner, 1500);
    PumpMessages(600);
    if (IsWindowVisible(bar_hwnd)) {
        std::cerr << "foreground watchdog left a stale toolbar visible\n";
        DestroyWindow(other_owner);
        DestroyWindow(owner);
        return 1;
    }
    DestroyWindow(other_owner);

    if (!MakeForeground(owner) || !toolbar.Update(state, true)) {
        std::cerr << "toolbar did not recover after watchdog test\n";
        DestroyWindow(owner);
        return 1;
    }
    bar_hwnd = toolbar.native_handle_for_testing();
    DestroyWindow(owner);
    PumpMessages(50);
    if ((toolbar.native_handle_for_testing() &&
         IsWindowVisible(toolbar.native_handle_for_testing())) ||
        !toolbar.Update(state, true) ||
        (toolbar.native_handle_for_testing() &&
         IsWindowVisible(toolbar.native_handle_for_testing()))) {
        std::cerr << "owner destruction did not fail closed\n";
        toolbar.Hide();
        return 1;
    }
    toolbar.Hide();
    if (co_initialized) {
        CoUninitialize();
    }
    std::cout << "language bar smoke passed\n";
    return 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && std::wstring(argv[1]) == L"--self-test") {
        return SelfTest();
    }
    if (argc == 5 &&
        std::wstring(argv[1]) == L"--supersession-child") {
        wchar_t* end = nullptr;
        const unsigned long parent_process_id = wcstoul(argv[4], &end, 10);
        if (!end || *end != L'\0' || parent_process_id == 0) {
            return 3;
        }
        return RunSupersessionChild(argv[2], argv[3],
                                    static_cast<DWORD>(parent_process_id));
    }
    std::cerr << "usage: YuneWindowsLanguageBarSmoke.exe --self-test\n"
                 "       YuneWindowsLanguageBarSmoke.exe "
                 "--supersession-child <ready-event> <stop-event> <parent-pid>\n";
    return 2;
}
