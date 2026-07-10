#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <msctf.h>
#include <strsafe.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <filesystem>
#include <mutex>
#include <new>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#include "../candidate_window/yune_windows_candidate_window.h"
#include "yune_windows_reliability_core.h"

namespace {

// {1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}
const CLSID kTextServiceClsid = {
    0x1788dba7,
    0xcc9a,
    0x49e2,
    {0x9c, 0x4c, 0xe9, 0xdb, 0xf0, 0xbe, 0x25, 0x67}};

// {3AE69B8D-19B4-4267-8F21-E239666D6632}
const GUID kProfileGuid = {
    0x3ae69b8d,
    0x19b4,
    0x4267,
    {0x8f, 0x21, 0xe2, 0x39, 0x66, 0x6d, 0x66, 0x32}};

// Ctrl+Shift+2
const GUID kSchemaCyclePreservedKeyGuid = {
    0xd1d56b79,
    0x2f1f,
    0x4e0d,
    {0xb0, 0x74, 0xe4, 0x72, 0x0e, 0x72, 0x43, 0x12}};

// Ctrl+Shift+3
const GUID kFullShapePreservedKeyGuid = {
    0x88b8152f,
    0xde9c,
    0x4c45,
    {0x8c, 0xe6, 0x5a, 0x2c, 0xaf, 0x3e, 0x62, 0x97}};

const TF_PRESERVEDKEY kSchemaCyclePreservedKey = {L'2',
                                                  TF_MOD_CONTROL | TF_MOD_SHIFT};
const TF_PRESERVEDKEY kFullShapePreservedKey = {L'3',
                                                TF_MOD_CONTROL | TF_MOD_SHIFT};

constexpr LANGID kTextServiceLangId = 0x0c04;
constexpr const wchar_t* kTextServiceDesc = L"Yune Windows";
constexpr const wchar_t* kThreadingModel = L"Apartment";
constexpr const wchar_t* kPipeName = L"\\\\.\\pipe\\yune-windows-ime";
constexpr DWORD kServerQueryTimeoutMs = 5000;
constexpr DWORD kServerKeyPathQueryTimeoutMs = 200;
constexpr DWORD kServerFocusRefreshTimeoutMs = 100;
constexpr DWORD kServerPipeReconnectWaitMs = 250;
constexpr DWORD kServerLaunchReadyWaitMs = 15000;
constexpr DWORD kServerLaunchMutexWaitMs = 250;
constexpr DWORD kServerPipeMissingRetrySleepMs = 15;
constexpr ULONGLONG kServerLaunchCooldownMs = 1500;
constexpr UINT kShiftHookToggleMessage = WM_APP + 0x5a;
constexpr UINT kFocusedServiceSupersededMessage = WM_APP + 0x5b;
constexpr UINT kShiftHookRepeatMessage = WM_APP + 0x5c;
constexpr UINT kShiftHookModifiedMessage = WM_APP + 0x5d;
constexpr UINT kShiftHookMouseMessage = WM_APP + 0x5e;
constexpr UINT kShiftHookConsumedMessage = WM_APP + 0x5f;
constexpr UINT_PTR kFocusedServiceWatchdogTimer = 1;
constexpr UINT kFocusedServiceWatchdogIntervalMs = 250;
constexpr unsigned int kMaxAsciiToggleCasAttempts = 2;
constexpr ULONGLONG kPendingAsciiToggleDeadlineMs = 1500;
constexpr const wchar_t* kFocusedServiceWindowClass =
    L"YuneWindowsFocusedServiceWindow";
constexpr int kCandidatePageSize = 5;
constexpr LPARAM kKeyWasDownMask = 0x40000000;

enum class RefreshStateMode {
    AllowLaunch,
    ExistingServerOnly,
};

enum class ShiftDetector {
    Sink,
    Hook,
};

enum class ShiftRejectionReason {
    None,
    Repeat,
    Modified,
    MouseOrCapture,
    Consumed,
};

constexpr const char* ShiftDetectorName(ShiftDetector detector) {
    return detector == ShiftDetector::Hook ? "hook" : "sink";
}

constexpr const char* ShiftRejectionDisposition(
    ShiftRejectionReason reason) {
    switch (reason) {
        case ShiftRejectionReason::Repeat:
            return "rejected_repeat";
        case ShiftRejectionReason::Modified:
            return "rejected_modified";
        case ShiftRejectionReason::MouseOrCapture:
            return "rejected_mouse_or_capture";
        case ShiftRejectionReason::Consumed:
            return "rejected_consumed";
        case ShiftRejectionReason::None:
            break;
    }
    return "rejected_consumed";
}

constexpr UINT ShiftHookRejectionMessage(ShiftRejectionReason reason) {
    switch (reason) {
        case ShiftRejectionReason::Repeat:
            return kShiftHookRepeatMessage;
        case ShiftRejectionReason::Modified:
            return kShiftHookModifiedMessage;
        case ShiftRejectionReason::MouseOrCapture:
            return kShiftHookMouseMessage;
        case ShiftRejectionReason::Consumed:
            return kShiftHookConsumedMessage;
        case ShiftRejectionReason::None:
            break;
    }
    return 0;
}

constexpr ShiftRejectionReason ShiftHookRejectionReason(UINT message) {
    switch (message) {
        case kShiftHookRepeatMessage:
            return ShiftRejectionReason::Repeat;
        case kShiftHookModifiedMessage:
            return ShiftRejectionReason::Modified;
        case kShiftHookMouseMessage:
            return ShiftRejectionReason::MouseOrCapture;
        case kShiftHookConsumedMessage:
            return ShiftRejectionReason::Consumed;
        default:
            return ShiftRejectionReason::None;
    }
}

class TextService;

HINSTANCE g_instance = nullptr;
std::atomic<long> g_dll_refs = 0;
std::atomic<unsigned long long> g_last_server_launch_attempt_ms = 0;
std::atomic<unsigned long> g_structural_event_sequence = 0;
std::atomic<bool> g_server_warmup_inflight = false;
std::atomic<bool> g_hook_shift_down = false;
std::atomic<bool> g_hook_shift_consumed = false;
std::atomic<ShiftRejectionReason> g_hook_shift_rejection_reason =
    ShiftRejectionReason::None;
std::atomic<unsigned long long> g_shift_sequence = 0;
std::atomic<unsigned long long> g_hook_shift_snapshot = 0;
std::atomic<unsigned long long> g_focused_service_generation = 0;
std::atomic<unsigned long long> g_published_focus_generation = 0;
std::atomic<unsigned long long> g_shift_hook_active_generation = 0;
unsigned long long g_committed_focus_generation = 0;
std::mutex g_structural_log_mutex;
std::mutex g_shift_hook_mutex;
HHOOK g_shift_hook = nullptr;
DWORD g_shift_hook_thread_id = 0;
std::atomic<HWND> g_shift_hook_dispatcher{nullptr};
std::atomic<DWORD> g_shift_hook_dispatcher_thread_id{0};
TextService* g_focused_text_service = nullptr;
constexpr size_t kShiftCorrelationCapacity = 256;
std::array<std::atomic<unsigned long long>, kShiftCorrelationCapacity>
    g_hook_shift_history = {};
std::array<std::atomic<DWORD>, kShiftCorrelationCapacity>
    g_hook_shift_history_time = {};
std::array<std::atomic<bool>, kShiftCorrelationCapacity>
    g_hook_shift_history_consumed = {};

constexpr unsigned long long PackShiftSnapshot(unsigned long token,
                                               unsigned long generation) {
    return (static_cast<unsigned long long>(generation) << 32) |
           static_cast<unsigned long long>(token);
}

constexpr unsigned long ShiftSnapshotToken(unsigned long long snapshot) {
    return static_cast<unsigned long>(snapshot & 0xffffffffull);
}

constexpr unsigned long ShiftSnapshotGeneration(
    unsigned long long snapshot) {
    return static_cast<unsigned long>(snapshot >> 32);
}

unsigned long NextNonzeroSequence(
    std::atomic<unsigned long long>* sequence) {
    if (!sequence) {
        return 0;
    }
    for (;;) {
        const unsigned long value =
            static_cast<unsigned long>(++(*sequence));
        if (value != 0) {
            return value;
        }
    }
}

void ResetShiftCorrelationHistory() {
    g_hook_shift_rejection_reason.store(ShiftRejectionReason::None,
                                        std::memory_order_release);
    for (auto& snapshot : g_hook_shift_history) {
        snapshot.store(0, std::memory_order_release);
    }
    for (auto& event_time : g_hook_shift_history_time) {
        event_time.store(0, std::memory_order_release);
    }
    for (auto& consumed : g_hook_shift_history_consumed) {
        consumed.store(false, std::memory_order_release);
    }
}

void SetHookShiftRejectionIfNone(ShiftRejectionReason reason) {
    if (reason == ShiftRejectionReason::None) {
        return;
    }
    ShiftRejectionReason expected = ShiftRejectionReason::None;
    (void)g_hook_shift_rejection_reason.compare_exchange_strong(
        expected, reason, std::memory_order_acq_rel,
        std::memory_order_acquire);
}

unsigned long long FindShiftHookSnapshot(unsigned long generation,
                                         unsigned long after_token,
                                         DWORD message_time) {
    unsigned long best_token = 0;
    unsigned long long best_snapshot = 0;
    for (size_t index = 0; index < g_hook_shift_history.size(); ++index) {
        const unsigned long long snapshot =
            g_hook_shift_history[index].load(std::memory_order_acquire);
        const DWORD event_time = g_hook_shift_history_time[index].load(
            std::memory_order_relaxed);
        if (g_hook_shift_history[index].load(std::memory_order_acquire) !=
            snapshot) {
            continue;
        }
        const unsigned long token = ShiftSnapshotToken(snapshot);
        if (ShiftSnapshotGeneration(snapshot) != generation ||
            event_time != message_time ||
            token <= after_token ||
            (best_token != 0 && token >= best_token)) {
            continue;
        }
        best_token = token;
        best_snapshot = snapshot;
    }
    return best_snapshot;
}

bool ShiftHookTokenWasConsumed(unsigned long token,
                               unsigned long generation) {
    if (token == 0 || generation == 0) {
        return false;
    }
    const size_t index = token % kShiftCorrelationCapacity;
    const unsigned long long expected =
        PackShiftSnapshot(token, generation);
    const unsigned long long before =
        g_hook_shift_history[index].load(std::memory_order_acquire);
    const bool consumed = g_hook_shift_history_consumed[index].load(
        std::memory_order_acquire);
    const unsigned long long after =
        g_hook_shift_history[index].load(std::memory_order_acquire);
    return before == expected && after == expected && consumed;
}

void MarkShiftHookSnapshotConsumed(unsigned long long snapshot) {
    const unsigned long token = ShiftSnapshotToken(snapshot);
    if (token == 0) {
        return;
    }
    const size_t index = token % kShiftCorrelationCapacity;
    if (g_hook_shift_history[index].load(std::memory_order_acquire) ==
        snapshot) {
        g_hook_shift_history_consumed[index].store(
            true, std::memory_order_release);
    }
}

void MarkCurrentShiftHookTokenConsumed() {
    MarkShiftHookSnapshotConsumed(
        g_hook_shift_snapshot.load(std::memory_order_acquire));
}

void DllAddRef() {
    ++g_dll_refs;
}

void DllRelease() {
    --g_dll_refs;
}

bool IsHandledKey(WPARAM key) {
    return (key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z') ||
           key == VK_SPACE || key == VK_RETURN ||
           (key >= L'1' && key <= L'9') || key == VK_BACK ||
           key == VK_ESCAPE || key == VK_NEXT || key == VK_PRIOR;
}

bool IsShiftKey(WPARAM key) {
    return key == VK_SHIFT || key == VK_LSHIFT || key == VK_RSHIFT;
}

bool IsShortcutModifierKey(WPARAM key) {
    return key == VK_CONTROL || key == VK_LCONTROL || key == VK_RCONTROL ||
           key == VK_MENU || key == VK_LMENU || key == VK_RMENU ||
           key == VK_LWIN || key == VK_RWIN;
}

bool IsShiftPressed() {
    return (GetKeyState(VK_SHIFT) & 0x8000) != 0;
}

bool IsShortcutModifierDown() {
    return (GetKeyState(VK_CONTROL) & 0x8000) != 0 ||
           (GetKeyState(VK_MENU) & 0x8000) != 0 ||
           (GetKeyState(VK_LWIN) & 0x8000) != 0 ||
           (GetKeyState(VK_RWIN) & 0x8000) != 0;
}

bool IsMouseButtonDown() {
    return (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0 ||
           (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0 ||
           (GetAsyncKeyState(VK_MBUTTON) & 0x8000) != 0;
}

void ClearMouseButtonTransitionBits() {
    (void)GetAsyncKeyState(VK_LBUTTON);
    (void)GetAsyncKeyState(VK_RBUTTON);
    (void)GetAsyncKeyState(VK_MBUTTON);
}

bool MouseButtonTransitionOrDown() {
    return (GetAsyncKeyState(VK_LBUTTON) & 0x8001) != 0 ||
           (GetAsyncKeyState(VK_RBUTTON) & 0x8001) != 0 ||
           (GetAsyncKeyState(VK_MBUTTON) & 0x8001) != 0;
}

wchar_t LowerAscii(WPARAM key) {
    if (key >= L'A' && key <= L'Z') {
        return static_cast<wchar_t>(key - L'A' + L'a');
    }
    return static_cast<wchar_t>(key);
}

std::wstring PunctuationInput(WPARAM key, bool shift) {
    switch (key) {
        case VK_OEM_COMMA:
            return shift ? L"<" : L",";
        case VK_OEM_PERIOD:
            return shift ? L">" : L".";
        case VK_OEM_1:
            return shift ? L":" : L";";
        case VK_OEM_2:
            return shift ? L"?" : L"/";
        case VK_OEM_3:
            return shift ? L"~" : L"`";
        case VK_OEM_4:
            return shift ? L"{" : L"[";
        case VK_OEM_5:
            return shift ? L"|" : L"\\";
        case VK_OEM_6:
            return shift ? L"}" : L"]";
        case VK_OEM_7:
            return shift ? L"\"" : L"'";
        case VK_OEM_MINUS:
            return shift ? L"_" : L"-";
        case VK_OEM_PLUS:
            return shift ? L"+" : L"=";
        case L'1':
            return shift ? L"!" : std::wstring{};
        case L'2':
            return shift ? L"@" : std::wstring{};
        case L'3':
            return shift ? L"#" : std::wstring{};
        case L'4':
            return shift ? L"$" : std::wstring{};
        case L'5':
            return shift ? L"%" : std::wstring{};
        case L'6':
            return shift ? L"^" : std::wstring{};
        case L'7':
            return shift ? L"&" : std::wstring{};
        case L'8':
            return shift ? L"*" : std::wstring{};
        case L'9':
            return shift ? L"(" : std::wstring{};
        case L'0':
            return shift ? L")" : std::wstring{};
        default:
            return {};
    }
}

bool IsPunctuationKey(WPARAM key, bool shift) {
    return !PunctuationInput(key, shift).empty();
}

std::string Narrow(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr,
                                         0, nullptr, nullptr);
    if (size <= 0) {
        return {};
    }
    std::string output(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        output.data(), size, nullptr, nullptr);
    return output;
}

std::wstring Widen(std::string_view value) {
    if (value.empty()) {
        return {};
    }
    const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0);
    if (size <= 0) {
        return {};
    }
    std::wstring output(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        output.data(), size);
    return output;
}

std::filesystem::path ModuleDirectory() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(g_instance, module_path, ARRAYSIZE(module_path))) {
        return {};
    }
    return std::filesystem::path(module_path).parent_path();
}

std::wstring QuoteCommandLineArgument(const std::filesystem::path& value);
bool PathExists(const std::filesystem::path& value);
bool WaitForSharedServerPipe(DWORD timeout_ms);
bool CanLaunchSharedServerFromCurrentHost();
bool RequestSharedServerLaunch();
void RequestSharedServerWarmupAsync();
bool ActivateFocusedTextService(TextService* service);
void DeactivateFocusedTextService(TextService* service);
bool IsCurrentFocusedTextService(TextService* service,
                                 unsigned long long generation);
bool RefreshShiftHookForFocusedService(TextService* service);
LRESULT CALLBACK FocusedServiceWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam);

void WriteStructuralEvent(const char* event_name, int buffer_length = -1,
                          int candidate_count = -1,
                          DWORD error_code = ERROR_SUCCESS,
                          std::string_view attributes = {}) {
    try {
        const std::filesystem::path module_dir = ModuleDirectory();
        if (module_dir.empty()) {
            return;
        }
        const std::filesystem::path log_dir = module_dir / L"logs";
        std::filesystem::create_directories(log_dir);

        static const unsigned long long process_start_nonce =
            (GetTickCount64() << 16) ^ GetCurrentProcessId();
        std::lock_guard<std::mutex> lock(g_structural_log_mutex);
        FILETIME utc = {};
        GetSystemTimePreciseAsFileTime(&utc);
        ULARGE_INTEGER utc_value = {};
        utc_value.LowPart = utc.dwLowDateTime;
        utc_value.HighPart = utc.dwHighDateTime;

        std::ostringstream line;
        line << "event=" << event_name
             << " sequence=" << ++g_structural_event_sequence
             << " utc_filetime=" << utc_value.QuadPart
             << " monotonic_ms=" << GetTickCount64()
             << " pid=" << GetCurrentProcessId()
             << " tid=" << GetCurrentThreadId()
             << " process_nonce=" << process_start_nonce;
        if (buffer_length >= 0) {
            line << " buffer_length=" << buffer_length;
        }
        if (candidate_count >= 0) {
            line << " candidate_count=" << candidate_count;
        }
        if (error_code != ERROR_SUCCESS) {
            line << " error_code=" << error_code;
        }
        if (!attributes.empty()) {
            line << " " << attributes;
        }
        line << "\r\n";
        const std::string encoded = line.str();

        HANDLE log = CreateFileW(
            (log_dir / L"tsf-events.log").c_str(), FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (log == INVALID_HANDLE_VALUE) {
            return;
        }
        DWORD written = 0;
        (void)WriteFile(log, encoded.data(), static_cast<DWORD>(encoded.size()),
                        &written, nullptr);
        CloseHandle(log);
    } catch (...) {
    }
}

std::wstring QuoteCommandLineArgument(const std::filesystem::path& value) {
    std::wstring input = value.wstring();
    std::wstring output = L"\"";
    size_t backslashes = 0;
    for (wchar_t ch : input) {
        if (ch == L'\\') {
            ++backslashes;
            continue;
        }
        if (ch == L'"') {
            output.append(backslashes * 2 + 1, L'\\');
            output.push_back(ch);
            backslashes = 0;
            continue;
        }
        output.append(backslashes, L'\\');
        backslashes = 0;
        output.push_back(ch);
    }
    output.append(backslashes * 2, L'\\');
    output.push_back(L'"');
    return output;
}

bool PathExists(const std::filesystem::path& value) {
    std::error_code error;
    return std::filesystem::exists(value, error);
}

bool WaitForSharedServerPipe(DWORD timeout_ms) {
    const ULONGLONG deadline = GetTickCount64() + timeout_ms;
    do {
        const ULONGLONG now = GetTickCount64();
        const DWORD wait_ms =
            now >= deadline ? 0 : static_cast<DWORD>(deadline - now);
        if (WaitNamedPipeW(kPipeName, wait_ms)) {
            WriteStructuralEvent("server_launch_ready");
            return true;
        }
        if (GetLastError() != ERROR_SEM_TIMEOUT &&
            GetLastError() != ERROR_FILE_NOT_FOUND) {
            break;
        }
        if (GetTickCount64() < deadline) {
            Sleep(kServerPipeMissingRetrySleepMs);
        }
    } while (GetTickCount64() < deadline);
    WriteStructuralEvent("server_launch_timeout");
    return false;
}

bool CanLaunchSharedServerFromCurrentHost() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        return false;
    }

    DWORD is_app_container = 0;
    DWORD returned = 0;
    if (GetTokenInformation(token, TokenIsAppContainer, &is_app_container,
                            sizeof(is_app_container), &returned) &&
        is_app_container != 0) {
        CloseHandle(token);
        return false;
    }

    DWORD needed = 0;
    (void)GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &needed);
    if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && needed > 0) {
        std::vector<unsigned char> buffer(needed);
        if (GetTokenInformation(token, TokenIntegrityLevel, buffer.data(), needed,
                                &needed)) {
            const auto* label =
                reinterpret_cast<const TOKEN_MANDATORY_LABEL*>(buffer.data());
            const DWORD sub_authority_count =
                *GetSidSubAuthorityCount(label->Label.Sid);
            const DWORD integrity_rid =
                *GetSidSubAuthority(label->Label.Sid, sub_authority_count - 1);
            if (integrity_rid < SECURITY_MANDATORY_MEDIUM_RID) {
                CloseHandle(token);
                return false;
            }
        }
    }

    CloseHandle(token);
    return true;
}

bool RequestSharedServerLaunch() {
    if (!CanLaunchSharedServerFromCurrentHost()) {
        WriteStructuralEvent("server_launch_skipped_restricted_host");
        return false;
    }

    const ULONGLONG now = GetTickCount64();
    const ULONGLONG last_attempt = g_last_server_launch_attempt_ms.load();
    if (last_attempt != 0 && now - last_attempt < kServerLaunchCooldownMs) {
        WriteStructuralEvent("server_launch_pending");
        return false;
    }

    const std::filesystem::path module_dir = ModuleDirectory();
    const std::filesystem::path server_exe = module_dir / L"YuneWindowsServer.exe";
    const std::filesystem::path rime_dll = module_dir / L"rime.dll";
    const std::filesystem::path shared_dir = module_dir / L"schema";
    const std::filesystem::path user_dir = module_dir / L"user-data";
    if (module_dir.empty() || !PathExists(server_exe) || !PathExists(rime_dll) ||
        !PathExists(shared_dir) || !PathExists(user_dir)) {
        WriteStructuralEvent("server_launch_failed");
        return false;
    }

    HANDLE launch_mutex = CreateMutexW(
        nullptr, FALSE,
        L"Local\\YuneWindowsServerLaunch_1788DBA7_CC9A_49E2_9C4C_E9DBF0BE2567");
    if (!launch_mutex) {
        WriteStructuralEvent("server_launch_failed");
        return false;
    }

    const DWORD wait_result = WaitForSingleObject(launch_mutex,
                                                  kServerLaunchMutexWaitMs);
    if (wait_result != WAIT_OBJECT_0 && wait_result != WAIT_ABANDONED) {
        CloseHandle(launch_mutex);
        WriteStructuralEvent("server_launch_pending");
        return false;
    }

    bool owns_mutex = true;
    if (WaitForSharedServerPipe(kServerPipeReconnectWaitMs)) {
        ReleaseMutex(launch_mutex);
        CloseHandle(launch_mutex);
        return true;
    }

    g_last_server_launch_attempt_ms.store(now);
    WriteStructuralEvent("server_launch_attempt");

    std::wstring command_line = QuoteCommandLineArgument(server_exe) +
                                L" --rime-dll " +
                                QuoteCommandLineArgument(rime_dll) +
                                L" --shared-dir " +
                                QuoteCommandLineArgument(shared_dir) +
                                L" --user-dir " +
                                QuoteCommandLineArgument(user_dir) +
                                L" --pipe " +
                                QuoteCommandLineArgument(kPipeName);

    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process = {};
    const DWORD flags = CREATE_NO_WINDOW;
    const BOOL launched = CreateProcessW(
        server_exe.c_str(), command_line.data(), nullptr, nullptr, FALSE, flags,
        nullptr, module_dir.c_str(), &startup, &process);
    if (!launched) {
        ReleaseMutex(launch_mutex);
        owns_mutex = false;
        CloseHandle(launch_mutex);
        WriteStructuralEvent("server_launch_failed");
        return false;
    }

    WriteStructuralEvent("server_launch_started");
    if (WaitForSharedServerPipe(kServerLaunchReadyWaitMs)) {
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        if (owns_mutex) {
            ReleaseMutex(launch_mutex);
        }
        CloseHandle(launch_mutex);
        return true;
    }

    DWORD exit_code = STILL_ACTIVE;
    if (GetExitCodeProcess(process.hProcess, &exit_code) && exit_code != STILL_ACTIVE) {
        WriteStructuralEvent("server_launch_exited");
    } else {
        WriteStructuralEvent("server_launch_pending");
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    if (owns_mutex) {
        ReleaseMutex(launch_mutex);
    }
    CloseHandle(launch_mutex);
    return false;
}

DWORD WINAPI ServerWarmupThreadProc(void*) {
    (void)RequestSharedServerLaunch();
    g_server_warmup_inflight.store(false);
    DllRelease();
    return 0;
}

void RequestSharedServerWarmupAsync() {
    bool expected = false;
    if (!g_server_warmup_inflight.compare_exchange_strong(expected, true)) {
        WriteStructuralEvent("server_warmup_pending");
        return;
    }
    DllAddRef();
    HANDLE thread = CreateThread(nullptr, 0, ServerWarmupThreadProc, nullptr, 0,
                                 nullptr);
    if (!thread) {
        g_server_warmup_inflight.store(false);
        DllRelease();
        WriteStructuralEvent("server_warmup_failed");
        return;
    }
    CloseHandle(thread);
    WriteStructuralEvent("server_warmup_started");
}

std::string JsonStringValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":\"";
    const size_t start = json.find(needle);
    if (start == std::string::npos) {
        return {};
    }
    size_t pos = start + needle.size();
    std::string value;
    while (pos < json.size()) {
        const char ch = json[pos++];
        if (ch == '"') {
            break;
        }
        if (ch == '\\' && pos < json.size()) {
            const char escaped = json[pos++];
            switch (escaped) {
                case 'n':
                    value.push_back('\n');
                    break;
                case 'r':
                    value.push_back('\r');
                    break;
                case 't':
                    value.push_back('\t');
                    break;
                case 'f':
                    value.push_back('\f');
                    break;
                case '\\':
                case '"':
                    value.push_back(escaped);
                    break;
                default:
                    break;
            }
        } else {
            value.push_back(ch);
        }
    }
    return value;
}

bool JsonBoolTrueValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":true";
    return json.find(needle) != std::string::npos;
}

bool JsonBoolValue(std::string_view json, std::string_view key, bool* value) {
    const std::string true_needle = "\"" + std::string(key) + "\":true";
    if (json.find(true_needle) != std::string::npos) {
        *value = true;
        return true;
    }
    const std::string false_needle = "\"" + std::string(key) + "\":false";
    if (json.find(false_needle) != std::string::npos) {
        *value = false;
        return true;
    }
    return false;
}

bool JsonIntValue(std::string_view json, std::string_view key, int* value) {
    const std::string needle = "\"" + std::string(key) + "\":";
    const size_t start = json.find(needle);
    if (start == std::string::npos) {
        return false;
    }
    size_t pos = start + needle.size();
    while (pos < json.size() &&
           static_cast<unsigned char>(json[pos]) <= 0x20) {
        ++pos;
    }
    size_t end = pos;
    if (end < json.size() && (json[end] == '-' || json[end] == '+')) {
        ++end;
    }
    while (end < json.size() && json[end] >= '0' && json[end] <= '9') {
        ++end;
    }
    if (end == pos) {
        return false;
    }
    size_t delimiter = end;
    while (delimiter < json.size() &&
           static_cast<unsigned char>(json[delimiter]) <= 0x20) {
        ++delimiter;
    }
    if (delimiter >= json.size() ||
        (json[delimiter] != ',' && json[delimiter] != '}')) {
        return false;
    }
    try {
        size_t parsed = 0;
        const int parsed_value = std::stoi(std::string(json.substr(pos, end - pos)),
                                           &parsed, 10);
        if (parsed != end - pos) {
            return false;
        }
        *value = parsed_value;
        return true;
    } catch (...) {
        return false;
    }
}

bool JsonRevisionValue(std::string_view json, std::string_view key,
                       unsigned long long* value) {
    if (!value) {
        return false;
    }
    const std::string needle = "\"" + std::string(key) + "\":";
    const size_t start = json.find(needle);
    if (start == std::string::npos) {
        return false;
    }
    size_t pos = start + needle.size();
    while (pos < json.size() &&
           static_cast<unsigned char>(json[pos]) <= 0x20) {
        ++pos;
    }
    size_t end = pos;
    while (end < json.size() && json[end] >= '0' && json[end] <= '9') {
        ++end;
    }
    if (end == pos) {
        return false;
    }
    try {
        size_t parsed = 0;
        const unsigned long long parsed_value =
            std::stoull(std::string(json.substr(pos, end - pos)), &parsed, 10);
        if (parsed != end - pos) {
            return false;
        }
        *value = parsed_value;
        return true;
    } catch (...) {
        return false;
    }
}

bool JsonHasArrayValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":[";
    return json.find(needle) != std::string::npos;
}

struct ImeState {
    bool present = false;
    std::wstring boot_id;
    unsigned long long revision = 0;
    std::wstring schema_id;
    bool ascii_mode = false;
    bool full_shape = false;
    std::wstring output_standard = L"hong_kong_traditional";
    yune_windows::ToolbarPosition toolbar_position;
    std::wstring toolbar_skin = L"default";
};

struct ServerResponse {
    bool ok = false;
    bool mutation_response = false;
    bool applied = false;
    bool rejected = false;
    bool transport_unknown = false;
    std::wstring outcome;
    std::wstring reason;
    ImeState state;
    std::wstring session;
    std::wstring raw_input;
    std::wstring composition_preedit;
    std::wstring commit_text;
    std::vector<std::wstring> schemas;
    std::vector<yune_windows::CandidateWindowCandidate> candidates;
};

ServerResponse ServerQueryFailure(const std::wstring& input) {
    WriteStructuralEvent("server_query_failed", static_cast<int>(input.size()));
    return {};
}

std::vector<yune_windows::CandidateWindowCandidate> JsonCandidates(std::string_view json) {
    std::vector<yune_windows::CandidateWindowCandidate> candidates;
    const size_t array_start = json.find("\"candidates\":[");
    if (array_start == std::string::npos) {
        return candidates;
    }

    size_t pos = json.find('{', array_start);
    while (pos != std::string::npos) {
        const size_t end = json.find('}', pos);
        if (end == std::string::npos) {
            break;
        }
        const size_t array_end = json.find(']', array_start);
        if (array_end != std::string::npos && end > array_end) {
            break;
        }
        const std::string_view object = json.substr(pos, end - pos + 1);
        const std::string text = JsonStringValue(object, "text");
        if (!text.empty()) {
            candidates.push_back(
                yune_windows::CandidateWindowCandidate{Widen(text),
                                                   Widen(JsonStringValue(object,
                                                                         "comment"))});
        }
        pos = json.find('{', end + 1);
    }
    return candidates;
}

ImeState JsonImeState(std::string_view json) {
    ImeState state;
    const std::string boot_id = JsonStringValue(json, "boot_id");
    const std::string schema_id = JsonStringValue(json, "schema_id");
    const std::string output_standard = JsonStringValue(json, "output_standard");
    bool ascii_mode = false;
    bool full_shape = false;
    unsigned long long revision = 0;
    if (boot_id.empty() ||
        !JsonRevisionValue(json, "revision", &revision) ||
        schema_id.empty() || output_standard.empty() ||
        !JsonBoolValue(json, "ascii_mode", &ascii_mode) ||
        !JsonBoolValue(json, "full_shape", &full_shape)) {
        return state;
    }
    state.present = true;
    state.boot_id = Widen(boot_id);
    state.revision = revision;
    state.schema_id = Widen(schema_id);
    state.ascii_mode = ascii_mode;
    state.full_shape = full_shape;
    state.output_standard = Widen(output_standard);
    bool toolbar_position_set = false;
    int toolbar_position_x = 0;
    int toolbar_position_y = 0;
    if (JsonBoolValue(json, "position_set", &toolbar_position_set)) {
        state.toolbar_position.present = toolbar_position_set;
    }
    if (JsonIntValue(json, "x", &toolbar_position_x)) {
        state.toolbar_position.x = toolbar_position_x;
    }
    if (JsonIntValue(json, "y", &toolbar_position_y)) {
        state.toolbar_position.y = toolbar_position_y;
    }
    const std::string toolbar_skin = JsonStringValue(json, "skin");
    if (!toolbar_skin.empty()) {
        state.toolbar_skin = Widen(toolbar_skin);
    }
    return state;
}

std::vector<std::wstring> JsonSchemaIds(std::string_view json) {
    std::vector<std::wstring> schemas;
    const size_t array_start = json.find("\"schemas\":[");
    if (array_start == std::string::npos) {
        return schemas;
    }

    size_t pos = json.find('{', array_start);
    while (pos != std::string::npos) {
        const size_t end = json.find('}', pos);
        if (end == std::string::npos) {
            break;
        }
        const size_t array_end = json.find(']', array_start);
        if (array_end != std::string::npos && end > array_end) {
            break;
        }
        const std::string_view object = json.substr(pos, end - pos + 1);
        const std::string schema_id = JsonStringValue(object, "schema_id");
        if (!schema_id.empty()) {
            schemas.push_back(Widen(schema_id));
        }
        pos = json.find('{', end + 1);
    }
    return schemas;
}

struct PipeExchangeResult {
    bool ok = false;
    DWORD error = ERROR_SUCCESS;
    std::string response;
};

PipeExchangeResult ExchangeOperationPipe(const std::string& request,
                                         DWORD timeout_ms);

ServerResponse QueryServer(
    const std::wstring& input, bool commit,
    RefreshStateMode mode = RefreshStateMode::AllowLaunch,
    DWORD timeout_ms = kServerQueryTimeoutMs) {
    std::string request = "input=" + Narrow(input) + "\n";
    request += commit ? "commit=1\n.\n" : "commit=0\n.\n";
    const PipeExchangeResult exchange =
        ExchangeOperationPipe(request, timeout_ms);
    if (!exchange.ok) {
        WriteStructuralEvent("server_query_call_failed", -1, -1,
                             exchange.error);
        if (mode == RefreshStateMode::AllowLaunch) {
            RequestSharedServerWarmupAsync();
        }
        return ServerQueryFailure(input);
    }

    const std::string& json = exchange.response;
    if (!JsonBoolTrueValue(json, "ready") ||
        JsonStringValue(json, "schema_id").empty() ||
        !JsonHasArrayValue(json, "candidates")) {
        WriteStructuralEvent("server_query_invalid_response");
        return ServerQueryFailure(input);
    }

    ServerResponse result;
    result.ok = true;
    result.state = JsonImeState(json);
    result.commit_text = Widen(JsonStringValue(json, "commit_text"));
    result.candidates = JsonCandidates(json);
    if (!commit && result.commit_text.empty() && !result.candidates.empty()) {
        result.commit_text = result.candidates.front().text;
    }
    return result;
}

struct PipeCall {
    std::atomic<unsigned long> refs{1};
    HANDLE done = nullptr;
    HANDLE cancel = nullptr;
    HMODULE module_hold = nullptr;
    ULONGLONG deadline = 0;
    std::string request;
    PipeExchangeResult result;
    std::atomic<bool> published{false};

    void AddRef() {
        ++refs;
    }

    void Release() {
        if (--refs == 0) {
            if (done) {
                CloseHandle(done);
            }
            if (cancel) {
                CloseHandle(cancel);
            }
            delete this;
        }
    }
};

constexpr long kMaxPipeWorkers = 4;
std::atomic<long> g_pipe_workers = 0;

DWORD RemainingPipeDeadline(ULONGLONG deadline) {
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline) {
        return 0;
    }
    const ULONGLONG remaining = deadline - now;
    return remaining > MAXDWORD ? MAXDWORD
                                : static_cast<DWORD>(remaining);
}

bool CompletePipeIoWithinDeadline(PipeCall* call, HANDLE pipe,
                                  OVERLAPPED* overlapped, BOOL started,
                                  DWORD start_error, DWORD* transferred,
                                  DWORD* error) {
    if (!call || !overlapped || !transferred || !error) {
        return false;
    }
    if (!started && start_error != ERROR_IO_PENDING) {
        *error = start_error;
        return false;
    }
    if (!started) {
        HANDLE waits[] = {overlapped->hEvent, call->cancel};
        const DWORD wait = WaitForMultipleObjects(
            ARRAYSIZE(waits), waits, FALSE,
            RemainingPipeDeadline(call->deadline));
        if (wait != WAIT_OBJECT_0) {
            (void)CancelIoEx(pipe, overlapped);
            DWORD ignored = 0;
            // The worker owns every buffer/handle touched by this OVERLAPPED.
            // Drain cancellation here even after the STA has returned.
            (void)GetOverlappedResult(pipe, overlapped, &ignored, TRUE);
            *error = wait == WAIT_TIMEOUT ? ERROR_SEM_TIMEOUT
                                         : ERROR_OPERATION_ABORTED;
            return false;
        }
    }
    if (!GetOverlappedResult(pipe, overlapped, transferred, FALSE)) {
        *error = GetLastError();
        return false;
    }
    return true;
}

PipeExchangeResult RunPipeExchangeOnWorker(PipeCall* call) {
    PipeExchangeResult result;
    if (!call) {
        result.error = ERROR_INVALID_PARAMETER;
        return result;
    }
    // Allocate every throwing buffer before acquiring raw pipe/event handles.
    std::vector<char> response(65536);

    HANDLE pipe = INVALID_HANDLE_VALUE;
    while (RemainingPipeDeadline(call->deadline) > 0 &&
           WaitForSingleObject(call->cancel, 0) != WAIT_OBJECT_0) {
        pipe = CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0,
                           nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED,
                           nullptr);
        if (pipe != INVALID_HANDLE_VALUE) {
            break;
        }
        result.error = GetLastError();
        const DWORD wait_slice =
            std::min<DWORD>(RemainingPipeDeadline(call->deadline),
                            kServerPipeMissingRetrySleepMs);
        if (result.error == ERROR_PIPE_BUSY) {
            (void)WaitNamedPipeW(kPipeName, wait_slice);
            continue;
        }
        if (result.error == ERROR_FILE_NOT_FOUND) {
            if (wait_slice == 0 ||
                WaitForSingleObject(call->cancel, wait_slice) ==
                    WAIT_OBJECT_0) {
                break;
            }
            continue;
        }
        break;
    }
    if (pipe == INVALID_HANDLE_VALUE) {
        if (WaitForSingleObject(call->cancel, 0) == WAIT_OBJECT_0) {
            result.error = ERROR_OPERATION_ABORTED;
        } else if (RemainingPipeDeadline(call->deadline) == 0) {
            result.error = ERROR_SEM_TIMEOUT;
        }
        return result;
    }

    DWORD pipe_mode = PIPE_READMODE_MESSAGE;
    if (!SetNamedPipeHandleState(pipe, &pipe_mode, nullptr, nullptr)) {
        result.error = GetLastError();
        CloseHandle(pipe);
        return result;
    }

    HANDLE io_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!io_event) {
        result.error = GetLastError();
        CloseHandle(pipe);
        return result;
    }
    OVERLAPPED overlapped = {};
    overlapped.hEvent = io_event;
    DWORD written = 0;
    const BOOL write_started = WriteFile(
        pipe, call->request.data(), static_cast<DWORD>(call->request.size()),
        nullptr, &overlapped);
    const DWORD write_error = write_started ? ERROR_SUCCESS : GetLastError();
    bool ok = CompletePipeIoWithinDeadline(
        call, pipe, &overlapped, write_started, write_error, &written,
        &result.error);
    if (ok && written != static_cast<DWORD>(call->request.size())) {
        result.error = ERROR_WRITE_FAULT;
        ok = false;
    }

    DWORD bytes_read = 0;
    if (ok) {
        ResetEvent(io_event);
        overlapped = {};
        overlapped.hEvent = io_event;
        const BOOL read_started = ReadFile(
            pipe, response.data(), static_cast<DWORD>(response.size() - 1),
            nullptr, &overlapped);
        const DWORD read_error = read_started ? ERROR_SUCCESS : GetLastError();
        ok = CompletePipeIoWithinDeadline(
            call, pipe, &overlapped, read_started, read_error, &bytes_read,
            &result.error);
        if (ok && bytes_read == 0) {
            result.error = ERROR_HANDLE_EOF;
            ok = false;
        }
    }

    CloseHandle(io_event);
    CloseHandle(pipe);
    if (ok) {
        result.ok = true;
        result.error = ERROR_SUCCESS;
        result.response.assign(response.data(), bytes_read);
    }
    return result;
}

DWORD WINAPI PipeWorkerProc(void* context) {
    auto* call = static_cast<PipeCall*>(context);
    try {
        call->result = RunPipeExchangeOnWorker(call);
    } catch (...) {
        call->result.ok = false;
        call->result.error = ERROR_NOT_ENOUGH_MEMORY;
        call->result.response.clear();
    }
    call->published.store(true, std::memory_order_release);
    (void)SetEvent(call->done);
    const HMODULE module_hold = call->module_hold;
    --g_pipe_workers;
    call->Release();
    DllRelease();
    // This is the exit-safe final release. The OS module reference prevents
    // unloading while the worker drains I/O, publishes, and tears down.
    FreeLibraryAndExitThread(module_hold, 0);
}

PipeExchangeResult ExchangeOperationPipe(const std::string& request,
                                         DWORD timeout_ms) {
    PipeExchangeResult failure;
    failure.error = ERROR_NOT_ENOUGH_MEMORY;
    auto* call = new (std::nothrow) PipeCall;
    if (!call) {
        return failure;
    }
    call->deadline = GetTickCount64() + timeout_ms;
    try {
        call->request = request;
    } catch (...) {
        call->Release();
        return failure;
    }
    call->done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!call->done) {
        failure.error = GetLastError();
        call->Release();
        return failure;
    }
    call->cancel = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!call->cancel) {
        failure.error = GetLastError();
        call->Release();
        return failure;
    }

    long active = g_pipe_workers.load();
    while (active < kMaxPipeWorkers &&
           !g_pipe_workers.compare_exchange_weak(active, active + 1)) {
    }
    if (active >= kMaxPipeWorkers) {
        failure.error = ERROR_TOO_MANY_TCBS;
        call->Release();
        return failure;
    }

    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            reinterpret_cast<LPCWSTR>(&PipeWorkerProc),
            &call->module_hold)) {
        failure.error = GetLastError();
        --g_pipe_workers;
        call->Release();
        return failure;
    }
    call->AddRef();
    DllAddRef();
    HANDLE worker =
        CreateThread(nullptr, 0, PipeWorkerProc, call, 0, nullptr);
    if (!worker) {
        failure.error = GetLastError();
        DllRelease();
        FreeLibrary(call->module_hold);
        --g_pipe_workers;
        call->Release();
        call->Release();
        return failure;
    }
    CloseHandle(worker);

    const DWORD wait = WaitForSingleObject(
        call->done, RemainingPipeDeadline(call->deadline));
    PipeExchangeResult result;
    if (wait == WAIT_OBJECT_0 &&
        call->published.load(std::memory_order_acquire)) {
        result = call->result;
    } else {
        result.error = wait == WAIT_TIMEOUT ? ERROR_SEM_TIMEOUT
                                            : GetLastError();
        (void)SetEvent(call->cancel);
    }
    call->Release();
    return result;
}

ServerResponse QueryServerOperation(
    const std::string& request,
    RefreshStateMode mode = RefreshStateMode::AllowLaunch,
    DWORD timeout_ms = kServerQueryTimeoutMs) {
    const PipeExchangeResult exchange =
        ExchangeOperationPipe(request, timeout_ms);
    if (!exchange.ok) {
        WriteStructuralEvent("server_query_call_failed", -1, -1,
                             exchange.error);
        WriteStructuralEvent("server_query_failed");
        if (mode == RefreshStateMode::AllowLaunch) {
            RequestSharedServerWarmupAsync();
        }
        ServerResponse failure;
        failure.transport_unknown = true;
        return failure;
    }

    const std::string& json = exchange.response;
    ServerResponse result;
    result.state = JsonImeState(json);
    result.outcome = Widen(JsonStringValue(json, "outcome"));
    result.reason = Widen(JsonStringValue(json, "reason"));
    bool applied = false;
    result.mutation_response = JsonBoolValue(json, "applied", &applied);
    result.applied = result.mutation_response && applied;
    if (!JsonBoolTrueValue(json, "ready")) {
        WriteStructuralEvent("server_query_invalid_response");
        result.rejected = true;
        return result;
    }
    result.ok = true;
    result.rejected = result.mutation_response && !result.applied;
    result.session = Widen(JsonStringValue(json, "session"));
    result.raw_input = Widen(JsonStringValue(json, "raw_input"));
    result.composition_preedit = Widen(JsonStringValue(json, "preedit"));
    result.commit_text = Widen(JsonStringValue(json, "commit_text"));
    result.schemas = JsonSchemaIds(json);
    result.candidates = JsonCandidates(json);
    return result;
}

class InsertTextEditSession final : public ITfEditSession {
public:
    InsertTextEditSession(ITfContext* context, std::wstring text)
        : ref_(1), context_(context), text_(std::move(text)) {
        if (context_) {
            context_->AddRef();
        }
        DllAddRef();
    }

    ~InsertTextEditSession() {
        if (context_) {
            context_->Release();
        }
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_ITfEditSession)) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        const HRESULT selection_hr = SetSelectionText(cookie, E_FAIL);
        if (SUCCEEDED(selection_hr)) {
            return selection_hr;
        }

        ITfInsertAtSelection* insert = nullptr;
        const HRESULT query_hr =
            context_ ? context_->QueryInterface(IID_ITfInsertAtSelection,
                                                reinterpret_cast<void**>(&insert))
                     : E_FAIL;
        HRESULT insert_hr = FAILED(query_hr) ? query_hr : E_NOINTERFACE;
        if (SUCCEEDED(query_hr) && insert) {
            insert_hr = insert->InsertTextAtSelection(
                cookie, TF_IAS_NOQUERY, text_.c_str(),
                static_cast<LONG>(text_.size()), nullptr);
            insert->Release();
            insert = nullptr;
            if (SUCCEEDED(insert_hr)) {
                return insert_hr;
            }
        }
        if (insert) {
            insert->Release();
        }
        return FAILED(insert_hr) ? insert_hr : selection_hr;
    }

private:
    HRESULT SetSelectionText(TfEditCookie cookie, HRESULT prior_hr) {
        if (!context_) {
            return FAILED(prior_hr) ? prior_hr : E_FAIL;
        }

        TF_SELECTION selection = {};
        ULONG fetched = 0;
        const HRESULT selection_hr =
            context_->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection,
                                   &fetched);
        if (FAILED(selection_hr) || fetched == 0 || !selection.range) {
            return FAILED(selection_hr) ? selection_hr
                                        : (FAILED(prior_hr) ? prior_hr
                                                            : E_NOINTERFACE);
        }

        const HRESULT set_hr =
            selection.range->SetText(cookie, 0, text_.c_str(),
                                     static_cast<LONG>(text_.size()));
        if (SUCCEEDED(set_hr)) {
            if (SUCCEEDED(selection.range->Collapse(cookie, TF_ANCHOR_END))) {
                context_->SetSelection(cookie, 1, &selection);
            }
        }
        selection.range->Release();
        return set_hr;
    }

    std::atomic<long> ref_;
    ITfContext* context_;
    std::wstring text_;
};

struct CandidateAnchorResult {
    RECT anchor = {};
    HWND owner = nullptr;
    UINT dpi = 96;
    bool has_anchor = false;
    bool has_text_ext = false;
    bool has_screen_ext = false;
};

class CandidateAnchorEditSession final : public ITfEditSession {
public:
    CandidateAnchorEditSession(ITfContext* context, CandidateAnchorResult* result)
        : ref_(1), context_(context), result_(result) {
        if (context_) {
            context_->AddRef();
        }
        DllAddRef();
    }

    ~CandidateAnchorEditSession() {
        if (context_) {
            context_->Release();
        }
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_ITfEditSession)) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        if (!context_ || !result_) {
            return E_FAIL;
        }

        ITfContextView* view = nullptr;
        const HRESULT view_hr = context_->GetActiveView(&view);
        if (FAILED(view_hr) || !view) {
            return FAILED(view_hr) ? view_hr : E_FAIL;
        }

        HWND owner = nullptr;
        if (SUCCEEDED(view->GetWnd(&owner)) && owner) {
            result_->owner = owner;
            result_->dpi = GetDpiForWindow(owner);
        }

        TF_SELECTION selection = {};
        ULONG fetched = 0;
        const HRESULT selection_hr =
            context_->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection,
                                   &fetched);
        if (SUCCEEDED(selection_hr) && fetched > 0 && selection.range) {
            RECT text_ext = {};
            BOOL clipped = FALSE;
            if (SUCCEEDED(view->GetTextExt(cookie, selection.range, &text_ext,
                                           &clipped)) &&
                clipped == FALSE &&
                text_ext.right > text_ext.left &&
                text_ext.bottom > text_ext.top) {
                result_->anchor = text_ext;
                result_->has_anchor = true;
                result_->has_text_ext = true;
            }
            selection.range->Release();
        }

        if (!result_->has_text_ext) {
            RECT screen_ext = {};
            if (SUCCEEDED(view->GetScreenExt(&screen_ext)) &&
                screen_ext.right > screen_ext.left &&
                screen_ext.bottom > screen_ext.top) {
                result_->anchor = screen_ext;
                result_->anchor.right = result_->anchor.left + 24;
                result_->anchor.bottom = result_->anchor.top + 24;
                result_->has_anchor = true;
                result_->has_screen_ext = true;
            }
        }

        view->Release();
        return result_->has_text_ext || result_->has_screen_ext ? S_OK : S_FALSE;
    }

private:
    std::atomic<long> ref_;
    ITfContext* context_;
    CandidateAnchorResult* result_;
};

class InlineCompositionEditSession final : public ITfEditSession {
public:
    InlineCompositionEditSession(ITfContext* context, ITfCompositionSink* sink,
                                 ITfComposition** composition,
                                 ITfRange** range,
                                 std::wstring commit_text,
                                 std::wstring preedit)
        : ref_(1),
          context_(context),
          sink_(sink),
          composition_(composition),
          range_(range),
          commit_text_(std::move(commit_text)),
          preedit_(std::move(preedit)) {
        if (context_) {
            context_->AddRef();
        }
        if (sink_) {
            sink_->AddRef();
        }
        DllAddRef();
    }

    ~InlineCompositionEditSession() {
        if (context_) {
            context_->Release();
        }
        if (sink_) {
            sink_->Release();
        }
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_ITfEditSession)) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        if (!context_ || !composition_ || !range_) {
            return E_FAIL;
        }

        ITfRange* working_range = nullptr;
        if (*range_) {
            working_range = *range_;
            working_range->AddRef();
        }

        EndCurrentComposition(cookie);

        const std::wstring replacement = commit_text_ + preedit_;
        HRESULT replace_hr = S_OK;
        if (working_range) {
            replace_hr = working_range->SetText(
                cookie, 0, replacement.c_str(),
                static_cast<LONG>(replacement.size()));
        } else if (!replacement.empty()) {
            replace_hr = InsertAtSelection(cookie, replacement, &working_range);
        }

        if (FAILED(replace_hr)) {
            if (working_range) {
                working_range->Release();
            }
            return replace_hr;
        }

        if (preedit_.empty()) {
            SetSelectionToEnd(cookie, working_range);
            ReplaceRange(nullptr);
            if (working_range) {
                working_range->Release();
            }
            return S_OK;
        }

        if (!working_range) {
            return E_FAIL;
        }

        ITfRange* preedit_range = nullptr;
        HRESULT range_hr = working_range->Clone(&preedit_range);
        if (SUCCEEDED(range_hr) && preedit_range) {
            range_hr = preedit_range->Collapse(cookie, TF_ANCHOR_END);
        }
        if (SUCCEEDED(range_hr) && preedit_range) {
            LONG shifted = 0;
            range_hr = preedit_range->ShiftStart(
                cookie, -static_cast<LONG>(preedit_.size()), &shifted, nullptr);
        }
        if (FAILED(range_hr) || !preedit_range) {
            if (preedit_range) {
                preedit_range->Release();
            }
            working_range->Release();
            return FAILED(range_hr) ? range_hr : E_FAIL;
        }

        ITfContextComposition* composition_context = nullptr;
        HRESULT query_hr = context_->QueryInterface(
            IID_ITfContextComposition,
            reinterpret_cast<void**>(&composition_context));
        if (FAILED(query_hr) || !composition_context) {
            preedit_range->Release();
            working_range->Release();
            return FAILED(query_hr) ? query_hr : E_NOINTERFACE;
        }

        ITfComposition* new_composition = nullptr;
        HRESULT start_hr = composition_context->StartComposition(
            cookie, preedit_range, sink_, &new_composition);
        composition_context->Release();
        if (FAILED(start_hr) || !new_composition) {
            preedit_range->Release();
            working_range->Release();
            return FAILED(start_hr) ? start_hr : E_FAIL;
        }

        ReplaceComposition(new_composition);
        ReplaceRange(preedit_range);
        SetSelectionToEnd(cookie, preedit_range);
        working_range->Release();
        return S_OK;
    }

private:
    HRESULT InsertAtSelection(TfEditCookie cookie,
                              const std::wstring& text,
                              ITfRange** range) {
        ITfInsertAtSelection* insert = nullptr;
        const HRESULT query_hr =
            context_->QueryInterface(IID_ITfInsertAtSelection,
                                     reinterpret_cast<void**>(&insert));
        if (FAILED(query_hr) || !insert) {
            return FAILED(query_hr) ? query_hr : E_NOINTERFACE;
        }
        const HRESULT insert_hr = insert->InsertTextAtSelection(
            cookie, 0, text.c_str(), static_cast<LONG>(text.size()), range);
        insert->Release();
        return insert_hr;
    }

    void EndCurrentComposition(TfEditCookie cookie) {
        if (*composition_) {
            ITfComposition* current = *composition_;
            *composition_ = nullptr;
            (void)current->EndComposition(cookie);
            current->Release();
        }
    }

    void ReplaceComposition(ITfComposition* value) {
        if (*composition_) {
            (*composition_)->Release();
        }
        *composition_ = value;
    }

    void ReplaceRange(ITfRange* value) {
        if (*range_) {
            (*range_)->Release();
        }
        *range_ = value;
    }

    void SetSelectionToEnd(TfEditCookie cookie, ITfRange* range) {
        if (!range) {
            return;
        }
        ITfRange* selection_range = nullptr;
        if (FAILED(range->Clone(&selection_range)) || !selection_range) {
            return;
        }
        if (SUCCEEDED(selection_range->Collapse(cookie, TF_ANCHOR_END))) {
            TF_SELECTION selection = {};
            selection.range = selection_range;
            selection.style.ase = TF_AE_NONE;
            selection.style.fInterimChar = FALSE;
            (void)context_->SetSelection(cookie, 1, &selection);
        }
        selection_range->Release();
    }

    std::atomic<long> ref_;
    ITfContext* context_;
    ITfCompositionSink* sink_;
    ITfComposition** composition_;
    ITfRange** range_;
    std::wstring commit_text_;
    std::wstring preedit_;
};

class TextService final : public ITfTextInputProcessorEx,
                          public ITfKeyEventSink,
                          public ITfCompositionSink {
public:
    TextService() : ref_(1) {
        language_bar_.SetClickHandler(&TextService::LanguageBarClickThunk, this);
        language_bar_.SetPositionChangedHandler(
            &TextService::LanguageBarPositionChangedThunk, this);
        DllAddRef();
    }

    ~TextService() {
        Deactivate();
        const HWND dispatcher = focused_service_window_.exchange(nullptr);
        focused_service_window_thread_id_.store(0);
        if (dispatcher) {
            SetWindowLongPtrW(dispatcher, GWLP_USERDATA, 0);
            if (GetWindowThreadProcessId(dispatcher, nullptr) ==
                GetCurrentThreadId()) {
                DestroyWindow(dispatcher);
            } else {
                (void)PostMessageW(dispatcher, WM_CLOSE, 0, 0);
            }
        }
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) ||
            IsEqualIID(iid, IID_ITfTextInputProcessor)) {
            *object = static_cast<ITfTextInputProcessor*>(this);
        } else if (IsEqualIID(iid, IID_ITfTextInputProcessorEx)) {
            *object = static_cast<ITfTextInputProcessorEx*>(this);
        } else if (IsEqualIID(iid, IID_ITfKeyEventSink)) {
            *object = static_cast<ITfKeyEventSink*>(this);
        } else if (IsEqualIID(iid, IID_ITfCompositionSink)) {
            *object = static_cast<ITfCompositionSink*>(this);
        }
        if (*object) {
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) override {
        return ActivateEx(thread_mgr, client_id, 0);
    }

    STDMETHODIMP ActivateEx(ITfThreadMgr* thread_mgr, TfClientId client_id,
                            DWORD) override {
        if (thread_mgr_) {
            Deactivate();
        }
        if (!thread_mgr) {
            return E_INVALIDARG;
        }

        ITfKeystrokeMgr* keystroke_mgr = nullptr;
        const HRESULT query_hr =
            thread_mgr->QueryInterface(IID_ITfKeystrokeMgr,
                                       reinterpret_cast<void**>(&keystroke_mgr));
        if (FAILED(query_hr) || !keystroke_mgr) {
            return FAILED(query_hr) ? query_hr : E_NOINTERFACE;
        }
        const HRESULT hr =
            keystroke_mgr->AdviseKeyEventSink(client_id, this, TRUE);
        if (SUCCEEDED(hr)) {
            (void)keystroke_mgr->PreserveKey(
                client_id, kSchemaCyclePreservedKeyGuid,
                &kSchemaCyclePreservedKey, L"Yune Windows schema cycle",
                static_cast<ULONG>(wcslen(L"Yune Windows schema cycle")));
            (void)keystroke_mgr->PreserveKey(
                client_id, kFullShapePreservedKeyGuid,
                &kFullShapePreservedKey, L"Yune Windows full shape",
                static_cast<ULONG>(wcslen(L"Yune Windows full shape")));
        }
        keystroke_mgr->Release();
        if (FAILED(hr)) {
            return hr;
        }

        thread_mgr_ = thread_mgr;
        thread_mgr_->AddRef();
        client_id_ = client_id;
        RefreshStateFromServer(nullptr, RefreshStateMode::ExistingServerOnly);
        RequestSharedServerWarmupAsync();
        WriteStructuralEvent("profile_activate");
        return S_OK;
    }

    STDMETHODIMP Deactivate() override {
        const bool was_active = thread_mgr_ != nullptr ||
                                client_id_ != TF_CLIENTID_NULL ||
                                IsComposing();
        if (was_active) {
            WriteStructuralEvent("profile_deactivate",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
        }
        ClearCompositionState(true);
        if (thread_mgr_) {
            ITfKeystrokeMgr* keystroke_mgr = nullptr;
            if (SUCCEEDED(thread_mgr_->QueryInterface(
                    IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke_mgr)))) {
                (void)keystroke_mgr->UnpreserveKey(kSchemaCyclePreservedKeyGuid,
                                                   &kSchemaCyclePreservedKey);
                (void)keystroke_mgr->UnpreserveKey(kFullShapePreservedKeyGuid,
                                                   &kFullShapePreservedKey);
                keystroke_mgr->UnadviseKeyEventSink(client_id_);
                keystroke_mgr->Release();
            }
            thread_mgr_->Release();
            thread_mgr_ = nullptr;
        }
        client_id_ = TF_CLIENTID_NULL;
        focused_ = false;
        CancelPendingAsciiToggle("cancelled_deactivation");
        DeactivateFocusedTextService(this);
        ClearToolbarAnchorCache();
        ClearShiftState();
        language_bar_.Hide();
        return S_OK;
    }

    STDMETHODIMP OnSetFocus(BOOL focused) override {
        if (!focused) {
            focused_ = false;
            acknowledged_state_generation_ = 0;
            CancelPendingAsciiToggle("cancelled_focus_loss");
            DeactivateFocusedTextService(this);
            ClearToolbarAnchorCache();
            ClearShiftState();
            WriteStructuralEvent("focus_lost", static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            ClearCompositionState(true);
            language_bar_.Hide();
        } else {
            acknowledged_state_generation_ = 0;
            focused_ = ActivateFocusedTextService(this);
            if (!focused_) {
                ClearToolbarAnchorCache();
                language_bar_.Hide();
                return S_OK;
            }
            RecordFocusGained();
            RefreshStateFromServer(nullptr, RefreshStateMode::ExistingServerOnly);
            RequestSharedServerWarmupAsync();
        }
        return S_OK;
    }

    STDMETHODIMP OnTestKeyDown(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        const bool shift_pressed = IsShiftPressed();
        *eaten = ShouldHandleKeyDown(key, shift_pressed);
        return S_OK;
    }

    STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM key, LPARAM lparam, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        *eaten = FALSE;
        if (IsShiftKey(key)) {
            if ((lparam & kKeyWasDownMask) == 0) {
                shift_down_ = true;
                const bool modified = IsShortcutModifierDown();
                const bool mouse_or_capture = IsMouseButtonDown();
                shift_consumed_ = modified || mouse_or_capture;
                shift_rejection_reason_ =
                    modified
                        ? ShiftRejectionReason::Modified
                        : (mouse_or_capture
                               ? ShiftRejectionReason::MouseOrCapture
                               : ShiftRejectionReason::None);
                const unsigned long current_generation =
                    static_cast<unsigned long>(
                        focused_service_generation_.load());
                const bool hook_authoritative =
                    g_shift_hook_active_generation.load(
                        std::memory_order_acquire) == current_generation;
                if (!hook_authoritative) {
                    ClearMouseButtonTransitionBits();
                }
                // The hook can post key-up before a busy host delivers the TSF
                // key-down. Correlate from bounded history rather than relying
                // on the transient "currently down" snapshot.
                const unsigned long long hook_snapshot =
                    FindShiftHookSnapshot(
                        current_generation,
                        last_hook_shift_token_adopted_,
                        static_cast<DWORD>(GetMessageTime()));
                const unsigned long hook_token =
                    ShiftSnapshotToken(hook_snapshot);
                const unsigned long hook_generation =
                    ShiftSnapshotGeneration(hook_snapshot);
                if (hook_token != 0 && hook_generation == current_generation) {
                    shift_token_ = hook_token;
                    shift_token_generation_ = hook_generation;
                    last_hook_shift_token_adopted_ = hook_token;
                } else {
                    if (hook_authoritative) {
                        // A healthy hook is authoritative when the TSF message
                        // cannot be correlated exactly; its posted token will
                        // settle the physical event without a second identity.
                        shift_token_ = 0;
                        shift_token_generation_ = 0;
                    } else {
                        shift_token_ = NextNonzeroSequence(&g_shift_sequence);
                        shift_token_generation_ = current_generation;
                    }
                }
            } else if (shift_down_) {
                shift_consumed_ = true;
                if (shift_rejection_reason_ == ShiftRejectionReason::None) {
                    shift_rejection_reason_ = ShiftRejectionReason::Repeat;
                }
            }
            return S_OK;
        }
        if (shift_down_) {
            shift_consumed_ = true;
            if (shift_rejection_reason_ == ShiftRejectionReason::None) {
                shift_rejection_reason_ =
                    IsShortcutModifierKey(key) || IsShortcutModifierDown()
                        ? ShiftRejectionReason::Modified
                        : ShiftRejectionReason::Consumed;
            }
        }
        const bool shift_pressed = IsShiftPressed();
        if (!ShouldHandleKeyDown(key, shift_pressed)) {
            return S_OK;
        }
        if (!shift_pressed &&
            ((key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z'))) {
            *eaten = TRUE;
            std::wstring key_text(1, LowerAscii(key));
            if (!EnsureComposeSession(context)) {
                (void)CommitRawFallback(context, key_text);
                return S_OK;
            }
            std::string payload = "op=compose-key\nsession=";
            payload += Narrow(compose_session_);
            payload += "\nkey=";
            payload += Narrow(key_text);
            payload += "\nmask=0\n.\n";
            ServerResponse response = QueryComposeOperation(payload, context);
            if (!response.ok) {
                (void)CommitRawFallback(context, buffer_ + key_text);
                return S_OK;
            }
            if (!ApplyComposeResponse(context, response)) {
                // The server answered but the inline composition could not be
                // applied in this host (edit session / ITfComposition failed).
                // Don't leave the key eaten with no output: fall back to the raw
                // input (which ApplyComposeResponse set from the server) so typing
                // still produces text instead of silently disappearing.
                (void)CommitRawFallback(context, buffer_);
                return S_OK;
            }
            const int buffer_length = static_cast<int>(buffer_.size());
            const int candidate_count = static_cast<int>(last_candidates_.size());
            WriteStructuralEvent("key_down", buffer_length, candidate_count);
            return S_OK;
        }
        if (key == VK_BACK) {
            if (IsComposing()) {
                *eaten = TRUE;
                if (compose_session_.empty()) {
                    ClearCompositionState(false);
                    return S_OK;
                }
                ServerResponse response =
                    QueryComposeOperation(ComposePayload("compose-back"), context);
                if (!response.ok) {
                    ClearCompositionState(false);
                    return S_OK;
                }
                (void)ApplyComposeResponse(context, response);
                WriteStructuralEvent("key_backspace",
                                     static_cast<int>(buffer_.size()),
                                     static_cast<int>(last_candidates_.size()));
            } else {
                candidate_window_.Hide();
            }
            return S_OK;
        }
        if (key == VK_ESCAPE) {
            WriteStructuralEvent("composition_cancel",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            if (!compose_session_.empty()) {
                ServerResponse response = QueryComposeOperation(
                    ComposePayload("compose-cancel"), context);
                if (response.ok) {
                    (void)ApplyComposeResponse(context, response);
                }
            }
            ClearCompositionState(true);
            *eaten = TRUE;
            return S_OK;
        }
        if (!shift_pressed &&
            (key == VK_NEXT || key == VK_PRIOR || key == VK_OEM_MINUS ||
             key == VK_OEM_PLUS) && IsComposing()) {
            *eaten = TRUE;
            const int page_delta =
                (key == VK_NEXT || key == VK_OEM_PLUS) ? 1 : -1;
            PageComposition(context, page_delta);
            return S_OK;
        }
        if (!shift_pressed && key >= L'1' && key <= L'9' && IsComposing()) {
            *eaten = TRUE;
            const int page_relative_index = static_cast<int>(key - L'1');
            const int visible_index =
                yune_windows::CandidatePageStartIndex(candidate_page_index_,
                                                      kCandidatePageSize) +
                page_relative_index;
            if (!compose_session_.empty() && visible_index >= 0 &&
                visible_index < static_cast<int>(last_candidates_.size())) {
                WriteStructuralEvent("commit_request",
                                     static_cast<int>(buffer_.size()),
                                     static_cast<int>(last_candidates_.size()));
                std::string payload = "op=compose-select\nsession=";
                payload += Narrow(compose_session_);
                payload += "\nindex=";
                payload += std::to_string(page_relative_index);
                payload += "\n.\n";
                ServerResponse response = QueryComposeOperation(payload, context);
                if (!response.ok) {
                    ClearCompositionState(false);
                    return S_OK;
                }
                (void)ApplyComposeResponse(context, response);
            }
            return S_OK;
        }
        if (IsPunctuationKey(key, shift_pressed)) {
            const bool was_composing = IsComposing();
            if (CommitCompositionForPunctuation(context, key, shift_pressed) ||
                was_composing) {
                *eaten = TRUE;
            }
            return S_OK;
        }
        if (key == VK_RETURN && IsComposing()) {
            *eaten = TRUE;
            (void)CommitRawBuffer(context);
            return S_OK;
        }
        if (key == VK_SPACE && IsComposing()) {
            *eaten = TRUE;
            ServerResponse response =
                QueryComposeOperation(ComposePayload("compose-commit"), context);
            if (!response.ok) {
                ClearCompositionState(false);
                return S_OK;
            }
            WriteStructuralEvent("commit_request",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            (void)ApplyComposeResponse(context, response);
        }
        return S_OK;
    }

    STDMETHODIMP OnTestKeyUp(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        (void)key;
        *eaten = FALSE;
        return S_OK;
    }

    STDMETHODIMP OnKeyUp(ITfContext* context, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        *eaten = FALSE;
        if (IsShiftKey(key)) {
            const bool mouse_or_capture = MouseButtonTransitionOrDown() ||
                                          IsMouseButtonDown();
            const bool modified = IsShortcutModifierDown();
            const bool hook_consumed =
                ShiftHookTokenWasConsumed(
                    static_cast<unsigned long>(shift_token_),
                    static_cast<unsigned long>(shift_token_generation_));
            if (shift_down_ && (mouse_or_capture || modified || hook_consumed)) {
                shift_consumed_ = true;
                if (shift_rejection_reason_ == ShiftRejectionReason::None) {
                    shift_rejection_reason_ =
                        mouse_or_capture
                            ? ShiftRejectionReason::MouseOrCapture
                            : (modified ? ShiftRejectionReason::Modified
                                        : ShiftRejectionReason::Consumed);
                }
            }
            if (shift_down_ && !shift_consumed_ &&
                !modified && !mouse_or_capture &&
                !IsShortcutModifierDown() && !IsMouseButtonDown()) {
                HandleDeferredLoneShiftToggle(
                    shift_token_, shift_token_generation_, ShiftDetector::Sink,
                    context);
            } else if (shift_down_) {
                if (shift_rejection_reason_ == ShiftRejectionReason::None) {
                    shift_rejection_reason_ = ShiftRejectionReason::Consumed;
                }
                const unsigned long long generation =
                    shift_token_generation_ != 0
                        ? shift_token_generation_
                        : focused_service_generation_.load();
                SettleRejectedShiftToken(
                    shift_token_, generation, ShiftDetector::Sink,
                    ShiftRejectionDisposition(shift_rejection_reason_));
            }
            ClearShiftState();
        }
        return S_OK;
    }

    STDMETHODIMP OnPreservedKey(ITfContext* context, REFGUID guid, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        if (IsEqualGUID(guid, kFullShapePreservedKeyGuid)) {
            *eaten = TRUE;
            CancelLoneShiftToggle();
            ToggleBoolState("full_shape", context);
            return S_OK;
        }
        if (IsEqualGUID(guid, kSchemaCyclePreservedKeyGuid)) {
            *eaten = TRUE;
            CancelLoneShiftToggle();
            CycleSchema(context);
            return S_OK;
        }
        *eaten = FALSE;
        return S_OK;
    }

    STDMETHODIMP OnCompositionTerminated(TfEditCookie, ITfComposition*) override {
        ReleaseInlineCompositionRefs();
        return S_OK;
    }

    void HandleDeferredLoneShiftToggle(unsigned long long token,
                                       unsigned long long generation,
                                       ShiftDetector detector,
                                       ITfContext* context = nullptr) {
        using yune_windows::reliability::ShiftClaimDisposition;
        const ShiftClaimDisposition disposition =
            shift_token_arbiter_.Claim(token, generation);
        switch (disposition) {
            case ShiftClaimDisposition::InvalidToken:
                RecordShiftDisposition(token, generation, detector,
                                       "rejected_invalid_token");
                return;
            case ShiftClaimDisposition::StaleGeneration:
                RecordShiftDisposition(token, generation, detector,
                                       "rejected_stale_generation");
                return;
            case ShiftClaimDisposition::Duplicate:
                RecordShiftDisposition(token, generation, detector,
                                       "rejected_duplicate");
                return;
            case ShiftClaimDisposition::ExpiredToken:
                RecordShiftDisposition(token, generation, detector,
                                       "rejected_capacity_expired");
                return;
            case ShiftClaimDisposition::Accepted:
                break;
        }
        if (pending_ascii_intent_.active() &&
            pending_ascii_deadline_ms_ != 0 &&
            GetTickCount64() >= pending_ascii_deadline_ms_) {
            CancelPendingAsciiToggle("deadline_expired");
            RecordShiftDisposition(token, generation, detector,
                                   "rejected_expired_intent");
            return;
        }
        PerformLoneShiftToggle(token, generation, detector, context);
    }

    void RecordShiftDisposition(unsigned long long token,
                                unsigned long long generation,
                                ShiftDetector detector,
                                const char* disposition) {
        std::ostringstream attributes;
        attributes << "toggle_token=" << token
                   << " generation=" << generation
                   << " detector=" << ShiftDetectorName(detector)
                   << " disposition="
                   << (disposition ? disposition : "unknown")
                   << " state_revision=" << state_.revision;
        const std::string fields = attributes.str();
        WriteStructuralEvent("shift_disposition", -1, -1, ERROR_SUCCESS,
                             fields);
    }

    void SettleRejectedShiftToken(unsigned long long token,
                                  unsigned long long generation,
                                  ShiftDetector detector,
                                  const char* disposition) {
        if (token != 0 && generation != 0) {
            (void)shift_token_arbiter_.Claim(token, generation);
        }
        RecordShiftDisposition(token, generation, detector, disposition);
    }

    // The TSF sink and low-level-hook fallback carry the same physical token
    // when both observe a press. The first delivery claims it; token and
    // generation identity replace the old 250 ms time suppression window.
    void PerformLoneShiftToggle(unsigned long long token,
                                unsigned long long generation,
                                ShiftDetector detector,
                                ITfContext* context) {
        if (!IsCurrentFocusedTextService(
                this, generation) ||
            !CachedToolbarOwnerMatchesForeground()) {
            RecordShiftDisposition(token, generation, detector,
                "rejected_background_or_noncurrent");
            return;
        }
        RecordShiftDisposition(token, generation, detector, "accepted");
        // A hook fallback can reach the dispatcher before the TSF sink's
        // key-up report. Preserve matching sink correlation state so that
        // report can still receive its own duplicate disposition. The sink
        // path clears its state after OnTestKeyUp/OnKeyUp completes.
        if (detector == ShiftDetector::Sink) {
            ClearShiftState();
        }
        QueueAsciiToggle(token, detector, context);
    }

    void HideLanguageBarForSupersededFocus() {
        language_bar_.HideForSupersededFocus();
    }

    bool PrepareFocusedServiceActivation(unsigned long long generation);
    bool QueueSupersededFocus(unsigned long long generation);
    unsigned long long FocusedServiceGeneration() const {
        return focused_service_generation_.load();
    }
    HWND FocusedServiceWindow() const {
        return focused_service_window_.load();
    }
    DWORD FocusedServiceWindowThreadId() const {
        return focused_service_window_thread_id_.load();
    }
    void HandleSupersededFocus(HWND dispatcher,
                               unsigned long long generation);
    void HandleFocusedServiceWatchdog(HWND dispatcher) {
        if (dispatcher != focused_service_window_.load() ||
            !IsCurrentFocusedTextService(
                this, focused_service_generation_.load())) {
            CancelPendingAsciiToggle("cancelled_noncurrent_watchdog");
            language_bar_.Hide();
            return;
        }
        (void)RefreshShiftHookForFocusedService(this);
        if (!StateAcknowledgedForCurrentGeneration()) {
            RefreshStateFromServer(nullptr,
                                   RefreshStateMode::ExistingServerOnly);
            if (!StateAcknowledgedForCurrentGeneration()) {
                if (pending_ascii_intent_.active()) {
                    DrivePendingAsciiToggle(nullptr);
                }
                return;
            }
        }
        if (pending_ascii_intent_.active()) {
            DrivePendingAsciiToggle(nullptr);
            if (!StateAcknowledgedForCurrentGeneration() ||
                pending_ascii_intent_.active()) {
                return;
            }
        }
        if (!CachedToolbarOwnerMatchesForeground() ||
            last_toolbar_visibility_reason_ != "eligible_show" ||
            !language_bar_.IsVisible()) {
            UpdateLanguageBar(nullptr);
        }
    }
    bool DetachFocusedServiceWindow(HWND dispatcher,
                                    unsigned long* pending_references);
    void RetainOrphanedFocusReference() {
        ++orphaned_focus_references_;
    }
    unsigned long TakeOrphanedFocusReferences() {
        return orphaned_focus_references_.exchange(0);
    }

private:
    static void LanguageBarClickThunk(yune_windows::LanguageBarSegment segment,
                                      void* context) {
        auto* service = static_cast<TextService*>(context);
        if (service) {
            service->HandleLanguageBarClick(segment);
        }
    }

    static void LanguageBarPositionChangedThunk(int x, int y, void* context) {
        auto* service = static_cast<TextService*>(context);
        if (service) {
            service->HandleLanguageBarPositionChanged(x, y);
        }
    }

    ServerResponse QueryInput(const std::wstring& input, bool commit) {
        ServerResponse response = QueryServer(
            input, commit, RefreshStateMode::ExistingServerOnly,
            kServerKeyPathQueryTimeoutMs);
        if (!response.ok) {
            RequestSharedServerWarmupAsync();
        }
        ReconcileState(response, nullptr);
        return response;
    }

    ServerResponse QueryOperation(
        const std::string& payload,
        ITfContext* context,
        RefreshStateMode mode = RefreshStateMode::AllowLaunch,
        DWORD timeout_ms = kServerQueryTimeoutMs) {
        ServerResponse response = QueryServerOperation(payload, mode, timeout_ms);
        ReconcileState(response, context);
        return response;
    }

    ServerResponse QueryComposeOperation(const std::string& payload,
                                         ITfContext* context) {
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (!response.ok) {
            RequestSharedServerWarmupAsync();
        }
        return response;
    }

    bool IsComposing() const {
        return !compose_session_.empty() || !buffer_.empty() ||
               composition_ != nullptr || !last_candidates_.empty();
    }

    bool EnsureComposeSession(ITfContext* context) {
        if (!compose_session_.empty()) {
            return true;
        }
        ServerResponse response =
            QueryComposeOperation("op=compose-begin\n.\n", context);
        if (!response.ok || response.session.empty()) {
            return false;
        }
        compose_session_ = response.session;
        buffer_ = response.raw_input;
        composition_preedit_ = response.composition_preedit;
        return true;
    }

    std::string ComposePayload(const char* op) const {
        std::string payload = "op=";
        payload += op;
        payload += "\nsession=";
        payload += Narrow(compose_session_);
        payload += "\n.\n";
        return payload;
    }

    bool ApplyComposeResponse(ITfContext* context,
                              const ServerResponse& response,
                              bool reset_page = true) {
        if (!response.ok) {
            return false;
        }
        if (!response.session.empty()) {
            compose_session_ = response.session;
        }
        buffer_ = response.raw_input;
        composition_preedit_ = response.composition_preedit;
        last_candidates_ = response.candidates;
        if (reset_page) {
            candidate_page_index_ = 0;
        }
        candidate_.clear();
        const int page_start = yune_windows::CandidatePageStartIndex(
            candidate_page_index_, kCandidatePageSize);
        if (page_start >= 0 &&
            page_start < static_cast<int>(last_candidates_.size())) {
            candidate_ = last_candidates_[static_cast<size_t>(page_start)].text;
        }

        if (!ApplyInlineComposition(context, response.commit_text,
                                    composition_preedit_)) {
            return false;
        }

        const bool still_composing =
            !buffer_.empty() || !composition_preedit_.empty() ||
            !last_candidates_.empty();
        if (!still_composing) {
            EndComposeSession(true);
            ClearCompositionState(false, false);
            return true;
        }

        const int buffer_length = static_cast<int>(buffer_.size());
        const int candidate_count = static_cast<int>(last_candidates_.size());
        if (ShowCandidates(context, last_candidates_)) {
            WriteStructuralEvent("candidate_update", buffer_length,
                                 candidate_count);
        }
        return true;
    }

    void ReconcileState(const ServerResponse& response, ITfContext* context) {
        if (!response.state.present) {
            return;
        }
        const unsigned long long generation =
            focused_service_generation_.load();
        if (!focused_ ||
            !IsCurrentFocusedTextService(this, generation)) {
            WriteStructuralEvent("server_state_noncurrent_reply");
            return;
        }
        if (state_.present && !state_.boot_id.empty() &&
            response.state.boot_id == state_.boot_id &&
            response.state.revision < state_.revision) {
            WriteStructuralEvent("server_state_stale_reply");
            return;
        }
        state_ = response.state;
        acknowledged_state_generation_ = generation;
        UpdateInputModeCompartment();
        UpdateLanguageBar(context);
    }

    void RefreshStateFromServer(
        ITfContext* context,
        RefreshStateMode mode = RefreshStateMode::AllowLaunch) {
        acknowledged_state_generation_ = 0;
        const DWORD timeout_ms = mode == RefreshStateMode::ExistingServerOnly
                                     ? kServerFocusRefreshTimeoutMs
                                     : kServerQueryTimeoutMs;
        (void)QueryOperation("op=get-state\n.\n", context, mode, timeout_ms);
    }

    void UpdateInputModeCompartment() {
        if (!state_.present || !thread_mgr_ || client_id_ == TF_CLIENTID_NULL) {
            return;
        }

        ITfCompartmentMgr* compartment_mgr = nullptr;
        if (FAILED(thread_mgr_->QueryInterface(
                IID_ITfCompartmentMgr,
                reinterpret_cast<void**>(&compartment_mgr))) ||
            !compartment_mgr) {
            return;
        }
        ITfCompartment* compartment = nullptr;
        if (SUCCEEDED(compartment_mgr->GetCompartment(
                GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &compartment)) &&
            compartment) {
            VARIANT value = {};
            value.vt = VT_I4;
            value.lVal = state_.ascii_mode ? 0 : 1;
            (void)compartment->SetValue(client_id_, &value);
            compartment->Release();
        }
        compartment_mgr->Release();
    }

    void RecordFocusGained() {
        bool context_available = false;
        const char* context_source = "none";
        if (thread_mgr_) {
            ITfDocumentMgr* document_mgr = nullptr;
            if (SUCCEEDED(thread_mgr_->GetFocus(&document_mgr)) &&
                document_mgr) {
                ITfContext* context = nullptr;
                if (SUCCEEDED(document_mgr->GetTop(&context)) && context) {
                    context_available = true;
                    context_source = "thread_mgr_focus_top";
                    context->Release();
                }
                document_mgr->Release();
            }
        }

        std::ostringstream attributes;
        attributes << "generation=" << focused_service_generation_.load()
                   << " dispatcher="
                   << static_cast<unsigned long long>(
                          reinterpret_cast<ULONG_PTR>(
                              focused_service_window_.load()))
                   << " context_available="
                   << (context_available ? 1 : 0)
                   << " context_source=" << context_source;
        const std::string fields = attributes.str();
        WriteStructuralEvent("focus_gained", -1, -1, ERROR_SUCCESS, fields);
    }

    void ClearToolbarAnchorCache() {
        last_toolbar_owner_ = nullptr;
        last_toolbar_anchor_ = {};
        last_toolbar_dpi_ = 96;
        has_toolbar_anchor_ = false;
    }

    bool CachedToolbarOwnerMatchesForeground() const {
        if (!last_toolbar_owner_ || !IsWindow(last_toolbar_owner_)) {
            return false;
        }
        HWND foreground = GetForegroundWindow();
        if (!foreground || !IsWindow(foreground)) {
            return false;
        }
        HWND foreground_root = GetAncestor(foreground, GA_ROOTOWNER);
        if (!foreground_root) {
            foreground_root = foreground;
        }
        HWND owner_root = GetAncestor(last_toolbar_owner_, GA_ROOTOWNER);
        if (!owner_root) {
            owner_root = last_toolbar_owner_;
        }
        return owner_root == foreground_root;
    }

    bool StateAcknowledgedForCurrentGeneration() const {
        const unsigned long long generation =
            focused_service_generation_.load();
        return state_.present && !state_.boot_id.empty() && generation != 0 &&
               acknowledged_state_generation_ == generation;
    }

    void RecordToolbarVisibilityReason(const char* reason,
                                       const char* context_source) {
        const std::string normalized_context_source =
            context_source ? context_source : "none";
        if (!reason ||
            (last_toolbar_visibility_reason_ == reason &&
             last_toolbar_context_source_ == normalized_context_source)) {
            return;
        }
        last_toolbar_visibility_reason_ = reason;
        last_toolbar_context_source_ = normalized_context_source;
        const HWND foreground = GetForegroundWindow();
        std::ostringstream attributes;
        attributes << "reason=" << reason
                   << " generation="
                   << focused_service_generation_.load()
                   << " owner="
                   << static_cast<unsigned long long>(
                          reinterpret_cast<ULONG_PTR>(last_toolbar_owner_))
                   << " foreground="
                   << static_cast<unsigned long long>(
                          reinterpret_cast<ULONG_PTR>(foreground))
                   << " foreground_match="
                   << (CachedToolbarOwnerMatchesForeground() ? 1 : 0)
                   << " context_source=" << normalized_context_source
                   << " state_revision=" << state_.revision;
        const std::string fields = attributes.str();
        WriteStructuralEvent("toolbar_visibility", -1, -1, ERROR_SUCCESS,
                             fields);
    }

    void UpdateLanguageBar(ITfContext* context) {
        ReconcileLanguageBarVisibility(context);
    }

    void ReconcileLanguageBarVisibility(ITfContext* context) {
        const char* context_source = context ? "explicit" : "none";
        if (!focused_) {
            RecordToolbarVisibilityReason("not_focused", context_source);
            language_bar_.Hide();
            return;
        }
        if (!IsCurrentFocusedTextService(
                this, focused_service_generation_.load())) {
            RecordToolbarVisibilityReason("not_current_generation",
                                          context_source);
            language_bar_.Hide();
            return;
        }
        if (!StateAcknowledgedForCurrentGeneration()) {
            RecordToolbarVisibilityReason("state_unacknowledged",
                                          context_source);
            language_bar_.Hide();
            return;
        }

        const bool contextless_update = context == nullptr;
        ITfContext* resolved_context = context;
        bool release_resolved_context = false;
        if (!resolved_context && thread_mgr_) {
            ITfDocumentMgr* document_mgr = nullptr;
            if (SUCCEEDED(thread_mgr_->GetFocus(&document_mgr)) && document_mgr) {
                if (SUCCEEDED(document_mgr->GetTop(&resolved_context)) &&
                    resolved_context) {
                    release_resolved_context = true;
                    context_source = "thread_mgr_focus_top";
                }
                document_mgr->Release();
            }
        }

        CandidateAnchorResult anchor_result;
        if (resolved_context && client_id_ != TF_CLIENTID_NULL) {
            CandidateAnchorEditSession* session = nullptr;
            try {
                session = new (std::nothrow)
                    CandidateAnchorEditSession(resolved_context, &anchor_result);
            } catch (...) {
            }
            if (session) {
                HRESULT edit_hr = E_FAIL;
                const HRESULT request_hr =
                    resolved_context->RequestEditSession(
                        client_id_, session, TF_ES_SYNC | TF_ES_READ, &edit_hr);
                session->Release();
                (void)request_hr;
                (void)edit_hr;
            }
        }
        if (release_resolved_context) {
            resolved_context->Release();
        }

        HWND resolved_owner = anchor_result.owner;
        if (resolved_owner && IsWindow(resolved_owner)) {
            HWND root = GetAncestor(resolved_owner, GA_ROOTOWNER);
            resolved_owner = root ? root : resolved_owner;
            if (resolved_owner != last_toolbar_owner_) {
                has_toolbar_anchor_ = false;
            }
            last_toolbar_owner_ = resolved_owner;
            last_toolbar_dpi_ = anchor_result.dpi;
            if (anchor_result.has_anchor) {
                last_toolbar_anchor_ = anchor_result.anchor;
                has_toolbar_anchor_ = true;
            }
        } else if (!contextless_update) {
            // A concrete context must establish its own owner. Reusing the
            // previous context's cache here can expose a bar over the wrong host.
            ClearToolbarAnchorCache();
            RecordToolbarVisibilityReason("no_owner_for_context",
                                          context_source);
            language_bar_.Hide();
            return;
        } else if (last_toolbar_owner_ && IsWindow(last_toolbar_owner_)) {
            context_source = "cached_owner";
        }
        if (!last_toolbar_owner_ || !IsWindow(last_toolbar_owner_)) {
            ClearToolbarAnchorCache();
            RecordToolbarVisibilityReason("owner_invalid", context_source);
            language_bar_.Hide();
            return;
        }
        if (!CachedToolbarOwnerMatchesForeground()) {
            RecordToolbarVisibilityReason("foreground_mismatch",
                                          context_source);
            language_bar_.Hide();
            return;
        }

        yune_windows::LanguageBarState bar_state;
        bar_state.ascii_mode = state_.ascii_mode;
        bar_state.full_shape = state_.full_shape;
        bar_state.output_standard = state_.output_standard;
        bar_state.schema_id = state_.schema_id;
        bar_state.owner = last_toolbar_owner_;
        bar_state.dpi = last_toolbar_dpi_;
        bar_state.toolbar_position = state_.toolbar_position;
        bar_state.skin_name = state_.toolbar_skin;
        if (has_toolbar_anchor_) {
            bar_state.anchor = last_toolbar_anchor_;
            bar_state.anchor.top =
                bar_state.anchor.top > 40 ? bar_state.anchor.top - 40 : 0;
            bar_state.anchor.bottom = bar_state.anchor.top + 34;
        }
        const unsigned long long show_generation =
            focused_service_generation_.load();
        bool still_current = false;
        bool update_succeeded = false;
        {
            // Serialize the final show claim with process-global focus
            // publication. A superseded STA cannot pass the early checks, lose
            // focus during anchor lookup, then show after the new service.
            std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
            still_current =
                g_focused_text_service == this &&
                g_committed_focus_generation == show_generation &&
                acknowledged_state_generation_ == show_generation &&
                CachedToolbarOwnerMatchesForeground();
            if (still_current) {
                update_succeeded = language_bar_.Update(bar_state, true);
            }
        }
        if (!still_current) {
            RecordToolbarVisibilityReason("superseded_before_show",
                                          context_source);
            language_bar_.Hide();
        } else if (update_succeeded) {
            RecordToolbarVisibilityReason("eligible_show", context_source);
        } else {
            RecordToolbarVisibilityReason("window_update_failed",
                                          context_source);
        }
    }

    void ReleaseInlineCompositionRefs() {
        if (composition_) {
            composition_->Release();
            composition_ = nullptr;
        }
        if (composition_range_) {
            composition_range_->Release();
            composition_range_ = nullptr;
        }
        if (composition_context_) {
            composition_context_->Release();
            composition_context_ = nullptr;
        }
    }

    void RememberCompositionContext(ITfContext* context) {
        if (composition_context_ == context) {
            return;
        }
        if (composition_context_) {
            composition_context_->Release();
            composition_context_ = nullptr;
        }
        if (context) {
            composition_context_ = context;
            composition_context_->AddRef();
        }
    }

    bool ApplyInlineComposition(ITfContext* context,
                                const std::wstring& commit_text,
                                const std::wstring& preedit) {
        if (!context || client_id_ == TF_CLIENTID_NULL) {
            if (preedit.empty()) {
                ReleaseInlineCompositionRefs();
            }
            return commit_text.empty() && preedit.empty();
        }
        InlineCompositionEditSession* session = nullptr;
        try {
            session = new (std::nothrow) InlineCompositionEditSession(
                context, static_cast<ITfCompositionSink*>(this), &composition_,
                &composition_range_, commit_text, preedit);
        } catch (...) {
            return false;
        }
        if (!session) {
            return false;
        }
        HRESULT edit_hr = E_FAIL;
        const HRESULT request_hr =
            context->RequestEditSession(client_id_, session,
                                        TF_ES_SYNC | TF_ES_READWRITE, &edit_hr);
        session->Release();
        if (FAILED(request_hr) || FAILED(edit_hr)) {
            WriteStructuralEvent("inline_composition_failed",
                                 static_cast<int>(preedit.size()));
            return false;
        }
        if (preedit.empty()) {
            if (composition_context_) {
                composition_context_->Release();
                composition_context_ = nullptr;
            }
        } else {
            RememberCompositionContext(context);
            WriteStructuralEvent("inline_composition_update",
                                 static_cast<int>(preedit.size()));
        }
        return true;
    }

    void ClearInlineCompositionText() {
        ITfContext* context = composition_context_;
        if (context) {
            context->AddRef();
            (void)ApplyInlineComposition(context, L"", L"");
            context->Release();
        }
        ReleaseInlineCompositionRefs();
    }

    void EndComposeSession(bool notify_server) {
        if (compose_session_.empty()) {
            return;
        }
        if (notify_server) {
            (void)QueryComposeOperation(ComposePayload("compose-end"),
                                        composition_context_);
        }
        compose_session_.clear();
    }

    void ClearCompositionState(bool notify_server = true,
                               bool clear_inline = true) {
        EndComposeSession(notify_server);
        buffer_.clear();
        composition_preedit_.clear();
        candidate_.clear();
        last_candidates_.clear();
        candidate_page_index_ = 0;
        candidate_window_.Hide();
        if (clear_inline) {
            ClearInlineCompositionText();
        }
    }

    void ClearShiftState() {
        shift_down_ = false;
        shift_consumed_ = false;
        shift_rejection_reason_ = ShiftRejectionReason::None;
        shift_token_ = 0;
        shift_token_generation_ = 0;
    }

    void ClearPendingAsciiToggle() {
        pending_ascii_intent_.Reset();
        pending_ascii_deadline_ms_ = 0;
    }

    void CancelPendingAsciiToggle(const char* outcome) {
        if (pending_ascii_intent_.active()) {
            WritePendingAsciiOutcome(outcome);
        }
        ClearPendingAsciiToggle();
    }

    void CancelLoneShiftToggle() {
        shift_consumed_ = true;
        if (shift_rejection_reason_ == ShiftRejectionReason::None) {
            shift_rejection_reason_ = ShiftRejectionReason::Consumed;
        }
    }

    bool AppendStateExpectation(std::string* payload) const {
        if (!payload || !StateAcknowledgedForCurrentGeneration()) {
            return false;
        }
        *payload += "expect_boot_id=";
        *payload += Narrow(state_.boot_id);
        *payload += "\nexpect_revision=";
        *payload += std::to_string(state_.revision);
        *payload += "\n";
        return true;
    }

    bool CommitOrClearCompositionBeforeStateChange(ITfContext* context) {
        if (!IsComposing()) {
            return true;
        }

        const int buffer_length = static_cast<int>(buffer_.size());
        const int candidate_count = static_cast<int>(last_candidates_.size());
        bool committed = false;
        if (context && !compose_session_.empty()) {
            ServerResponse response =
                QueryComposeOperation(ComposePayload("compose-commit"), context);
            if (response.ok) {
                WriteStructuralEvent("commit_request", buffer_length,
                                     candidate_count);
                committed = ApplyComposeResponse(context, response);
            }
        }

        WriteStructuralEvent(committed ? "composition_flush_commit"
                                       : "composition_flush_clear",
                             buffer_length, candidate_count);
        ClearCompositionState(true);
        return committed;
    }

    void ToggleBoolState(const char* name, ITfContext* context) {
        CommitOrClearCompositionBeforeStateChange(context);
        const bool current =
            std::string_view(name) == "full_shape" ? state_.full_shape
                                                   : state_.ascii_mode;
        std::string payload = "op=set-option\nname=";
        payload += name;
        payload += "\nvalue=";
        payload += current ? "0" : "1";
        payload += "\n";
        if (!AppendStateExpectation(&payload)) {
            RequestSharedServerWarmupAsync();
            return;
        }
        payload += ".\n";
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (response.transport_unknown) {
            state_.present = false;
            acknowledged_state_generation_ = 0;
            language_bar_.Hide();
            RequestSharedServerWarmupAsync();
        }
    }

    void DrivePendingAsciiToggle(ITfContext* context) {
        if (!pending_ascii_intent_.active()) {
            return;
        }
        const ULONGLONG now = GetTickCount64();
        if (pending_ascii_deadline_ms_ == 0 ||
            now >= pending_ascii_deadline_ms_) {
            CancelPendingAsciiToggle("deadline_expired");
            return;
        }
        const unsigned long long generation =
            focused_service_generation_.load();
        if (pending_ascii_intent_.generation() != generation ||
            !IsCurrentFocusedTextService(this, generation)) {
            CancelPendingAsciiToggle("cancelled_noncurrent");
            return;
        }
        if (!CachedToolbarOwnerMatchesForeground()) {
            CancelPendingAsciiToggle("cancelled_foreground_mismatch");
            return;
        }
        if (!StateAcknowledgedForCurrentGeneration()) {
            return;
        }
        (void)pending_ascii_intent_.ResolveDesired(state_.ascii_mode);
        if (state_.ascii_mode == pending_ascii_intent_.desired()) {
            WritePendingAsciiOutcome("converged");
            ClearPendingAsciiToggle();
            return;
        }
        if (pending_ascii_intent_.attempts() >=
            kMaxAsciiToggleCasAttempts) {
            WriteStructuralEvent("shift_toggle_retry_exhausted");
            WritePendingAsciiOutcome("retry_exhausted");
            ClearPendingAsciiToggle();
            return;
        }

        std::string payload =
            "op=set-option\nname=ascii_mode\nvalue=";
        payload += pending_ascii_intent_.desired() ? "1\n" : "0\n";
        if (!AppendStateExpectation(&payload)) {
            return;
        }
        payload += ".\n";
        pending_ascii_intent_.RecordAttempt();
        ServerResponse response =
            QueryOperation(payload, context,
                           RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (response.transport_unknown) {
            WritePendingAsciiOutcome("outcome_unknown");
            state_.present = false;
            acknowledged_state_generation_ = 0;
            language_bar_.Hide();
            RequestSharedServerWarmupAsync();
            return;
        }
        if (StateAcknowledgedForCurrentGeneration() &&
            state_.ascii_mode == pending_ascii_intent_.desired()) {
            WritePendingAsciiOutcome(response.applied ? "applied"
                                                      : "converged");
            ClearPendingAsciiToggle();
            return;
        }
        if (response.rejected &&
            response.reason != L"revision_conflict" &&
            response.reason != L"epoch_conflict") {
            WritePendingAsciiOutcome(
                response.outcome == L"persist_failed" ? "persist_failed"
                                                        : "server_rejected");
            ClearPendingAsciiToggle();
            return;
        }
        if (!response.ok) {
            WritePendingAsciiOutcome("invalid_response");
            ClearPendingAsciiToggle();
            return;
        }
        if (pending_ascii_intent_.attempts() >=
            kMaxAsciiToggleCasAttempts) {
            WriteStructuralEvent("shift_toggle_retry_exhausted");
            WritePendingAsciiOutcome("retry_exhausted");
            ClearPendingAsciiToggle();
        }
    }

    void WritePendingAsciiOutcome(const char* outcome) {
        std::ostringstream attributes;
        attributes << "generation=" << pending_ascii_intent_.generation()
                   << " outcome=" << (outcome ? outcome : "unknown")
                   << " press_count=" << pending_ascii_intent_.press_count()
                   << " desired=" << (pending_ascii_intent_.desired() ? 1 : 0)
                   << " attempts=" << pending_ascii_intent_.attempts()
                   << " state_revision=" << state_.revision;
        const std::string fields = attributes.str();
        WriteStructuralEvent("shift_toggle_outcome", -1, -1,
                             ERROR_SUCCESS, fields);
    }

    void QueueAsciiToggle(unsigned long long token, ShiftDetector detector,
                          ITfContext* context,
                          bool record_shift_disposition = true) {
        CommitOrClearCompositionBeforeStateChange(context);
        const unsigned long long generation =
            focused_service_generation_.load();
        const bool same_pending_generation =
            pending_ascii_intent_.active() &&
            pending_ascii_intent_.generation() == generation;
        const bool coalesced = same_pending_generation;
        pending_ascii_intent_.AcceptPress(
            generation, StateAcknowledgedForCurrentGeneration(),
            state_.ascii_mode);
        if (!same_pending_generation) {
            pending_ascii_deadline_ms_ =
                GetTickCount64() + kPendingAsciiToggleDeadlineMs;
        }
        if (coalesced && record_shift_disposition) {
            std::ostringstream attributes;
            attributes << "toggle_token=" << token
                       << " generation=" << generation
                       << " detector=" << ShiftDetectorName(detector)
                       << " state_revision=" << state_.revision;
            const std::string fields = attributes.str();
            WriteStructuralEvent("shift_parity_coalesced", -1, -1,
                                 ERROR_SUCCESS, fields);
        }

        if (!StateAcknowledgedForCurrentGeneration()) {
            RequestSharedServerWarmupAsync();
            return;
        }
        DrivePendingAsciiToggle(context);
    }

    std::wstring NextSchemaId() const {
        const std::wstring schemas[] = {L"jyut6ping3", L"cangjie5",
                                        L"luna_pinyin"};
        constexpr size_t schema_count = sizeof(schemas) / sizeof(schemas[0]);
        for (size_t i = 0; i < schema_count; ++i) {
            if (state_.schema_id == schemas[i]) {
                return schemas[(i + 1) % schema_count];
            }
        }
        return schemas[0];
    }

    std::wstring NextOutputStandard() const {
        const std::wstring standards[] = {
            L"opencc_traditional",
            L"hong_kong_traditional",
            L"taiwan_traditional",
            L"mainland_simplified",
        };
        constexpr size_t standard_count =
            sizeof(standards) / sizeof(standards[0]);
        for (size_t i = 0; i < standard_count; ++i) {
            if (state_.output_standard == standards[i]) {
                return standards[(i + 1) % standard_count];
            }
        }
        return L"hong_kong_traditional";
    }

    void SelectSchema(const std::wstring& schema_id, ITfContext* context) {
        CommitOrClearCompositionBeforeStateChange(context);
        std::string payload = "op=select-schema\nschema=";
        payload += Narrow(schema_id);
        payload += "\n";
        if (!AppendStateExpectation(&payload)) {
            RequestSharedServerWarmupAsync();
            return;
        }
        payload += ".\n";
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (response.transport_unknown) {
            state_.present = false;
            acknowledged_state_generation_ = 0;
            language_bar_.Hide();
            RequestSharedServerWarmupAsync();
        }
    }

    void SetOutputStandard(const std::wstring& standard, ITfContext* context) {
        CommitOrClearCompositionBeforeStateChange(context);
        std::string payload =
            "op=set-option\nname=output_standard\nvalue=" + Narrow(standard) +
            "\n";
        if (!AppendStateExpectation(&payload)) {
            RequestSharedServerWarmupAsync();
            return;
        }
        payload += ".\n";
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (response.transport_unknown) {
            state_.present = false;
            acknowledged_state_generation_ = 0;
            language_bar_.Hide();
            RequestSharedServerWarmupAsync();
        }
    }

    void CycleSchema(ITfContext* context) {
        SelectSchema(NextSchemaId(), context);
    }

    void CycleOutputStandard(ITfContext* context) {
        SetOutputStandard(NextOutputStandard(), context);
    }

    void LaunchOrFocusSettings() {
        HWND existing = FindWindowW(L"YuneWindowsSettingsWindow", nullptr);
        if (existing && IsWindow(existing)) {
            ShowWindow(existing, SW_SHOWNORMAL);
            SetForegroundWindow(existing);
            WriteStructuralEvent("settings_focus");
            return;
        }

        const std::filesystem::path settings_exe =
            ModuleDirectory() / L"YuneWindowsSettings.exe";
        if (!PathExists(settings_exe)) {
            WriteStructuralEvent("settings_launch_failed");
            return;
        }

        std::wstring command_line = QuoteCommandLineArgument(settings_exe);
        STARTUPINFOW startup = {};
        startup.cb = sizeof(startup);
        startup.dwFlags = STARTF_USESHOWWINDOW;
        startup.wShowWindow = SW_SHOWNORMAL;
        PROCESS_INFORMATION process = {};
        const BOOL launched = CreateProcessW(
            settings_exe.c_str(), command_line.data(), nullptr, nullptr, FALSE,
            0, nullptr, ModuleDirectory().c_str(), &startup, &process);
        if (!launched) {
            WriteStructuralEvent("settings_launch_failed");
            return;
        }
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        WriteStructuralEvent("settings_launch_started");
    }

    void HandleLanguageBarClick(yune_windows::LanguageBarSegment segment) {
        switch (segment) {
            case yune_windows::LanguageBarSegment::AsciiMode:
                QueueAsciiToggle(++g_shift_sequence, ShiftDetector::Sink,
                                 nullptr, false);
                break;
            case yune_windows::LanguageBarSegment::FullShape:
                ToggleBoolState("full_shape", nullptr);
                break;
            case yune_windows::LanguageBarSegment::OutputStandard:
                CycleOutputStandard(nullptr);
                break;
            case yune_windows::LanguageBarSegment::Schema:
                CycleSchema(nullptr);
                break;
            case yune_windows::LanguageBarSegment::Settings:
                LaunchOrFocusSettings();
                break;
        }
    }

    void HandleLanguageBarPositionChanged(int x, int y) {
        for (int attempt = 0; attempt < 2; ++attempt) {
            std::string payload = "op=set-toolbar-position\nx=";
            payload += std::to_string(x);
            payload += "\ny=";
            payload += std::to_string(y);
            payload += "\n";
            if (!AppendStateExpectation(&payload)) {
                return;
            }
            payload += ".\n";
            ServerResponse response = QueryOperation(
                payload, nullptr, RefreshStateMode::ExistingServerOnly,
                kServerKeyPathQueryTimeoutMs);
            if (response.transport_unknown) {
                state_.present = false;
                acknowledged_state_generation_ = 0;
                language_bar_.Hide();
                RequestSharedServerWarmupAsync();
                return;
            }
            if (response.applied) {
                return;
            }
            const bool retryable_conflict =
                response.rejected &&
                (response.reason == L"revision_conflict" ||
                 response.reason == L"epoch_conflict");
            if (!retryable_conflict ||
                !IsCurrentFocusedTextService(
                    this, focused_service_generation_.load()) ||
                !CachedToolbarOwnerMatchesForeground()) {
                return;
            }
        }
        WriteStructuralEvent("toolbar_position_retry_exhausted");
    }

    bool ShouldHandleKeyDown(WPARAM key, bool shift_pressed) const {
        if (IsShortcutModifierDown()) {
            return false;
        }
        if (state_.present && state_.ascii_mode && !IsComposing()) {
            if ((key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z') ||
                (key >= L'0' && key <= L'9') || key == VK_SPACE ||
                key == VK_RETURN || IsPunctuationKey(key, shift_pressed)) {
                return false;
            }
        }
        if (!shift_pressed &&
            ((key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z'))) {
            return true;
        }
        if (key == VK_SPACE || key == VK_RETURN || key == VK_BACK ||
            key == VK_ESCAPE || key == VK_NEXT || key == VK_PRIOR) {
            return IsComposing();
        }
        if (!shift_pressed && key >= L'1' && key <= L'9') {
            return IsComposing();
        }
        if (IsPunctuationKey(key, shift_pressed)) {
            return true;
        }
        return false;
    }

    bool CommitText(ITfContext* context, const std::wstring& text) {
        if (!context || client_id_ == TF_CLIENTID_NULL) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        InsertTextEditSession* session = nullptr;
        try {
            session = new (std::nothrow) InsertTextEditSession(context, text);
        } catch (...) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        if (!session) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        HRESULT edit_hr = E_FAIL;
        const HRESULT request_hr =
            context->RequestEditSession(client_id_, session,
                                        TF_ES_SYNC | TF_ES_READWRITE, &edit_hr);
        session->Release();
        if (FAILED(request_hr) || FAILED(edit_hr)) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        WriteStructuralEvent("commit_text",
                             static_cast<int>(text.size()));
        return true;
    }

    bool CommitRawFallback(ITfContext* context, const std::wstring& text) {
        WriteStructuralEvent("server_fallback_raw_commit",
                             static_cast<int>(text.size()));
        ClearCompositionState(false);
        if (text.empty()) {
            return true;
        }
        return CommitText(context, text);
    }

    bool CommitRawBuffer(ITfContext* context) {
        if (!IsComposing()) {
            return true;
        }
        const int buffer_length = static_cast<int>(buffer_.size());
        const int candidate_count = static_cast<int>(last_candidates_.size());
        WriteStructuralEvent("raw_commit_request", buffer_length,
                             candidate_count);
        if (compose_session_.empty()) {
            ClearCompositionState(false);
            return false;
        }
        ServerResponse response =
            QueryComposeOperation(ComposePayload("compose-commit-raw"), context);
        if (!response.ok) {
            ClearCompositionState(false);
            return false;
        }
        return ApplyComposeResponse(context, response);
    }

    bool CommitCompositionForPunctuation(ITfContext* context, WPARAM key,
                                         bool shift) {
        ServerResponse punctuation_response =
            QueryInput(PunctuationInput(key, shift), true);
        if (!punctuation_response.ok ||
            punctuation_response.commit_text.empty()) {
            return false;
        }

        bool committed_composition = false;
        if (IsComposing()) {
            ServerResponse composition_response =
                compose_session_.empty()
                    ? ServerResponse{}
                    : QueryComposeOperation(ComposePayload("compose-commit"),
                                            context);
            if (!composition_response.ok) {
                return false;
            }
            WriteStructuralEvent("commit_request",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            if (!ApplyComposeResponse(context, composition_response)) {
                return false;
            }
            committed_composition = true;
        }

        WriteStructuralEvent("punctuation_commit", 0, 0);
        if (CommitText(context, punctuation_response.commit_text)) {
            candidate_window_.Hide();
            return true;
        }
        return committed_composition;
    }

    bool PageComposition(ITfContext* context, int delta) {
        if (last_candidates_.empty()) {
            candidate_window_.Hide();
            return false;
        }
        const int page_count = yune_windows::CandidatePageCount(
            static_cast<int>(last_candidates_.size()), kCandidatePageSize);
        const int next_page = yune_windows::ClampCandidatePageIndex(
            candidate_page_index_ + delta,
            static_cast<int>(last_candidates_.size()), kCandidatePageSize);
        if (next_page == candidate_page_index_ || page_count <= 1) {
            return false;
        }
        if (compose_session_.empty()) {
            return false;
        }
        std::string payload = "op=compose-page\nsession=";
        payload += Narrow(compose_session_);
        payload += "\ndirection=";
        payload += delta > 0 ? "next" : "prev";
        payload += "\n.\n";
        ServerResponse response = QueryComposeOperation(payload, context);
        if (!response.ok) {
            ClearCompositionState(false);
            return false;
        }
        candidate_page_index_ = next_page;
        (void)ApplyComposeResponse(context, response, false);
        WriteStructuralEvent("candidate_page",
                             static_cast<int>(buffer_.size()),
                             static_cast<int>(last_candidates_.size()));
        return true;
    }

    bool ShowCandidates(ITfContext* context,
                        const std::vector<yune_windows::CandidateWindowCandidate>& candidates) {
        if (candidates.empty()) {
            candidate_window_.Hide();
            return false;
        }

        try {
            CandidateAnchorResult anchor_result;
            if (context && client_id_ != TF_CLIENTID_NULL) {
                CandidateAnchorEditSession* session = nullptr;
                try {
                    session = new (std::nothrow)
                        CandidateAnchorEditSession(context, &anchor_result);
                } catch (...) {
                }
                if (session) {
                    HRESULT edit_hr = E_FAIL;
                    const HRESULT request_hr =
                        context->RequestEditSession(client_id_, session,
                                                    TF_ES_SYNC | TF_ES_READ,
                                                    &edit_hr);
                    session->Release();
                    (void)request_hr;
                    (void)edit_hr;
                }
            }

            if (!anchor_result.has_anchor) {
                WriteStructuralEvent("candidate_anchor_failed",
                                     static_cast<int>(candidates.size()),
                                     static_cast<int>(candidates.size()));
                candidate_window_.Hide();
                return false;
            }

            yune_windows::CandidateWindowState state;
            state.candidates = candidates;
            state.anchor = anchor_result.anchor;
            state.owner = anchor_result.owner;
            state.dpi = anchor_result.dpi;
            state.page_index = candidate_page_index_;
            state.highlighted_index = 0;
            state.page_size = kCandidatePageSize;
            if (!candidate_window_.Update(state, true)) {
                WriteStructuralEvent("candidate_window_failed",
                                     static_cast<int>(candidates.size()),
                                     static_cast<int>(candidates.size()));
                return false;
            }
        } catch (...) {
            WriteStructuralEvent("candidate_window_failed",
                                 static_cast<int>(candidates.size()),
                                 static_cast<int>(candidates.size()));
            return false;
        }
        return true;
    }

    std::atomic<long> ref_;
    ITfThreadMgr* thread_mgr_ = nullptr;
    TfClientId client_id_ = TF_CLIENTID_NULL;
    std::wstring compose_session_;
    std::wstring buffer_;
    std::wstring composition_preedit_;
    std::wstring candidate_;
    std::vector<yune_windows::CandidateWindowCandidate> last_candidates_;
    int candidate_page_index_ = 0;
    ITfComposition* composition_ = nullptr;
    ITfRange* composition_range_ = nullptr;
    ITfContext* composition_context_ = nullptr;
    ImeState state_;
    unsigned long long acknowledged_state_generation_ = 0;
    bool shift_down_ = false;
    bool shift_consumed_ = false;
    ShiftRejectionReason shift_rejection_reason_ =
        ShiftRejectionReason::None;
    unsigned long long shift_token_ = 0;
    unsigned long long shift_token_generation_ = 0;
    unsigned long last_hook_shift_token_adopted_ = 0;
    bool focused_ = false;
    yune_windows::reliability::ShiftTokenArbiter shift_token_arbiter_;
    yune_windows::reliability::ToggleParityIntent pending_ascii_intent_;
    ULONGLONG pending_ascii_deadline_ms_ = 0;
    std::atomic<HWND> focused_service_window_{nullptr};
    std::atomic<unsigned long long> focused_service_generation_{0};
    std::atomic<unsigned long> orphaned_focus_references_{0};
    std::atomic<DWORD> focused_service_window_thread_id_{0};
    std::mutex focused_service_handoff_mutex_;
    std::vector<unsigned long long> pending_focused_service_handoffs_;
    bool retire_focused_service_window_ = false;
    HWND last_toolbar_owner_ = nullptr;
    std::string last_toolbar_visibility_reason_;
    std::string last_toolbar_context_source_;
    RECT last_toolbar_anchor_ = {};
    UINT last_toolbar_dpi_ = 96;
    bool has_toolbar_anchor_ = false;
    yune_windows::NativeCandidateWindow candidate_window_;
    yune_windows::LanguageBarWindow language_bar_;
};

bool EnsureFocusedServiceWindowClassRegistered() {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = FocusedServiceWindowProc;
    wc.hInstance = g_instance;
    wc.lpszClassName = kFocusedServiceWindowClass;
    return RegisterClassExW(&wc) != 0 ||
           GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

bool IsFocusedServiceWindow(HWND hwnd, DWORD expected_thread = 0,
                            TextService* expected_service = nullptr) {
    if (!hwnd || !IsWindow(hwnd)) {
        return false;
    }
    const DWORD window_thread = GetWindowThreadProcessId(hwnd, nullptr);
    if ((expected_thread != 0 && window_thread != expected_thread) ||
        window_thread == 0) {
        return false;
    }
    wchar_t class_name[64] = {};
    return GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name)) != 0 &&
           lstrcmpW(class_name, kFocusedServiceWindowClass) == 0 &&
           (!expected_service ||
            reinterpret_cast<TextService*>(
                GetWindowLongPtrW(hwnd, GWLP_USERDATA)) == expected_service);
}

bool TextService::PrepareFocusedServiceActivation(
    unsigned long long generation) {
    const DWORD current_thread = GetCurrentThreadId();
    HWND dispatcher = focused_service_window_.load();
    if (dispatcher) {
        const DWORD owner_thread =
            GetWindowThreadProcessId(dispatcher, nullptr);
        const bool still_bound =
            IsFocusedServiceWindow(dispatcher, owner_thread, this);
        if (still_bound && owner_thread != current_thread) {
            // Never abandon a live service-bound HWND or create a second
            // dispatcher on another apartment. The caller fails activation and
            // the owning STA remains responsible for retirement.
            WriteStructuralEvent("focused_service_wrong_apartment");
            return false;
        }
        if (!still_bound) {
            HWND expected = dispatcher;
            (void)focused_service_window_.compare_exchange_strong(expected,
                                                                  nullptr);
            dispatcher = nullptr;
            focused_service_window_thread_id_.store(0);
        } else {
            focused_service_window_thread_id_.store(current_thread);
        }
    }
    if (!dispatcher &&
        EnsureFocusedServiceWindowClassRegistered()) {
        dispatcher = CreateWindowExW(
            0, kFocusedServiceWindowClass, L"Yune Windows Focus Handoff", 0,
            0, 0, 0, 0, HWND_MESSAGE, nullptr, g_instance, this);
        focused_service_window_.store(dispatcher);
        focused_service_window_thread_id_.store(dispatcher ? current_thread : 0);
    }
    focused_service_generation_.store(generation);
    shift_token_arbiter_.Reset(generation);
    last_hook_shift_token_adopted_ = 0;
    CancelPendingAsciiToggle("cancelled_generation_change");
    retire_focused_service_window_ = false;
    if (dispatcher) {
        (void)SetTimer(dispatcher, kFocusedServiceWatchdogTimer,
                       kFocusedServiceWatchdogIntervalMs, nullptr);
    }
    return dispatcher != nullptr;
}

bool TextService::QueueSupersededFocus(unsigned long long generation) {
    std::lock_guard<std::mutex> lock(focused_service_handoff_mutex_);
    const HWND dispatcher = focused_service_window_.load();
    if (!IsFocusedServiceWindow(
            dispatcher, focused_service_window_thread_id_.load(), this)) {
        return false;
    }
    pending_focused_service_handoffs_.push_back(generation);
    if (PostMessageW(dispatcher, kFocusedServiceSupersededMessage,
                     static_cast<WPARAM>(generation), 0)) {
        return true;
    }
    pending_focused_service_handoffs_.pop_back();
    return false;
}

void TextService::HandleSupersededFocus(
    HWND dispatcher, unsigned long long generation) {
    size_t remaining = 0;
    {
        std::lock_guard<std::mutex> lock(focused_service_handoff_mutex_);
        const auto pending = std::find(
            pending_focused_service_handoffs_.begin(),
            pending_focused_service_handoffs_.end(), generation);
        if (pending == pending_focused_service_handoffs_.end()) {
            return;
        }
        pending_focused_service_handoffs_.erase(pending);
        remaining = pending_focused_service_handoffs_.size();
    }

    // Queueing occurs while the global focus mutex is held. Taking it here is a
    // commit barrier: the old registration reference is not released until the
    // new focused service has replaced it.
    {
        std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
    }
    if (focused_service_generation_.load() == generation &&
        !IsCurrentFocusedTextService(this, generation)) {
        // This callback runs on the superseded service's apartment/window
        // thread. A later activation on the same thread changes the generation
        // before a stale callback can run, so A -> B -> A cannot hide current A.
        CancelPendingAsciiToggle("cancelled_superseded");
        HideLanguageBarForSupersededFocus();
        retire_focused_service_window_ = true;
    }

    if (remaining == 0 && retire_focused_service_window_ &&
        dispatcher == focused_service_window_.load()) {
        focused_service_window_.store(nullptr);
        SetWindowLongPtrW(dispatcher, GWLP_USERDATA, 0);
        DestroyWindow(dispatcher);
    }

    // Releases the old process-global focus-registration reference transferred
    // by ActivateFocusedTextService. This is deliberately the final operation:
    // it may delete the service after its apartment-owned dispatcher is gone.
    Release();
}

bool TextService::DetachFocusedServiceWindow(
    HWND dispatcher, unsigned long* pending_references) {
    if (!pending_references) {
        return false;
    }
    *pending_references = 0;
    HWND expected = dispatcher;
    if (!focused_service_window_.compare_exchange_strong(expected, nullptr)) {
        return false;
    }
    (void)KillTimer(dispatcher, kFocusedServiceWatchdogTimer);
    focused_service_window_thread_id_.store(0);
    std::lock_guard<std::mutex> lock(focused_service_handoff_mutex_);
    *pending_references = static_cast<unsigned long>(
        pending_focused_service_handoffs_.size());
    pending_focused_service_handoffs_.clear();
    retire_focused_service_window_ = false;
    return true;
}

LRESULT CALLBACK FocusedServiceWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam) {
    TextService* service = reinterpret_cast<TextService*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
        service = create ? static_cast<TextService*>(create->lpCreateParams)
                         : nullptr;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(service));
        return service ? TRUE : FALSE;
    }
    if (message == kFocusedServiceSupersededMessage && service) {
        service->HandleSupersededFocus(
            hwnd, static_cast<unsigned long long>(wparam));
        return 0;
    }
    if (message == kShiftHookToggleMessage && service) {
        service->HandleDeferredLoneShiftToggle(
            static_cast<unsigned long long>(wparam),
            static_cast<unsigned long long>(lparam), ShiftDetector::Hook);
        return 0;
    }
    const ShiftRejectionReason hook_rejection =
        ShiftHookRejectionReason(message);
    if (hook_rejection != ShiftRejectionReason::None && service) {
        service->SettleRejectedShiftToken(
            static_cast<unsigned long long>(wparam),
            static_cast<unsigned long long>(lparam), ShiftDetector::Hook,
            ShiftRejectionDisposition(hook_rejection));
        return 0;
    }
    if (message == WM_TIMER &&
        wparam == kFocusedServiceWatchdogTimer && service) {
        service->HandleFocusedServiceWatchdog(hwnd);
        return 0;
    }
    if (message == WM_NCDESTROY) {
        (void)KillTimer(hwnd, kFocusedServiceWatchdogTimer);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        unsigned long references_to_release = 0;
        const bool detached =
            service && service->DetachFocusedServiceWindow(
                           hwnd, &references_to_release);
        if (detached) {
            std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
            if (g_focused_text_service == service) {
                g_focused_text_service = nullptr;
                g_committed_focus_generation = 0;
                ++references_to_release;
                g_published_focus_generation.store(
                    0, std::memory_order_release);
                g_shift_hook_active_generation.store(
                    0, std::memory_order_release);
                g_shift_hook_dispatcher.store(nullptr,
                                              std::memory_order_release);
                g_shift_hook_dispatcher_thread_id.store(
                    0, std::memory_order_release);
                g_hook_shift_down.store(false, std::memory_order_release);
                g_hook_shift_consumed.store(false,
                                            std::memory_order_release);
                g_hook_shift_snapshot.store(0, std::memory_order_release);
                ResetShiftCorrelationHistory();
                if (g_shift_hook) {
                    UnhookWindowsHookEx(g_shift_hook);
                    g_shift_hook = nullptr;
                    g_shift_hook_thread_id = 0;
                    WriteStructuralEvent("shift_hook_uninstalled");
                }
            }
            references_to_release += service->TakeOrphanedFocusReferences();
        }
        const LRESULT result =
            DefWindowProcW(hwnd, message, wparam, lparam);
        while (service && references_to_release > 0) {
            --references_to_release;
            service->Release();
        }
        return result;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool IsCurrentFocusedTextService(TextService* service,
                                 unsigned long long generation) {
    if (!service || generation == 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
    return g_focused_text_service == service &&
           g_committed_focus_generation == generation &&
           service->FocusedServiceGeneration() == generation;
}

bool EnsureShiftHookInstalledLocked() {
    const DWORD current_thread = GetCurrentThreadId();
    if (g_shift_hook && g_shift_hook_thread_id == current_thread) {
        return true;
    }
    if (g_shift_hook) {
        UnhookWindowsHookEx(g_shift_hook);
        g_shift_hook = nullptr;
        g_shift_hook_thread_id = 0;
    }
    g_shift_hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                                     g_instance, 0);
    if (!g_shift_hook) {
        WriteStructuralEvent("shift_hook_install_failed");
        return false;
    }
    g_shift_hook_thread_id = current_thread;
    WriteStructuralEvent("shift_hook_installed");
    return true;
}

bool PublishShiftHookDispatcherLocked(TextService* service) {
    const HWND dispatcher = service ? service->FocusedServiceWindow() : nullptr;
    const DWORD dispatcher_thread =
        service ? service->FocusedServiceWindowThreadId() : 0;
    if (!service ||
        !IsFocusedServiceWindow(dispatcher, dispatcher_thread, service)) {
        g_shift_hook_dispatcher.store(nullptr, std::memory_order_release);
        g_shift_hook_dispatcher_thread_id.store(0,
                                                std::memory_order_release);
        g_published_focus_generation.store(0, std::memory_order_release);
        g_shift_hook_active_generation.store(0,
                                             std::memory_order_release);
        return false;
    }
    g_shift_hook_dispatcher.store(dispatcher, std::memory_order_release);
    g_shift_hook_dispatcher_thread_id.store(dispatcher_thread,
                                            std::memory_order_release);
    if (g_focused_text_service != service ||
        g_committed_focus_generation !=
            service->FocusedServiceGeneration()) {
        g_shift_hook_dispatcher.store(nullptr, std::memory_order_release);
        g_shift_hook_dispatcher_thread_id.store(0,
                                                std::memory_order_release);
        g_published_focus_generation.store(0, std::memory_order_release);
        g_shift_hook_active_generation.store(0,
                                             std::memory_order_release);
        return false;
    }
    g_published_focus_generation.store(g_committed_focus_generation,
                                       std::memory_order_release);
    return true;
}

bool RefreshShiftHookForFocusedService(TextService* service) {
    std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
    if (!service || g_focused_text_service != service ||
        !PublishShiftHookDispatcherLocked(service)) {
        return false;
    }
    const bool installed = EnsureShiftHookInstalledLocked();
    g_shift_hook_active_generation.store(
        installed ? g_committed_focus_generation : 0,
        std::memory_order_release);
    return installed;
}

bool ActivateFocusedTextService(TextService* service) {
    if (!service) {
        return false;
    }
    const unsigned long long generation =
        NextNonzeroSequence(&g_focused_service_generation);
    if (!service->PrepareFocusedServiceActivation(generation)) {
        return false;
    }
    TextService* old_service = nullptr;
    unsigned long long old_generation = 0;
    {
        std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
        if (service == g_focused_text_service) {
            g_committed_focus_generation = generation;
            g_hook_shift_down.store(false, std::memory_order_release);
            g_hook_shift_consumed.store(false, std::memory_order_release);
            g_hook_shift_snapshot.store(0, std::memory_order_release);
            ResetShiftCorrelationHistory();
            if (PublishShiftHookDispatcherLocked(service)) {
                const bool installed = EnsureShiftHookInstalledLocked();
                g_shift_hook_active_generation.store(
                    installed ? generation : 0,
                    std::memory_order_release);
            }
            return true;
        }
        old_service = g_focused_text_service;
        old_generation = old_service ? g_committed_focus_generation : 0;
        service->AddRef();
        g_focused_text_service = service;
        g_committed_focus_generation = generation;
        g_hook_shift_down.store(false, std::memory_order_release);
        g_hook_shift_consumed.store(false, std::memory_order_release);
        g_hook_shift_snapshot.store(0, std::memory_order_release);
        ResetShiftCorrelationHistory();
        // Focus identity is authoritative even when the optional lone-Shift
        // hook cannot be created. Publish the service-bound dispatcher only
        // after the safe service handoff has committed.
        if (PublishShiftHookDispatcherLocked(service)) {
            const bool installed = EnsureShiftHookInstalledLocked();
            g_shift_hook_active_generation.store(
                installed ? generation : 0,
                std::memory_order_release);
        }
    }
    if (old_service &&
        !old_service->QueueSupersededFocus(old_generation)) {
        // The new registration is already authoritative, so a dead apartment
        // cannot permanently block focus in hosts with short-lived apartments.
        // Keep the old
        // global reference for release if that apartment later deactivates;
        // otherwise the process reclaims it at exit without cross-STA teardown.
        old_service->RetainOrphanedFocusReference();
        WriteStructuralEvent("focused_service_dispatcher_dead");
    }
    return true;
}

void DeactivateFocusedTextService(TextService* service) {
    if (!service) {
        return;
    }
    TextService* released_service = nullptr;
    bool was_current = false;
    {
        std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
        // A late focus-loss from an older TSF service must not clear the newer
        // focused service in this process.
        if (g_focused_text_service != service) {
            was_current = false;
        } else {
            was_current = true;
            released_service = g_focused_text_service;
            g_focused_text_service = nullptr;
            g_committed_focus_generation = 0;
            g_published_focus_generation.store(0,
                                               std::memory_order_release);
            g_shift_hook_active_generation.store(
                0, std::memory_order_release);
            g_shift_hook_dispatcher.store(nullptr,
                                          std::memory_order_release);
            g_shift_hook_dispatcher_thread_id.store(
                0, std::memory_order_release);
            g_hook_shift_down.store(false, std::memory_order_release);
            g_hook_shift_consumed.store(false, std::memory_order_release);
            g_hook_shift_snapshot.store(0, std::memory_order_release);
            ResetShiftCorrelationHistory();
            if (g_shift_hook) {
                UnhookWindowsHookEx(g_shift_hook);
                g_shift_hook = nullptr;
                g_shift_hook_thread_id = 0;
                WriteStructuralEvent("shift_hook_uninstalled");
            }
        }
    }
    if (was_current && released_service) {
        released_service->HideLanguageBarForSupersededFocus();
    }
    unsigned long orphaned_references = service->TakeOrphanedFocusReferences();
    while (orphaned_references > 0) {
        --orphaned_references;
        service->Release();
    }
    if (released_service) {
        released_service->Release();
    }
}

LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
    if (code == HC_ACTION && lparam != 0) {
        const auto* info = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
        const bool key_down =
            wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
        const bool key_up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
        if (IsShiftKey(info->vkCode)) {
            if (key_down) {
                const bool was_down =
                    g_hook_shift_down.load(std::memory_order_acquire);
                if (!was_down) {
                    ClearMouseButtonTransitionBits();
                    const unsigned long generation =
                        static_cast<unsigned long>(
                            g_published_focus_generation.load(
                                std::memory_order_acquire));
                    const unsigned long token = generation == 0
                                                    ? 0
                                                    : NextNonzeroSequence(
                                                          &g_shift_sequence);
                    const bool modified = IsShortcutModifierDown();
                    const bool mouse_or_capture = IsMouseButtonDown();
                    const ShiftRejectionReason initial_rejection =
                        modified
                            ? ShiftRejectionReason::Modified
                            : (mouse_or_capture
                                   ? ShiftRejectionReason::MouseOrCapture
                                   : ShiftRejectionReason::None);
                    const bool initially_consumed =
                        initial_rejection != ShiftRejectionReason::None;
                    const unsigned long long snapshot =
                        PackShiftSnapshot(token, generation);
                    if (token != 0) {
                        const size_t history_index =
                            token % kShiftCorrelationCapacity;
                        g_hook_shift_history[history_index].store(
                            0, std::memory_order_release);
                        g_hook_shift_history_time[history_index].store(
                            info->time, std::memory_order_relaxed);
                        g_hook_shift_history_consumed[history_index].store(
                            initially_consumed,
                            std::memory_order_relaxed);
                        g_hook_shift_history[history_index].store(
                            snapshot, std::memory_order_release);
                    }
                    g_hook_shift_snapshot.store(snapshot,
                                                std::memory_order_release);
                    g_hook_shift_rejection_reason.store(
                        initial_rejection, std::memory_order_release);
                    g_hook_shift_consumed.store(initially_consumed,
                                                std::memory_order_release);
                    // Publish "down" last so TSF cannot observe a pressed
                    // state paired with an uninitialized token/generation.
                    g_hook_shift_down.store(true, std::memory_order_release);
                } else {
                    SetHookShiftRejectionIfNone(
                        ShiftRejectionReason::Repeat);
                    g_hook_shift_consumed.store(true,
                                                std::memory_order_release);
                    MarkCurrentShiftHookTokenConsumed();
                }
            } else if (key_up) {
                const bool was_down = g_hook_shift_down.exchange(
                    false, std::memory_order_acq_rel);
                const bool consumed = g_hook_shift_consumed.exchange(
                    false, std::memory_order_acq_rel);
                const unsigned long long snapshot =
                    g_hook_shift_snapshot.exchange(0,
                                                   std::memory_order_acq_rel);
                const unsigned long token = ShiftSnapshotToken(snapshot);
                const unsigned long generation =
                    ShiftSnapshotGeneration(snapshot);
                const bool mouse_gesture = MouseButtonTransitionOrDown();
                ShiftRejectionReason rejection =
                    g_hook_shift_rejection_reason.exchange(
                        ShiftRejectionReason::None,
                        std::memory_order_acq_rel);
                if (mouse_gesture &&
                    rejection == ShiftRejectionReason::None) {
                    rejection = ShiftRejectionReason::MouseOrCapture;
                }
                if (IsShortcutModifierDown() &&
                    rejection == ShiftRejectionReason::None) {
                    rejection = ShiftRejectionReason::Modified;
                }
                if (consumed && rejection == ShiftRejectionReason::None) {
                    rejection = ShiftRejectionReason::Consumed;
                }
                if (rejection != ShiftRejectionReason::None) {
                    MarkShiftHookSnapshotConsumed(snapshot);
                }
                if (was_down && token != 0 && generation != 0) {
                    const HWND target = g_shift_hook_dispatcher.load(
                        std::memory_order_acquire);
                    if (target) {
                        const UINT dispatch_message =
                            rejection == ShiftRejectionReason::None
                                ? kShiftHookToggleMessage
                                : ShiftHookRejectionMessage(rejection);
                        (void)PostMessageW(
                            target, dispatch_message,
                            static_cast<WPARAM>(token),
                            static_cast<LPARAM>(generation));
                    }
                }
            }
        } else if (key_down &&
                   g_hook_shift_down.load(std::memory_order_acquire)) {
            SetHookShiftRejectionIfNone(
                IsShortcutModifierKey(info->vkCode)
                    ? ShiftRejectionReason::Modified
                    : ShiftRejectionReason::Consumed);
            g_hook_shift_consumed.store(true, std::memory_order_release);
            MarkCurrentShiftHookTokenConsumed();
        }
    }
    return CallNextHookEx(nullptr, code, wparam, lparam);
}

class ClassFactory final : public IClassFactory {
public:
    ClassFactory() : ref_(1) {
        DllAddRef();
    }

    ~ClassFactory() {
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_IClassFactory)) {
            *object = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (outer) {
            return CLASS_E_NOAGGREGATION;
        }
        TextService* service = new (std::nothrow) TextService();
        if (!service) {
            return E_OUTOFMEMORY;
        }
        const HRESULT hr = service->QueryInterface(iid, object);
        service->Release();
        return hr;
    }

    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) {
            DllAddRef();
        } else {
            DllRelease();
        }
        return S_OK;
    }

private:
    std::atomic<long> ref_;
};

std::wstring GuidString(REFGUID guid) {
    wchar_t buffer[64] = {};
    StringFromGUID2(guid, buffer, ARRAYSIZE(buffer));
    return buffer;
}

HRESULT SetRegString(HKEY root, const std::wstring& path, const wchar_t* name,
                     const std::wstring& value) {
    HKEY key = nullptr;
    DWORD disposition = 0;
    LSTATUS status =
        RegCreateKeyExW(root, path.c_str(), 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_WRITE, nullptr, &key, &disposition);
    if (status != ERROR_SUCCESS) {
        return HRESULT_FROM_WIN32(status);
    }
    status = RegSetValueExW(key, name, 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(value.c_str()),
                            static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    return HRESULT_FROM_WIN32(status);
}

void DeleteRegTree(HKEY root, const std::wstring& path) {
    RegDeleteTreeW(root, path.c_str());
}

HRESULT RegisterComServer() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(g_instance, module_path, ARRAYSIZE(module_path))) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    const std::wstring clsid_path = L"CLSID\\" + GuidString(kTextServiceClsid);
    HRESULT hr = SetRegString(HKEY_CLASSES_ROOT, clsid_path, nullptr, kTextServiceDesc);
    if (FAILED(hr)) {
        return hr;
    }
    hr = SetRegString(HKEY_CLASSES_ROOT, clsid_path + L"\\InprocServer32", nullptr,
                      module_path);
    if (FAILED(hr)) {
        return hr;
    }
    return SetRegString(HKEY_CLASSES_ROOT, clsid_path + L"\\InprocServer32",
                        L"ThreadingModel", kThreadingModel);
}

void UnregisterComServer() {
    DeleteRegTree(HKEY_CLASSES_ROOT, L"CLSID\\" + GuidString(kTextServiceClsid));
}

HRESULT RegisterProfiles() {
    ITfInputProcessorProfileMgr* profile_mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfileMgr,
                                  reinterpret_cast<void**>(&profile_mgr));
    if (FAILED(hr)) {
        return hr;
    }
    wchar_t module_path[MAX_PATH] = {};
    GetModuleFileNameW(g_instance, module_path, ARRAYSIZE(module_path));
    hr = profile_mgr->RegisterProfile(
        kTextServiceClsid, kTextServiceLangId, kProfileGuid, kTextServiceDesc,
        static_cast<ULONG>(wcslen(kTextServiceDesc)), module_path,
        static_cast<ULONG>(wcslen(module_path)), 0, 0, 0, TRUE, 0);
    profile_mgr->Release();
    return hr;
}

void UnregisterProfiles() {
    ITfInputProcessorProfileMgr* profile_mgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr,
                                   reinterpret_cast<void**>(&profile_mgr)))) {
        profile_mgr->UnregisterProfile(kTextServiceClsid, kTextServiceLangId,
                                       kProfileGuid, 0);
        profile_mgr->Release();
    }
}

HRESULT RegisterCategories() {
    ITfCategoryMgr* category_mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfCategoryMgr,
                                  reinterpret_cast<void**>(&category_mgr));
    if (FAILED(hr)) {
        return hr;
    }
    const GUID categories[] = {
        GUID_TFCAT_TIP_KEYBOARD,
        GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
        GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
        GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
    };
    for (const GUID& category : categories) {
        hr = category_mgr->RegisterCategory(kTextServiceClsid, category,
                                            kTextServiceClsid);
        if (FAILED(hr)) {
            break;
        }
    }
    category_mgr->Release();
    return hr;
}

void UnregisterCategories() {
    ITfCategoryMgr* category_mgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                   reinterpret_cast<void**>(&category_mgr)))) {
        const GUID categories[] = {
            GUID_TFCAT_TIP_KEYBOARD,
            GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
            GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
            GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
        };
        for (const GUID& category : categories) {
            category_mgr->UnregisterCategory(kTextServiceClsid, category,
                                             kTextServiceClsid);
        }
        category_mgr->Release();
    }
}

}  // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void*) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_instance = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

extern "C" HRESULT STDAPICALLTYPE DllGetClassObject(REFCLSID clsid, REFIID iid,
                                                     void** object) {
    if (!object) {
        return E_INVALIDARG;
    }
    *object = nullptr;
    if (!IsEqualCLSID(clsid, kTextServiceClsid)) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    ClassFactory* factory = new (std::nothrow) ClassFactory();
    if (!factory) {
        return E_OUTOFMEMORY;
    }
    const HRESULT hr = factory->QueryInterface(iid, object);
    factory->Release();
    return hr;
}

extern "C" HRESULT STDAPICALLTYPE DllCanUnloadNow() {
    return g_dll_refs.load() == 0 ? S_OK : S_FALSE;
}

extern "C" HRESULT STDAPICALLTYPE DllRegisterServer() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(hr);
    if (hr == RPC_E_CHANGED_MODE) {
        hr = S_OK;
    }
    if (SUCCEEDED(hr)) {
        hr = RegisterComServer();
    }
    if (SUCCEEDED(hr)) {
        hr = RegisterProfiles();
    }
    if (SUCCEEDED(hr)) {
        hr = RegisterCategories();
    }
    if (FAILED(hr)) {
        UnregisterCategories();
        UnregisterProfiles();
        UnregisterComServer();
    }
    if (should_uninit) {
        CoUninitialize();
    }
    return hr;
}

extern "C" HRESULT STDAPICALLTYPE DllUnregisterServer() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(hr);
    if (hr == RPC_E_CHANGED_MODE) {
        hr = S_OK;
    }
    UnregisterCategories();
    UnregisterProfiles();
    UnregisterComServer();
    if (should_uninit) {
        CoUninitialize();
    }
    return S_OK;
}
