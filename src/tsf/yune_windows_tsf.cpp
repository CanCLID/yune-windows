#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <msctf.h>
#include <strsafe.h>

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <new>
#include <string>
#include <string_view>
#include <vector>

#include "../candidate_window/yune_windows_candidate_window.h"

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
constexpr ULONGLONG kLoneShiftDoubleToggleGuardMs = 250;
constexpr UINT kShiftHookToggleMessage = WM_APP + 0x5a;
constexpr const wchar_t* kShiftHookWindowClass = L"YuneWindowsShiftHookWindow";
constexpr int kCandidatePageSize = 5;
constexpr LPARAM kKeyWasDownMask = 0x40000000;

enum class RefreshStateMode {
    AllowLaunch,
    ExistingServerOnly,
};

class TextService;

HINSTANCE g_instance = nullptr;
std::atomic<long> g_dll_refs = 0;
std::atomic<unsigned long long> g_last_server_launch_attempt_ms = 0;
std::atomic<unsigned long> g_structural_event_sequence = 0;
std::atomic<bool> g_server_warmup_inflight = false;
std::atomic<bool> g_hook_shift_down = false;
std::atomic<bool> g_hook_shift_consumed = false;
std::atomic<unsigned long long> g_last_lone_shift_toggle_ms = 0;
std::mutex g_structural_log_mutex;
std::mutex g_shift_hook_mutex;
HHOOK g_shift_hook = nullptr;
HWND g_shift_hook_window = nullptr;
DWORD g_shift_hook_window_thread_id = 0;
TextService* g_focused_text_service = nullptr;

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
bool TryAcquireLoneShiftToggle();
void RegisterFocusedTextService(TextService* service);
LRESULT CALLBACK ShiftHookWindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam);
LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam);

void WriteStructuralEvent(const char* event_name, int buffer_length = -1,
                          int candidate_count = -1) {
    try {
        const std::filesystem::path module_dir = ModuleDirectory();
        if (module_dir.empty()) {
            return;
        }
        const std::filesystem::path log_dir = module_dir / L"logs";
        std::filesystem::create_directories(log_dir);

        std::lock_guard<std::mutex> lock(g_structural_log_mutex);
        std::ofstream log(log_dir / L"tsf-events.log", std::ios::app);
        if (!log) {
            return;
        }
        log << "event=" << event_name
            << " sequence=" << ++g_structural_event_sequence;
        if (buffer_length >= 0) {
            log << " buffer_length=" << buffer_length;
        }
        if (candidate_count >= 0) {
            log << " candidate_count=" << candidate_count;
        }
        log << "\n";
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

bool JsonHasArrayValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":[";
    return json.find(needle) != std::string::npos;
}

struct ImeState {
    bool present = false;
    std::wstring schema_id;
    bool ascii_mode = false;
    bool full_shape = false;
    std::wstring output_standard = L"hong_kong_traditional";
};

struct ServerResponse {
    bool ok = false;
    ImeState state;
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
    const std::string schema_id = JsonStringValue(json, "schema_id");
    const std::string output_standard = JsonStringValue(json, "output_standard");
    bool ascii_mode = false;
    bool full_shape = false;
    if (schema_id.empty() || output_standard.empty() ||
        !JsonBoolValue(json, "ascii_mode", &ascii_mode) ||
        !JsonBoolValue(json, "full_shape", &full_shape)) {
        return state;
    }
    state.present = true;
    state.schema_id = Widen(schema_id);
    state.ascii_mode = ascii_mode;
    state.full_shape = full_shape;
    state.output_standard = Widen(output_standard);
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

ServerResponse QueryServer(
    const std::wstring& input, bool commit,
    RefreshStateMode mode = RefreshStateMode::AllowLaunch,
    DWORD timeout_ms = kServerQueryTimeoutMs) {
    auto wait_for_pipe_io = [](HANDLE pipe, OVERLAPPED& overlapped,
                               DWORD& transferred,
                               DWORD timeout_ms) -> bool {
        const DWORD wait = WaitForSingleObject(overlapped.hEvent,
                                               timeout_ms);
        if (wait != WAIT_OBJECT_0) {
            CancelIo(pipe);
            WaitForSingleObject(overlapped.hEvent, 1000);
            return false;
        }
        return GetOverlappedResult(pipe, &overlapped, &transferred, FALSE) == TRUE;
    };

    auto write_pipe = [&](HANDLE pipe, const std::string& request,
                          DWORD& written) -> bool {
        HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!event) {
            return false;
        }
        OVERLAPPED overlapped = {};
        overlapped.hEvent = event;
        const DWORD request_size = static_cast<DWORD>(request.size());
        const BOOL started =
            WriteFile(pipe, request.data(), request_size, nullptr, &overlapped);
        bool ok = false;
        if (started) {
            ok = GetOverlappedResult(pipe, &overlapped, &written, FALSE) == TRUE;
        } else if (GetLastError() == ERROR_IO_PENDING) {
            ok = wait_for_pipe_io(pipe, overlapped, written, timeout_ms);
        }
        CloseHandle(event);
        return ok && written == request_size;
    };

    auto read_pipe = [&](HANDLE pipe, char* response, DWORD response_size,
                         DWORD& read) -> bool {
        HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!event) {
            return false;
        }
        OVERLAPPED overlapped = {};
        overlapped.hEvent = event;
        const BOOL started =
            ReadFile(pipe, response, response_size, nullptr, &overlapped);
        bool ok = false;
        if (started) {
            ok = GetOverlappedResult(pipe, &overlapped, &read, FALSE) == TRUE;
        } else if (GetLastError() == ERROR_IO_PENDING) {
            ok = wait_for_pipe_io(pipe, overlapped, read, timeout_ms);
        }
        CloseHandle(event);
        return ok && read > 0;
    };

    auto connect_pipe = []() -> HANDLE {
        return CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                           OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    };

    HANDLE pipe = connect_pipe();
    const DWORD reconnect_wait_ms =
        timeout_ms < kServerPipeReconnectWaitMs ? timeout_ms
                                                : kServerPipeReconnectWaitMs;
    if (pipe == INVALID_HANDLE_VALUE) {
        const DWORD connect_error = GetLastError();
        if (connect_error == ERROR_PIPE_BUSY) {
            WriteStructuralEvent("server_query_pipe_busy");
            if (WaitForSharedServerPipe(reconnect_wait_ms)) {
                pipe = connect_pipe();
            }
        } else if (connect_error == ERROR_FILE_NOT_FOUND) {
            if (WaitForSharedServerPipe(reconnect_wait_ms)) {
                pipe = connect_pipe();
            }
            if (pipe == INVALID_HANDLE_VALUE &&
                mode == RefreshStateMode::AllowLaunch &&
                RequestSharedServerLaunch()) {
                pipe = connect_pipe();
            }
        }
    }
    if (pipe == INVALID_HANDLE_VALUE) {
        WriteStructuralEvent("server_query_connect_failed");
        return ServerQueryFailure(input);
    }

    DWORD pipe_mode = PIPE_READMODE_MESSAGE;
    if (!SetNamedPipeHandleState(pipe, &pipe_mode, nullptr, nullptr)) {
        CloseHandle(pipe);
        WriteStructuralEvent("server_query_connect_failed");
        return ServerQueryFailure(input);
    }

    std::string request = "input=" + Narrow(input) + "\n";
    request += commit ? "commit=1\n.\n" : "commit=0\n.\n";
    DWORD written = 0;
    if (!write_pipe(pipe, request, written)) {
        CloseHandle(pipe);
        WriteStructuralEvent("server_query_write_failed");
        return ServerQueryFailure(input);
    }

    char response[65536] = {};
    DWORD read = 0;
    if (!read_pipe(pipe, response, sizeof(response) - 1, read)) {
        CloseHandle(pipe);
        WriteStructuralEvent("server_query_read_timeout");
        return ServerQueryFailure(input);
    }
    CloseHandle(pipe);

    const std::string json(response, read);
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

ServerResponse QueryServerOperation(
    const std::string& request,
    RefreshStateMode mode = RefreshStateMode::AllowLaunch,
    DWORD timeout_ms = kServerQueryTimeoutMs) {
    char response[65536] = {};
    DWORD read = 0;
    const int max_attempts = mode == RefreshStateMode::AllowLaunch ? 3 : 1;
    const DWORD reconnect_wait_ms =
        timeout_ms < kServerPipeReconnectWaitMs ? timeout_ms
                                                : kServerPipeReconnectWaitMs;
    for (int attempt = 0; attempt < max_attempts; ++attempt) {
        if (CallNamedPipeW(kPipeName, const_cast<char*>(request.data()),
                           static_cast<DWORD>(request.size()), response,
                           sizeof(response) - 1, &read, timeout_ms)) {
            const std::string json(response, read);
            if (!JsonBoolTrueValue(json, "ready")) {
                WriteStructuralEvent("server_query_invalid_response");
                return {};
            }
            ServerResponse result;
            result.ok = true;
            result.state = JsonImeState(json);
            result.schemas = JsonSchemaIds(json);
            return result;
        }

        const DWORD error = GetLastError();
        if (error == ERROR_FILE_NOT_FOUND) {
            if (mode == RefreshStateMode::ExistingServerOnly) {
                break;
            }
            if (!WaitForSharedServerPipe(reconnect_wait_ms) &&
                !RequestSharedServerLaunch()) {
                break;
            }
            continue;
        }
        if (error == ERROR_PIPE_BUSY) {
            WriteStructuralEvent("server_query_pipe_busy");
            if (WaitForSharedServerPipe(reconnect_wait_ms)) {
                continue;
            }
        }
        break;
    }
    WriteStructuralEvent("server_query_failed");
    return {};
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

class TextService final : public ITfTextInputProcessorEx, public ITfKeyEventSink {
public:
    TextService() : ref_(1) {
        language_bar_.SetClickHandler(&TextService::LanguageBarClickThunk, this);
        DllAddRef();
    }

    ~TextService() {
        Deactivate();
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
                                !buffer_.empty() ||
                                !candidate_.empty() ||
                                !last_candidates_.empty();
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
        RegisterFocusedTextService(nullptr);
        ClearShiftState();
        if (was_active) {
            WriteStructuralEvent("profile_deactivate",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
        }
        buffer_.clear();
        candidate_.clear();
        last_candidates_.clear();
        candidate_page_index_ = 0;
        candidate_window_.Hide();
        language_bar_.Hide();
        return S_OK;
    }

    STDMETHODIMP OnSetFocus(BOOL focused) override {
        if (!focused) {
            focused_ = false;
            RegisterFocusedTextService(nullptr);
            ClearShiftState();
            WriteStructuralEvent("focus_lost", static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            buffer_.clear();
            candidate_.clear();
            last_candidates_.clear();
            candidate_page_index_ = 0;
            candidate_window_.Hide();
            language_bar_.Hide();
        } else {
            focused_ = true;
            RegisterFocusedTextService(this);
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
                shift_consumed_ = IsShortcutModifierDown() || IsMouseButtonDown();
            }
            return S_OK;
        }
        if (shift_down_) {
            shift_consumed_ = true;
        }
        const bool shift_pressed = IsShiftPressed();
        if (!ShouldHandleKeyDown(key, shift_pressed)) {
            return S_OK;
        }
        if (!shift_pressed &&
            ((key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z'))) {
            buffer_.push_back(LowerAscii(key));
            ServerResponse response = QueryInput(buffer_, false);
            *eaten = TRUE;
            if (!response.ok) {
                candidate_.clear();
                last_candidates_.clear();
                candidate_page_index_ = 0;
                candidate_window_.Hide();
                return S_OK;
            }
            last_candidates_ = response.candidates;
            candidate_page_index_ = 0;
            candidate_ = last_candidates_.empty() ? std::wstring{}
                                                  : last_candidates_[0].text;
            const int buffer_length = static_cast<int>(buffer_.size());
            const int candidate_count = static_cast<int>(last_candidates_.size());
            WriteStructuralEvent("key_down", buffer_length, candidate_count);
            if (ShowCandidates(context, last_candidates_)) {
                WriteStructuralEvent("candidate_update", buffer_length,
                                     candidate_count);
            }
            return S_OK;
        }
        if (key == VK_BACK) {
            if (!buffer_.empty()) {
                buffer_.pop_back();
                if (buffer_.empty()) {
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_page_index_ = 0;
                    WriteStructuralEvent("key_backspace", 0, 0);
                    candidate_window_.Hide();
                    *eaten = TRUE;
                    return S_OK;
                }
                ServerResponse response = QueryInput(buffer_, false);
                if (!response.ok) {
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_page_index_ = 0;
                    candidate_window_.Hide();
                    *eaten = TRUE;
                    return S_OK;
                }
                last_candidates_ = response.candidates;
                candidate_page_index_ = 0;
                candidate_ = last_candidates_.empty() ? std::wstring{}
                                                      : last_candidates_[0].text;
                const int buffer_length = static_cast<int>(buffer_.size());
                const int candidate_count =
                    static_cast<int>(last_candidates_.size());
                WriteStructuralEvent("key_backspace", buffer_length,
                                     candidate_count);
                if (ShowCandidates(context, last_candidates_)) {
                    WriteStructuralEvent("candidate_update", buffer_length,
                                         candidate_count);
                }
                *eaten = TRUE;
            } else {
                last_candidates_.clear();
                candidate_page_index_ = 0;
                candidate_window_.Hide();
            }
            return S_OK;
        }
        if (key == VK_ESCAPE) {
            WriteStructuralEvent("composition_cancel",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            buffer_.clear();
            candidate_.clear();
            last_candidates_.clear();
            candidate_page_index_ = 0;
            candidate_window_.Hide();
            *eaten = TRUE;
            return S_OK;
        }
        if (!shift_pressed &&
            (key == VK_NEXT || key == VK_PRIOR || key == VK_OEM_MINUS ||
             key == VK_OEM_PLUS) && !buffer_.empty()) {
            *eaten = TRUE;
            const int page_delta =
                (key == VK_NEXT || key == VK_OEM_PLUS) ? 1 : -1;
            PageCandidateWindow(context, page_delta);
            return S_OK;
        }
        if (!shift_pressed && key >= L'1' && key <= L'9' && !buffer_.empty()) {
            *eaten = TRUE;
            const size_t index = static_cast<size_t>(
                yune_windows::CandidatePageStartIndex(candidate_page_index_,
                                                      kCandidatePageSize) +
                static_cast<int>(key - L'1'));
            if (index < last_candidates_.size()) {
                WriteStructuralEvent("commit_request",
                                     static_cast<int>(buffer_.size()),
                                     static_cast<int>(last_candidates_.size()));
                if (CommitText(context, last_candidates_[index].text)) {
                    buffer_.clear();
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_page_index_ = 0;
                    candidate_window_.Hide();
                }
            }
            return S_OK;
        }
        if (IsPunctuationKey(key, shift_pressed)) {
            const bool was_composing = !buffer_.empty();
            if (CommitCompositionForPunctuation(context, key, shift_pressed) ||
                was_composing) {
                *eaten = TRUE;
            }
            return S_OK;
        }
        if (key == VK_RETURN && !buffer_.empty()) {
            *eaten = TRUE;
            (void)CommitRawBuffer(context);
            return S_OK;
        }
        if (key == VK_SPACE && !buffer_.empty()) {
            *eaten = TRUE;
            ServerResponse response = QueryInput(buffer_, true);
            if (!response.ok) {
                *eaten = TRUE;
                return S_OK;
            }
            std::wstring commit = response.commit_text;
            if (commit.empty()) {
                commit = candidate_;
            }
            if (!commit.empty()) {
                WriteStructuralEvent("commit_request",
                                     static_cast<int>(buffer_.size()),
                                     static_cast<int>(last_candidates_.size()));
                if (CommitText(context, commit)) {
                    buffer_.clear();
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_page_index_ = 0;
                    candidate_window_.Hide();
                }
            }
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
            if (shift_down_ && !shift_consumed_ &&
                !IsShortcutModifierDown() && !IsMouseButtonDown() &&
                TryAcquireLoneShiftToggle()) {
                ToggleBoolState("ascii_mode", context);
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

    void HandleDeferredLoneShiftToggle() {
        if (!focused_) {
            return;
        }
        ClearShiftState();
        ToggleBoolState("ascii_mode", nullptr);
    }

private:
    static void LanguageBarClickThunk(yune_windows::LanguageBarSegment segment,
                                      void* context) {
        auto* service = static_cast<TextService*>(context);
        if (service) {
            service->HandleLanguageBarClick(segment);
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

    void ReconcileState(const ServerResponse& response, ITfContext* context) {
        if (!response.ok || !response.state.present) {
            return;
        }
        state_ = response.state;
        UpdateInputModeCompartment();
        UpdateLanguageBar(context);
    }

    void RefreshStateFromServer(
        ITfContext* context,
        RefreshStateMode mode = RefreshStateMode::AllowLaunch) {
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

    void UpdateLanguageBar(ITfContext* context) {
        if (!focused_) {
            language_bar_.Hide();
            return;
        }
        if (!state_.present) {
            language_bar_.Hide();
            return;
        }

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

        yune_windows::LanguageBarState bar_state;
        bar_state.ascii_mode = state_.ascii_mode;
        bar_state.full_shape = state_.full_shape;
        bar_state.output_standard = state_.output_standard;
        bar_state.schema_id = state_.schema_id;
        bar_state.owner = anchor_result.owner;
        bar_state.dpi = anchor_result.dpi;
        if (anchor_result.has_anchor) {
            bar_state.anchor = anchor_result.anchor;
            bar_state.anchor.top =
                bar_state.anchor.top > 40 ? bar_state.anchor.top - 40 : 0;
            bar_state.anchor.bottom = bar_state.anchor.top + 34;
        }
        (void)language_bar_.Update(bar_state, true);
    }

    void ClearCompositionState() {
        buffer_.clear();
        candidate_.clear();
        last_candidates_.clear();
        candidate_page_index_ = 0;
        candidate_window_.Hide();
    }

    void ClearShiftState() {
        shift_down_ = false;
        shift_consumed_ = false;
    }

    void CancelLoneShiftToggle() {
        shift_consumed_ = true;
    }

    bool CommitOrClearCompositionBeforeStateChange(ITfContext* context) {
        if (buffer_.empty()) {
            return true;
        }

        const int buffer_length = static_cast<int>(buffer_.size());
        const int candidate_count = static_cast<int>(last_candidates_.size());
        bool committed = false;
        if (context) {
            ServerResponse response = QueryInput(buffer_, true);
            if (response.ok) {
                std::wstring commit = response.commit_text;
                if (commit.empty()) {
                    commit = candidate_;
                }
                if (!commit.empty()) {
                    WriteStructuralEvent("commit_request", buffer_length,
                                         candidate_count);
                    committed = CommitText(context, commit);
                }
            }
        }

        WriteStructuralEvent(committed ? "composition_flush_commit"
                                       : "composition_flush_clear",
                             buffer_length, candidate_count);
        ClearCompositionState();
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
        payload += "\n.\n";
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (!response.ok) {
            RequestSharedServerWarmupAsync();
        }
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
        payload += "\n.\n";
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (!response.ok) {
            RequestSharedServerWarmupAsync();
        }
    }

    void SetOutputStandard(const std::wstring& standard, ITfContext* context) {
        CommitOrClearCompositionBeforeStateChange(context);
        std::string payload =
            "op=set-option\nname=output_standard\nvalue=" + Narrow(standard) +
            "\n.\n";
        ServerResponse response =
            QueryOperation(payload, context, RefreshStateMode::ExistingServerOnly,
                           kServerKeyPathQueryTimeoutMs);
        if (!response.ok) {
            RequestSharedServerWarmupAsync();
        }
    }

    void CycleSchema(ITfContext* context) {
        SelectSchema(NextSchemaId(), context);
    }

    void CycleOutputStandard(ITfContext* context) {
        SetOutputStandard(NextOutputStandard(), context);
    }

    void HandleLanguageBarClick(yune_windows::LanguageBarSegment segment) {
        switch (segment) {
            case yune_windows::LanguageBarSegment::AsciiMode:
                ToggleBoolState("ascii_mode", nullptr);
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
        }
    }

    bool ShouldHandleKeyDown(WPARAM key, bool shift_pressed) const {
        if (IsShortcutModifierDown()) {
            return false;
        }
        if (state_.present && state_.ascii_mode && buffer_.empty()) {
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
            return !buffer_.empty();
        }
        if (!shift_pressed && key >= L'1' && key <= L'9') {
            return !buffer_.empty();
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

    bool CommitRawBuffer(ITfContext* context) {
        if (buffer_.empty()) {
            return true;
        }
        const int buffer_length = static_cast<int>(buffer_.size());
        const int candidate_count = static_cast<int>(last_candidates_.size());
        WriteStructuralEvent("raw_commit_request", buffer_length,
                             candidate_count);
        if (!CommitText(context, buffer_)) {
            return false;
        }
        buffer_.clear();
        candidate_.clear();
        last_candidates_.clear();
        candidate_page_index_ = 0;
        candidate_window_.Hide();
        return true;
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
        if (!buffer_.empty()) {
            ServerResponse composition_response = QueryInput(buffer_, true);
            if (!composition_response.ok) {
                return false;
            }
            std::wstring composition_commit = composition_response.commit_text;
            if (composition_commit.empty()) {
                composition_commit = candidate_;
            }
            if (composition_commit.empty()) {
                return false;
            }

            WriteStructuralEvent("commit_request",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            if (!CommitText(context, composition_commit)) {
                return false;
            }
            committed_composition = true;
            buffer_.clear();
            candidate_.clear();
            last_candidates_.clear();
            candidate_page_index_ = 0;
            candidate_window_.Hide();
        }

        WriteStructuralEvent("punctuation_commit", 0, 0);
        if (CommitText(context, punctuation_response.commit_text)) {
            candidate_window_.Hide();
            return true;
        }
        return committed_composition;
    }

    bool PageCandidateWindow(ITfContext* context, int delta) {
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
        candidate_page_index_ = next_page;
        const int page_start = yune_windows::CandidatePageStartIndex(
            candidate_page_index_, kCandidatePageSize);
        if (page_start >= 0 &&
            page_start < static_cast<int>(last_candidates_.size())) {
            candidate_ = last_candidates_[static_cast<size_t>(page_start)].text;
        }
        WriteStructuralEvent("candidate_page",
                             static_cast<int>(buffer_.size()),
                             static_cast<int>(last_candidates_.size()));
        return ShowCandidates(context, last_candidates_);
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
    std::wstring buffer_;
    std::wstring candidate_;
    std::vector<yune_windows::CandidateWindowCandidate> last_candidates_;
    int candidate_page_index_ = 0;
    ImeState state_;
    bool shift_down_ = false;
    bool shift_consumed_ = false;
    bool focused_ = false;
    yune_windows::NativeCandidateWindow candidate_window_;
    yune_windows::LanguageBarWindow language_bar_;
};

bool TryAcquireLoneShiftToggle() {
    const ULONGLONG now = GetTickCount64();
    unsigned long long last = g_last_lone_shift_toggle_ms.load();
    while (true) {
        if (last != 0 && now - last < kLoneShiftDoubleToggleGuardMs) {
            return false;
        }
        if (g_last_lone_shift_toggle_ms.compare_exchange_weak(last, now)) {
            return true;
        }
    }
}

TextService* AddRefFocusedTextService() {
    std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
    if (!g_focused_text_service) {
        return nullptr;
    }
    g_focused_text_service->AddRef();
    return g_focused_text_service;
}

bool EnsureShiftHookWindowClassRegistered() {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = ShiftHookWindowProc;
    wc.hInstance = g_instance;
    wc.lpszClassName = kShiftHookWindowClass;
    if (RegisterClassExW(&wc) || GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
        return true;
    }
    WriteStructuralEvent("shift_hook_window_failed");
    return false;
}

bool EnsureShiftHookWindowForCurrentThreadLocked() {
    const DWORD current_thread = GetCurrentThreadId();
    if (g_shift_hook_window &&
        g_shift_hook_window_thread_id == current_thread &&
        IsWindow(g_shift_hook_window)) {
        return true;
    }
    if (!EnsureShiftHookWindowClassRegistered()) {
        return false;
    }
    if (g_shift_hook_window &&
        g_shift_hook_window_thread_id == current_thread) {
        DestroyWindow(g_shift_hook_window);
        g_shift_hook_window = nullptr;
        g_shift_hook_window_thread_id = 0;
    }
    HWND window = CreateWindowExW(0, kShiftHookWindowClass,
                                  L"Yune Windows Shift Hook",
                                  0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                  g_instance, nullptr);
    if (!window) {
        WriteStructuralEvent("shift_hook_window_failed");
        return false;
    }
    g_shift_hook_window = window;
    g_shift_hook_window_thread_id = current_thread;
    return true;
}

bool EnsureShiftHookInstalledLocked() {
    if (g_shift_hook) {
        return true;
    }
    g_shift_hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                                     g_instance, 0);
    if (!g_shift_hook) {
        WriteStructuralEvent("shift_hook_install_failed");
        return false;
    }
    WriteStructuralEvent("shift_hook_installed");
    return true;
}

void RegisterFocusedTextService(TextService* service) {
    TextService* old_service = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
        if (service == g_focused_text_service) {
            return;
        }
        if (service) {
            if (!EnsureShiftHookWindowForCurrentThreadLocked() ||
                !EnsureShiftHookInstalledLocked()) {
                return;
            }
            service->AddRef();
        }
        old_service = g_focused_text_service;
        g_focused_text_service = service;
        if (!service) {
            g_hook_shift_down.store(false);
            g_hook_shift_consumed.store(false);
            if (g_shift_hook) {
                UnhookWindowsHookEx(g_shift_hook);
                g_shift_hook = nullptr;
                WriteStructuralEvent("shift_hook_uninstalled");
            }
            if (g_shift_hook_window &&
                g_shift_hook_window_thread_id == GetCurrentThreadId()) {
                DestroyWindow(g_shift_hook_window);
                g_shift_hook_window = nullptr;
                g_shift_hook_window_thread_id = 0;
            }
        }
    }
    if (old_service) {
        old_service->Release();
    }
}

LRESULT CALLBACK ShiftHookWindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    if (message == kShiftHookToggleMessage) {
        TextService* service = AddRefFocusedTextService();
        if (service) {
            if (TryAcquireLoneShiftToggle()) {
                service->HandleDeferredLoneShiftToggle();
            }
            service->Release();
        }
        return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
    if (code == HC_ACTION && lparam != 0) {
        const auto* info = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
        const bool key_down =
            wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
        const bool key_up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
        if (IsShiftKey(info->vkCode)) {
            if (key_down) {
                const bool was_down = g_hook_shift_down.exchange(true);
                if (!was_down) {
                    g_hook_shift_consumed.store(IsShortcutModifierDown() ||
                                                IsMouseButtonDown());
                }
            } else if (key_up) {
                const bool was_down = g_hook_shift_down.exchange(false);
                const bool consumed = g_hook_shift_consumed.exchange(false);
                if (was_down && !consumed && !IsShortcutModifierDown() &&
                    !IsMouseButtonDown()) {
                    HWND target = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(g_shift_hook_mutex);
                        target = g_shift_hook_window;
                    }
                    if (target) {
                        PostMessageW(target, kShiftHookToggleMessage, 0, 0);
                    }
                }
            }
        } else if (key_down && g_hook_shift_down.load()) {
            g_hook_shift_consumed.store(true);
        }
    }
    return CallNextHookEx(g_shift_hook, code, wparam, lparam);
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
