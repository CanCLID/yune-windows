#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <objbase.h>
#include <winternl.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <filesystem>
#include <iostream>
#include <new>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "../candidate_window/yune_windows_candidate_window.h"
#include "yune_windows_ui_strings.h"

namespace {

namespace ui_strings = yune_windows::ui_strings;

constexpr const wchar_t* kPipeName = L"\\\\.\\pipe\\yune-windows-ime";
constexpr const wchar_t* kWindowClassName = L"YuneWindowsSettingsWindow";
constexpr const wchar_t* kPreviewClassName = L"YuneWindowsSettingsPreview";
constexpr const wchar_t* kInstanceMutexName =
    L"Local\\YuneWindowsSettingsInstance";
constexpr int kDesignDpi = 96;
// Controls keep their 96-DPI design coordinates at the top-left. Their current
// bounds end at x=684/y=524; this client floor preserves the intended margins.
constexpr int kDesignClientWidth = 704;
constexpr int kDesignClientHeight = 542;
constexpr int kMinimumDesignClientWidth = 420;
constexpr int kMinimumDesignClientHeight = 320;
constexpr DWORD kSettingsServerTimeoutMs = 750;
constexpr DWORD kSettingsWindowStyle =
    WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX |
    WS_MAXIMIZEBOX | WS_THICKFRAME | WS_HSCROLL | WS_VSCROLL;
constexpr DWORD kSettingsWindowExStyle = WS_EX_APPWINDOW;
constexpr COLORREF kSettingsAccentColor = RGB(8, 117, 190);

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif
#ifndef DWMSBT_MAINWINDOW
#define DWMSBT_MAINWINDOW 2
#endif

constexpr int kButtonAscii = 1001;
constexpr int kButtonFullShape = 1002;
constexpr int kComboOutputStandard = 1003;
constexpr int kComboSchema = 1004;
constexpr int kButtonRefresh = 1005;
constexpr int kComboSkin = 1006;
constexpr int kPreviewToolbar = 1007;

struct ComboItem {
    std::wstring value;
    std::wstring label;
};

struct LayoutEntry {
    HWND hwnd = nullptr;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
};

struct SettingsLayoutMetrics {
    int client_width = 0;
    int client_height = 0;
};

struct InitialWindowPlacement {
    int x = CW_USEDEFAULT;
    int y = CW_USEDEFAULT;
    int width = 0;
    int height = 0;
    UINT dpi = kDesignDpi;
};

struct SettingsState {
    bool ready = false;
    std::wstring boot_id;
    unsigned long long revision = 0;
    std::wstring schema_id = L"jyut6ping3";
    bool ascii_mode = false;
    bool full_shape = false;
    std::wstring output_standard = L"hong_kong_traditional";
    std::wstring toolbar_skin = L"default";
    std::vector<std::wstring> schemas;
    std::vector<std::wstring> skins;
    HWND ascii_button = nullptr;
    HWND full_shape_button = nullptr;
    HWND output_combo = nullptr;
    HWND schema_combo = nullptr;
    HWND skin_combo = nullptr;
    HWND preview_window = nullptr;
    HWND status_label = nullptr;
    UINT dpi = kDesignDpi;
    int scroll_x = 0;
    int scroll_y = 0;
    HFONT ui_font = nullptr;
    std::vector<HWND> controls;
    std::vector<LayoutEntry> layout_entries;
    std::vector<ComboItem> output_items;
    std::vector<ComboItem> schema_items;
    std::vector<ComboItem> skin_items;
    yune_windows::D2DSurface preview_surface;
};

SettingsState g_state;
bool g_layout_smoke = false;
UINT g_layout_smoke_dpi = 0;

UINT EffectiveWindowDpi(HWND hwnd) {
    if (g_layout_smoke && g_layout_smoke_dpi != 0) {
        return g_layout_smoke_dpi;
    }
    const UINT dpi = GetDpiForWindow(hwnd);
    return dpi == 0 ? kDesignDpi : dpi;
}

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi == 0 ? kDesignDpi : dpi),
                  kDesignDpi);
}

SettingsLayoutMetrics CalculateSettingsLayoutMetrics(UINT dpi) {
    return {Scale(kDesignClientWidth, dpi), Scale(kDesignClientHeight, dpi)};
}

bool CalculateWindowSizeForDesignClient(UINT dpi, int design_width,
                                        int design_height, DWORD style,
                                        DWORD ex_style, SIZE* size) {
    if (!size) {
        return false;
    }
    const UINT effective_dpi = dpi == 0 ? kDesignDpi : dpi;
    const SettingsLayoutMetrics layout = {
        Scale(design_width, effective_dpi),
        Scale(design_height, effective_dpi),
    };
    RECT window_rect = {0, 0, layout.client_width, layout.client_height};
    if (!AdjustWindowRectExForDpi(&window_rect, style, FALSE, ex_style,
                                  effective_dpi)) {
        window_rect = {0, 0, layout.client_width, layout.client_height};
        if (!AdjustWindowRectEx(&window_rect, style, FALSE, ex_style)) {
            return false;
        }
    }
    size->cx = window_rect.right - window_rect.left;
    size->cy = window_rect.bottom - window_rect.top;
    // AdjustWindowRectExForDpi does not include scrollbar dimensions.
    if ((style & WS_VSCROLL) != 0) {
        size->cx += GetSystemMetricsForDpi(SM_CXVSCROLL, effective_dpi);
    }
    if ((style & WS_HSCROLL) != 0) {
        size->cy += GetSystemMetricsForDpi(SM_CYHSCROLL, effective_dpi);
    }
    return size->cx > 0 && size->cy > 0;
}

bool CalculateSettingsWindowSize(UINT dpi, DWORD style, DWORD ex_style,
                                 SIZE* size) {
    return CalculateWindowSizeForDesignClient(
        dpi, kDesignClientWidth, kDesignClientHeight, style, ex_style, size);
}

bool CalculateSettingsMinimumWindowSize(UINT dpi, DWORD style,
                                        DWORD ex_style, SIZE* size) {
    return CalculateWindowSizeForDesignClient(
        dpi, kMinimumDesignClientWidth, kMinimumDesignClientHeight, style,
        ex_style, size);
}

UINT DpiForInitialMonitor(HMONITOR monitor, HWND reference_window) {
    if (reference_window && IsWindow(reference_window) &&
        MonitorFromWindow(reference_window, MONITOR_DEFAULTTONEAREST) ==
            monitor) {
        const UINT reference_dpi = GetDpiForWindow(reference_window);
        if (reference_dpi != 0) {
            return reference_dpi;
        }
    }
    const UINT system_dpi = GetDpiForSystem();
    return system_dpi == 0 ? kDesignDpi : system_dpi;
}

RECT ClampWindowRectToWorkArea(const RECT& requested,
                               const RECT& work_area) {
    const LONG work_width =
        std::max(1L, work_area.right - work_area.left);
    const LONG work_height =
        std::max(1L, work_area.bottom - work_area.top);
    const LONG width = std::min(
        std::max(1L, requested.right - requested.left), work_width);
    const LONG height = std::min(
        std::max(1L, requested.bottom - requested.top), work_height);
    RECT clamped = {};
    clamped.left = std::clamp(
        requested.left, work_area.left, work_area.right - width);
    clamped.top = std::clamp(
        requested.top, work_area.top, work_area.bottom - height);
    clamped.right = clamped.left + width;
    clamped.bottom = clamped.top + height;
    return clamped;
}

RECT ClampWindowRectToMonitorWorkArea(const RECT& requested) {
    const HMONITOR monitor = MonitorFromRect(
        &requested, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    if (!monitor || !GetMonitorInfoW(monitor, &monitor_info)) {
        return requested;
    }
    return ClampWindowRectToWorkArea(requested, monitor_info.rcWork);
}

InitialWindowPlacement CalculateInitialWindowPlacement() {
    InitialWindowPlacement placement;
    HWND reference_window = GetForegroundWindow();
    HMONITOR monitor = reference_window
                           ? MonitorFromWindow(reference_window,
                                               MONITOR_DEFAULTTONEAREST)
                           : nullptr;
    if (!monitor) {
        POINT origin = {};
        monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    }

    placement.dpi = DpiForInitialMonitor(monitor, reference_window);
    SIZE window_size = {};
    if (!CalculateSettingsWindowSize(placement.dpi, kSettingsWindowStyle,
                                     kSettingsWindowExStyle, &window_size)) {
        const SettingsLayoutMetrics layout =
            CalculateSettingsLayoutMetrics(placement.dpi);
        window_size.cx = layout.client_width;
        window_size.cy = layout.client_height;
    }
    placement.width = window_size.cx;
    placement.height = window_size.cy;

    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    if (monitor && GetMonitorInfoW(monitor, &monitor_info)) {
        const int work_width =
            monitor_info.rcWork.right - monitor_info.rcWork.left;
        const int work_height =
            monitor_info.rcWork.bottom - monitor_info.rcWork.top;
        placement.width = std::min(placement.width, work_width);
        placement.height = std::min(placement.height, work_height);
        placement.x = monitor_info.rcWork.left +
                      std::max(0, (work_width - placement.width) / 2);
        placement.y = monitor_info.rcWork.top +
                      std::max(0, (work_height - placement.height) / 2);
    }
    return placement;
}

std::filesystem::path ModuleDirectory() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(nullptr, module_path, ARRAYSIZE(module_path))) {
        return {};
    }
    return std::filesystem::path(module_path).parent_path();
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
                                         static_cast<int>(value.size()), nullptr,
                                         0);
    if (size <= 0) {
        return {};
    }
    std::wstring output(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        output.data(), size);
    return output;
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
            value.push_back(json[pos++]);
        } else {
            value.push_back(ch);
        }
    }
    return value;
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

bool JsonReady(std::string_view json) {
    return json.find("\"ready\":true") != std::string::npos;
}

enum class ServerRequestStatus {
    Success,
    Conflict,
    Failure,
};

ServerRequestStatus ClassifyMutationEnvelope(std::string_view json) {
    bool mutation_applied = false;
    const std::string outcome = JsonStringValue(json, "outcome");
    if (!JsonBoolValue(json, "applied", &mutation_applied)) {
        return ServerRequestStatus::Failure;
    }
    if (mutation_applied) {
        return outcome == "applied" || outcome == "unchanged"
                   ? ServerRequestStatus::Success
                   : ServerRequestStatus::Failure;
    }
    const std::string reason = JsonStringValue(json, "reason");
    return outcome == "rejected" &&
                   (reason == "revision_conflict" ||
                    reason == "epoch_conflict")
               ? ServerRequestStatus::Conflict
               : ServerRequestStatus::Failure;
}

struct SettingsPipeCall {
    std::atomic<unsigned long> refs{1};
    HANDLE done = nullptr;
    std::string payload;
    std::string response;
    bool succeeded = false;
    std::atomic<bool> published{false};

    void AddRef() { ++refs; }
    void Release() {
        if (--refs == 0) {
            if (done) {
                CloseHandle(done);
            }
            delete this;
        }
    }
};

constexpr long kMaxSettingsPipeWorkers = 2;
std::atomic<long> g_settings_pipe_workers = 0;

DWORD WINAPI SettingsPipeWorkerProc(void* context) {
    auto* call = static_cast<SettingsPipeCall*>(context);
    try {
        char response[65536] = {};
        DWORD read = 0;
        if (CallNamedPipeW(kPipeName,
                           const_cast<char*>(call->payload.data()),
                           static_cast<DWORD>(call->payload.size()), response,
                           sizeof(response) - 1, &read,
                           kSettingsServerTimeoutMs)) {
            call->response.assign(response, read);
            call->succeeded = true;
        }
    } catch (...) {
        call->response.clear();
        call->succeeded = false;
    }
    call->published.store(true, std::memory_order_release);
    (void)SetEvent(call->done);
    --g_settings_pipe_workers;
    call->Release();
    return 0;
}

bool ExchangeSettingsPipe(const std::string& payload, std::string* response) {
    if (!response) {
        return false;
    }
    auto* call = new (std::nothrow) SettingsPipeCall;
    if (!call) {
        return false;
    }
    try {
        call->payload = payload;
    } catch (...) {
        call->Release();
        return false;
    }
    call->done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!call->done) {
        call->Release();
        return false;
    }

    long active = g_settings_pipe_workers.load();
    while (active < kMaxSettingsPipeWorkers &&
           !g_settings_pipe_workers.compare_exchange_weak(active,
                                                          active + 1)) {
    }
    if (active >= kMaxSettingsPipeWorkers) {
        call->Release();
        return false;
    }
    call->AddRef();
    HANDLE worker = CreateThread(nullptr, 0, SettingsPipeWorkerProc, call, 0,
                                 nullptr);
    if (!worker) {
        --g_settings_pipe_workers;
        call->Release();
        call->Release();
        return false;
    }
    CloseHandle(worker);

    const DWORD wait = WaitForSingleObject(call->done,
                                           kSettingsServerTimeoutMs);
    bool succeeded = false;
    if (wait == WAIT_OBJECT_0 &&
        call->published.load(std::memory_order_acquire) &&
        call->succeeded) {
        try {
            *response = call->response;
            succeeded = true;
        } catch (...) {
            succeeded = false;
        }
    }
    call->Release();
    return succeeded;
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
        const size_t array_end = json.find(']', array_start);
        if (end == std::string::npos ||
            (array_end != std::string::npos && end > array_end)) {
            break;
        }
        const std::string schema =
            JsonStringValue(json.substr(pos, end - pos + 1), "schema_id");
        if (!schema.empty()) {
            schemas.push_back(Widen(schema));
        }
        pos = json.find('{', end + 1);
    }
    return schemas;
}

bool ApplyStateJson(std::string_view json) {
    if (!JsonReady(json)) {
        return false;
    }
    const std::string schema_id = JsonStringValue(json, "schema_id");
    const std::string boot_id = JsonStringValue(json, "boot_id");
    const std::string output_standard = JsonStringValue(json, "output_standard");
    const std::string toolbar_skin = JsonStringValue(json, "skin");
    bool ascii_mode = false;
    bool full_shape = false;
    unsigned long long revision = 0;
    if (boot_id.empty() ||
        !JsonRevisionValue(json, "revision", &revision) ||
        schema_id.empty() || output_standard.empty() ||
        !JsonBoolValue(json, "ascii_mode", &ascii_mode) ||
        !JsonBoolValue(json, "full_shape", &full_shape)) {
        return false;
    }
    g_state.ready = true;
    g_state.boot_id = Widen(boot_id);
    g_state.revision = revision;
    g_state.schema_id = Widen(schema_id);
    g_state.output_standard = Widen(output_standard);
    g_state.ascii_mode = ascii_mode;
    g_state.full_shape = full_shape;
    if (!toolbar_skin.empty()) {
        g_state.toolbar_skin = Widen(toolbar_skin);
    }
    const std::vector<std::wstring> schemas = JsonSchemaIds(json);
    if (!schemas.empty()) {
        g_state.schemas = schemas;
    }
    return true;
}

ServerRequestStatus SendServerRequest(const std::string& payload,
                                      bool expect_mutation = false) {
    std::string response;
    if (!ExchangeSettingsPipe(payload, &response)) {
        return ServerRequestStatus::Failure;
    }
    const std::string_view json(response);
    if (!ApplyStateJson(json)) {
        return ServerRequestStatus::Failure;
    }
    if (expect_mutation) {
        return ClassifyMutationEnvelope(json);
    }
    return ServerRequestStatus::Success;
}

std::vector<std::wstring> EnumerateInstalledSkins(
    const std::filesystem::path& install_root) {
    std::vector<std::wstring> skins;
    const std::filesystem::path skins_dir = install_root / L"skins";
    std::error_code error;
    if (std::filesystem::is_directory(skins_dir, error)) {
        for (const auto& entry :
             std::filesystem::directory_iterator(skins_dir, error)) {
            if (error) {
                break;
            }
            if (!entry.is_directory(error)) {
                continue;
            }
            const std::filesystem::path manifest =
                entry.path() / L"theme.json";
            if (std::filesystem::is_regular_file(manifest, error)) {
                skins.push_back(entry.path().filename().wstring());
            }
        }
    }
    if (std::find(skins.begin(), skins.end(), L"default") == skins.end()) {
        skins.push_back(L"default");
    }
    std::sort(skins.begin(), skins.end());
    return skins;
}

std::wstring OutputStandardDisplayLabel(std::wstring_view value) {
    if (value == L"opencc_traditional") {
        return ui_strings::kOutputOpenccTraditional;
    }
    if (value == L"hong_kong_traditional") {
        return ui_strings::kOutputHongKongTraditional;
    }
    if (value == L"taiwan_traditional") {
        return ui_strings::kOutputTaiwanTraditional;
    }
    if (value == L"mainland_simplified") {
        return ui_strings::kOutputMainlandSimplified;
    }
    return ui_strings::kStatusUnknown;
}

std::wstring SchemaDisplayLabel(std::wstring_view value) {
    if (value == L"jyut6ping3") {
        return ui_strings::kSchemaJyutping;
    }
    if (value == L"cangjie5") {
        return ui_strings::kSchemaCangjie;
    }
    if (value == L"luna_pinyin") {
        return ui_strings::kSchemaLunaPinyin;
    }
    if (value == L"luna_pinyin_octagram") {
        return ui_strings::kSchemaLunaPinyinOctagram;
    }
    return ui_strings::kSchemaUnknown;
}

std::wstring SkinDisplayLabel(std::wstring_view skin) {
    if (skin.empty() || skin == L"default") {
        return ui_strings::kSkinDefault;
    }
    return std::wstring(skin);
}

std::wstring StatusLine() {
    std::wstring status = ui_strings::kStatusPrefix;
    status += g_state.ready ? ui_strings::kStatusConnected
                            : ui_strings::kStatusOffline;
    status += ui_strings::kStatusSeparator;
    status += OutputStandardDisplayLabel(g_state.output_standard);
    status += ui_strings::kStatusSeparator;
    status += ui_strings::kStatusSkinPrefix;
    status += SkinDisplayLabel(g_state.toolbar_skin);
    return status;
}

void ResetCombo(HWND combo, std::vector<ComboItem>* items) {
    if (combo) {
        SendMessageW(combo, CB_RESETCONTENT, 0, 0);
    }
    if (items) {
        items->clear();
    }
}

void AddComboItem(HWND combo, std::vector<ComboItem>* items,
                  std::wstring value, std::wstring label) {
    if (!combo || !items) {
        return;
    }
    items->push_back({std::move(value), std::move(label)});
    const size_t item_index = items->size() - 1;
    const LRESULT combo_index =
        SendMessageW(combo, CB_ADDSTRING, 0,
                     reinterpret_cast<LPARAM>((*items)[item_index].label.c_str()));
    if (combo_index != CB_ERR && combo_index != CB_ERRSPACE) {
        SendMessageW(combo, CB_SETITEMDATA, static_cast<WPARAM>(combo_index),
                     static_cast<LPARAM>(item_index));
    }
}

void SelectComboValue(HWND combo, const std::vector<ComboItem>& items,
                      std::wstring_view value) {
    if (!combo) {
        return;
    }
    const LRESULT count = SendMessageW(combo, CB_GETCOUNT, 0, 0);
    for (LRESULT i = 0; i < count; ++i) {
        const LRESULT item_data =
            SendMessageW(combo, CB_GETITEMDATA, static_cast<WPARAM>(i), 0);
        if (item_data >= 0 &&
            static_cast<size_t>(item_data) < items.size() &&
            value == items[static_cast<size_t>(item_data)].value) {
            SendMessageW(combo, CB_SETCURSEL, static_cast<WPARAM>(i), 0);
            return;
        }
    }
    SendMessageW(combo, CB_SETCURSEL, 0, 0);
}

std::wstring SelectedComboValue(HWND combo, const std::vector<ComboItem>& items) {
    if (!combo) {
        return {};
    }
    const LRESULT index = SendMessageW(combo, CB_GETCURSEL, 0, 0);
    if (index == CB_ERR) {
        return {};
    }
    const LRESULT item_data =
        SendMessageW(combo, CB_GETITEMDATA, static_cast<WPARAM>(index), 0);
    if (item_data < 0 || static_cast<size_t>(item_data) >= items.size()) {
        return {};
    }
    return items[static_cast<size_t>(item_data)].value;
}

void UpdatePreview() {
    if (g_state.preview_window) {
        InvalidateRect(g_state.preview_window, nullptr, TRUE);
    }
}

void UpdateControls() {
    if (g_state.ascii_button) {
        SetWindowTextW(g_state.ascii_button,
                       g_state.ascii_mode ? ui_strings::kModeEnglish
                                          : ui_strings::kModeChinese);
    }
    if (g_state.full_shape_button) {
        SetWindowTextW(g_state.full_shape_button,
                       g_state.full_shape ? ui_strings::kShapeFull
                                          : ui_strings::kShapeHalf);
    }
    if (g_state.output_combo) {
        ResetCombo(g_state.output_combo, &g_state.output_items);
        for (const std::wstring& value : {
                 std::wstring(L"opencc_traditional"),
                 std::wstring(L"hong_kong_traditional"),
                 std::wstring(L"taiwan_traditional"),
                 std::wstring(L"mainland_simplified")}) {
            AddComboItem(g_state.output_combo, &g_state.output_items, value,
                         OutputStandardDisplayLabel(value));
        }
        SelectComboValue(g_state.output_combo, g_state.output_items,
                         g_state.output_standard);
    }
    if (g_state.schema_combo) {
        ResetCombo(g_state.schema_combo, &g_state.schema_items);
        for (const std::wstring& schema : g_state.schemas) {
            AddComboItem(g_state.schema_combo, &g_state.schema_items, schema,
                         SchemaDisplayLabel(schema));
        }
        SelectComboValue(g_state.schema_combo, g_state.schema_items,
                         g_state.schema_id);
    }
    if (g_state.skin_combo) {
        ResetCombo(g_state.skin_combo, &g_state.skin_items);
        for (const std::wstring& skin : g_state.skins) {
            AddComboItem(g_state.skin_combo, &g_state.skin_items, skin,
                         SkinDisplayLabel(skin));
        }
        SelectComboValue(g_state.skin_combo, g_state.skin_items,
                         g_state.toolbar_skin);
    }
    if (g_state.status_label) {
        const std::wstring status = StatusLine();
        SetWindowTextW(g_state.status_label, status.c_str());
    }
    UpdatePreview();
}

void RefreshSkinList() {
    g_state.skins = EnumerateInstalledSkins(ModuleDirectory());
}

void RefreshState(HWND hwnd, bool show_error = true) {
    RefreshSkinList();
    if (SendServerRequest("op=get-state\n.\n") !=
        ServerRequestStatus::Success) {
        g_state.ready = false;
        if (show_error) {
            MessageBoxW(hwnd, ui_strings::kServerUnavailable,
                        ui_strings::kSettingsWindowTitle,
                        MB_OK | MB_ICONWARNING);
        }
        UpdateControls();
        return;
    }
    (void)SendServerRequest("op=list-schemas\n.\n");
    UpdateControls();
}

bool AppendStateExpectation(std::string* payload) {
    if (!payload || !g_state.ready || g_state.boot_id.empty()) {
        return false;
    }
    *payload += "expect_boot_id=" + Narrow(g_state.boot_id) + "\n";
    *payload += "expect_revision=" + std::to_string(g_state.revision) + "\n";
    return true;
}

void ApplyOption(HWND hwnd, std::string_view name, std::string_view value) {
    std::string payload = "op=set-option\nname=" + std::string(name) +
                          "\nvalue=" + std::string(value) + "\n";
    const ServerRequestStatus result =
        AppendStateExpectation(&payload)
            ? SendServerRequest(payload + ".\n", true)
            : ServerRequestStatus::Failure;
    if (result != ServerRequestStatus::Success) {
        MessageBoxW(hwnd,
                    result == ServerRequestStatus::Conflict
                        ? ui_strings::kStateChangedConcurrently
                        : ui_strings::kUpdateStateFailed,
                    ui_strings::kSettingsWindowTitle,
                    MB_OK | MB_ICONWARNING);
    }
    UpdateControls();
}

void ApplySchema(HWND hwnd, const std::wstring& schema_id) {
    if (schema_id.empty()) {
        return;
    }
    std::string payload = "op=select-schema\nschema=" + Narrow(schema_id) + "\n";
    const ServerRequestStatus result =
        AppendStateExpectation(&payload)
            ? SendServerRequest(payload + ".\n", true)
            : ServerRequestStatus::Failure;
    if (result != ServerRequestStatus::Success) {
        MessageBoxW(hwnd,
                    result == ServerRequestStatus::Conflict
                        ? ui_strings::kStateChangedConcurrently
                        : ui_strings::kUpdateSchemaFailed,
                    ui_strings::kSettingsWindowTitle,
                    MB_OK | MB_ICONWARNING);
    }
    UpdateControls();
}

void ApplySkin(HWND hwnd, const std::wstring& skin_name) {
    if (skin_name.empty()) {
        return;
    }
    std::string payload = "op=set-skin\nname=" + Narrow(skin_name) + "\n";
    const ServerRequestStatus result =
        AppendStateExpectation(&payload)
            ? SendServerRequest(payload + ".\n", true)
            : ServerRequestStatus::Failure;
    if (result != ServerRequestStatus::Success) {
        MessageBoxW(hwnd,
                    result == ServerRequestStatus::Conflict
                        ? ui_strings::kStateChangedConcurrently
                        : ui_strings::kUpdateSkinFailed,
                    ui_strings::kSettingsWindowTitle,
                    MB_OK | MB_ICONWARNING);
        UpdateControls();
        return;
    }
    UpdateControls();
}

void FocusSettingsWindow(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) {
        return;
    }
    ShowWindow(hwnd, SW_SHOWNORMAL);
    SetForegroundWindow(hwnd);
}

HWND WaitForSettingsWindow(DWORD timeout_ms) {
    const DWORD start = GetTickCount();
    for (;;) {
        HWND existing = FindWindowW(kWindowClassName, nullptr);
        if (existing && IsWindow(existing)) {
            return existing;
        }
        if (timeout_ms == 0 || GetTickCount() - start >= timeout_ms) {
            return nullptr;
        }
        Sleep(25);
    }
}

HFONT CreateUIFont(UINT dpi) {
    const int height = -MulDiv(10, static_cast<int>(dpi == 0 ? kDesignDpi : dpi),
                              72);
    return CreateFontW(height, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                       DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                       CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                       L"Microsoft JhengHei UI");
}

void ApplyUIFontToControls() {
    if (!g_state.ui_font) {
        return;
    }
    for (HWND control : g_state.controls) {
        if (control && IsWindow(control)) {
            SendMessageW(control, WM_SETFONT,
                         reinterpret_cast<WPARAM>(g_state.ui_font), TRUE);
        }
    }
}

void RefreshUIFont(UINT dpi) {
    HFONT next_font = CreateUIFont(dpi);
    if (!next_font) {
        return;
    }
    HFONT old_font = g_state.ui_font;
    g_state.ui_font = next_font;
    ApplyUIFontToControls();
    if (old_font) {
        DeleteObject(old_font);
    }
}

void RegisterControlForLayout(HWND control, int x, int y, int width, int height) {
    if (!control) {
        return;
    }
    g_state.controls.push_back(control);
    g_state.layout_entries.push_back({control, x, y, width, height});
    if (g_state.ui_font) {
        SendMessageW(control, WM_SETFONT,
                     reinterpret_cast<WPARAM>(g_state.ui_font), TRUE);
    }
}

void RelayoutControls(UINT dpi) {
    for (const LayoutEntry& entry : g_state.layout_entries) {
        if (entry.hwnd && IsWindow(entry.hwnd)) {
            MoveWindow(entry.hwnd,
                       Scale(entry.x, dpi) - g_state.scroll_x,
                       Scale(entry.y, dpi) - g_state.scroll_y,
                       Scale(entry.width, dpi), Scale(entry.height, dpi), TRUE);
        }
    }
}

void UpdateScrollBars(HWND hwnd) {
    RECT client = {};
    if (!hwnd || !GetClientRect(hwnd, &client)) {
        return;
    }
    const SettingsLayoutMetrics content =
        CalculateSettingsLayoutMetrics(g_state.dpi);
    const int client_width =
        std::max(1, static_cast<int>(client.right - client.left));
    const int client_height =
        std::max(1, static_cast<int>(client.bottom - client.top));

    SCROLLINFO horizontal = {};
    horizontal.cbSize = sizeof(horizontal);
    horizontal.fMask = SIF_RANGE | SIF_PAGE | SIF_POS;
    horizontal.nMin = 0;
    horizontal.nMax = std::max(0, content.client_width - 1);
    horizontal.nPage = static_cast<UINT>(client_width);
    horizontal.nPos = g_state.scroll_x;
    (void)SetScrollInfo(hwnd, SB_HORZ, &horizontal, TRUE);

    SCROLLINFO vertical = {};
    vertical.cbSize = sizeof(vertical);
    vertical.fMask = SIF_RANGE | SIF_PAGE | SIF_POS;
    vertical.nMin = 0;
    vertical.nMax = std::max(0, content.client_height - 1);
    vertical.nPage = static_cast<UINT>(client_height);
    vertical.nPos = g_state.scroll_y;
    (void)SetScrollInfo(hwnd, SB_VERT, &vertical, TRUE);

    horizontal.fMask = SIF_POS;
    vertical.fMask = SIF_POS;
    (void)GetScrollInfo(hwnd, SB_HORZ, &horizontal);
    (void)GetScrollInfo(hwnd, SB_VERT, &vertical);
    g_state.scroll_x = horizontal.nPos;
    g_state.scroll_y = vertical.nPos;
    RelayoutControls(g_state.dpi);
}

void ScrollSettingsWindow(HWND hwnd, int bar, int request,
                          int thumb_position = 0) {
    SCROLLINFO info = {};
    info.cbSize = sizeof(info);
    info.fMask = SIF_ALL;
    if (!GetScrollInfo(hwnd, bar, &info)) {
        return;
    }
    int next = info.nPos;
    const int line = Scale(24, g_state.dpi);
    const int page = static_cast<int>(std::max<UINT>(1, info.nPage));
    switch (request) {
        case SB_LINEUP:
            next -= line;
            break;
        case SB_LINEDOWN:
            next += line;
            break;
        case SB_PAGEUP:
            next -= page;
            break;
        case SB_PAGEDOWN:
            next += page;
            break;
        case SB_THUMBPOSITION:
        case SB_THUMBTRACK:
            next = thumb_position;
            break;
        case SB_TOP:
            next = info.nMin;
            break;
        case SB_BOTTOM:
            next = info.nMax;
            break;
        default:
            return;
    }
    info.fMask = SIF_POS;
    info.nPos = next;
    (void)SetScrollInfo(hwnd, bar, &info, TRUE);
    info.fMask = SIF_POS;
    (void)GetScrollInfo(hwnd, bar, &info);
    if (bar == SB_HORZ) {
        g_state.scroll_x = info.nPos;
    } else {
        g_state.scroll_y = info.nPos;
    }
    RelayoutControls(g_state.dpi);
}

DWORD WindowsBuildNumber() {
    using RtlGetVersionProc = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    auto rtl_get_version = ntdll ? reinterpret_cast<RtlGetVersionProc>(
                                      GetProcAddress(ntdll, "RtlGetVersion"))
                                : nullptr;
    if (!rtl_get_version) {
        return 0;
    }
    RTL_OSVERSIONINFOW version = {};
    version.dwOSVersionInfoSize = sizeof(version);
    if (rtl_get_version(&version) != 0) {
        return 0;
    }
    return version.dwBuildNumber;
}

bool SystemPrefersDarkMode() {
    DWORD light_theme = 1;
    DWORD size = sizeof(light_theme);
    const LSTATUS status = RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light_theme, &size);
    return status == ERROR_SUCCESS && light_theme == 0;
}

void ApplyDwmPolish(HWND hwnd) {
    if (!hwnd) {
        return;
    }
    const DWORD build = WindowsBuildNumber();
    const BOOL use_dark_mode = SystemPrefersDarkMode() ? TRUE : FALSE;
    HRESULT hr = DwmSetWindowAttribute(
        hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &use_dark_mode,
        sizeof(use_dark_mode));
    if (FAILED(hr)) {
        constexpr DWORD fallback_dark_mode_attribute = 19;
        (void)DwmSetWindowAttribute(hwnd, fallback_dark_mode_attribute,
                                    &use_dark_mode, sizeof(use_dark_mode));
    }

    if (build >= 22000) {
        const DWORD rounded = DWMWCP_ROUND;
        (void)DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                                    &rounded, sizeof(rounded));
    }
    if (build >= 22621) {
        const DWORD backdrop = DWMSBT_MAINWINDOW;
        (void)DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop,
                                    sizeof(backdrop));
    }
}

HWND AddText(HWND hwnd, int x, int y, int w, int h, const wchar_t* text) {
    HWND control = CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE,
                                   Scale(x, g_state.dpi), Scale(y, g_state.dpi),
                                   Scale(w, g_state.dpi), Scale(h, g_state.dpi),
                                   hwnd, nullptr, GetModuleHandleW(nullptr),
                                   nullptr);
    RegisterControlForLayout(control, x, y, w, h);
    return control;
}

HWND AddGroup(HWND hwnd, int x, int y, int w, int h, const wchar_t* text) {
    HWND control = CreateWindowExW(0, L"BUTTON", text,
                                   WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
                                   Scale(x, g_state.dpi), Scale(y, g_state.dpi),
                                   Scale(w, g_state.dpi), Scale(h, g_state.dpi),
                                   hwnd, nullptr, GetModuleHandleW(nullptr),
                                   nullptr);
    RegisterControlForLayout(control, x, y, w, h);
    return control;
}

HWND AddButton(HWND hwnd, int id, int x, int y, int w, int h,
               const wchar_t* text) {
    HWND control = CreateWindowExW(
        0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        Scale(x, g_state.dpi), Scale(y, g_state.dpi), Scale(w, g_state.dpi),
        Scale(h, g_state.dpi), hwnd,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        GetModuleHandleW(nullptr), nullptr);
    RegisterControlForLayout(control, x, y, w, h);
    return control;
}

HWND AddCombo(HWND hwnd, int id, int x, int y, int w, int h) {
    HWND control = CreateWindowExW(
        0, L"COMBOBOX", L"",
        WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
        Scale(x, g_state.dpi), Scale(y, g_state.dpi), Scale(w, g_state.dpi),
        Scale(h, g_state.dpi), hwnd,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        GetModuleHandleW(nullptr), nullptr);
    RegisterControlForLayout(control, x, y, w, h);
    return control;
}

HWND AddDisabled(HWND hwnd, int x, int y, int w, int h, const wchar_t* text) {
    HWND control = CreateWindowExW(
        0, L"BUTTON", text,
        WS_CHILD | WS_VISIBLE | WS_DISABLED | BS_AUTOCHECKBOX,
        Scale(x, g_state.dpi), Scale(y, g_state.dpi), Scale(w, g_state.dpi),
        Scale(h, g_state.dpi), hwnd, nullptr, GetModuleHandleW(nullptr),
        nullptr);
    RegisterControlForLayout(control, x, y, w, h);
    return control;
}

void CreatePanelControls(HWND hwnd) {
    g_state.controls.clear();
    g_state.layout_entries.clear();

    AddText(hwnd, 18, 12, 640, 20, ui_strings::kSettingsPanelTitle);
    g_state.status_label = AddText(hwnd, 18, 34, 640, 22, StatusLine().c_str());

    AddGroup(hwnd, 14, 64, 320, 190, ui_strings::kSectionSession);
    g_state.ascii_button = AddButton(hwnd, kButtonAscii, 30, 92, 130, 30,
                                     ui_strings::kModeChinese);
    g_state.full_shape_button = AddButton(hwnd, kButtonFullShape, 172, 92, 130,
                                          30, ui_strings::kShapeHalf);
    AddText(hwnd, 30, 132, 110, 20, ui_strings::kOutputStandard);
    g_state.output_combo = AddCombo(hwnd, kComboOutputStandard, 146, 128, 156, 150);
    AddText(hwnd, 30, 170, 110, 20, ui_strings::kSchemaSwitch);
    g_state.schema_combo = AddCombo(hwnd, kComboSchema, 146, 166, 156, 150);
    AddDisabled(hwnd, 30, 208, 230, 24,
                ui_strings::kExtendedCharsetComingSoon);

    AddGroup(hwnd, 354, 64, 330, 242, ui_strings::kSectionAppearance);
    AddText(hwnd, 370, 92, 80, 20, ui_strings::kSkin);
    g_state.skin_combo = AddCombo(hwnd, kComboSkin, 450, 88, 190, 150);
    g_state.preview_window = CreateWindowExW(
        WS_EX_CLIENTEDGE, kPreviewClassName, L"",
        WS_CHILD | WS_VISIBLE, Scale(370, g_state.dpi), Scale(130, g_state.dpi),
        Scale(292, g_state.dpi), Scale(68, g_state.dpi), hwnd,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPreviewToolbar)),
        GetModuleHandleW(nullptr), nullptr);
    RegisterControlForLayout(g_state.preview_window, 370, 130, 292, 68);
    AddDisabled(hwnd, 370, 212, 250, 24,
                ui_strings::kCandidatePageSizeComingSoon);
    AddDisabled(hwnd, 370, 238, 250, 24,
                ui_strings::kCandidateLayoutComingSoon);
    AddDisabled(hwnd, 370, 264, 250, 24,
                ui_strings::kRomanizationDisplayComingSoon);

    AddGroup(hwnd, 14, 270, 320, 145, ui_strings::kSectionEngine);
    AddDisabled(hwnd, 30, 298, 130, 24, ui_strings::kCompletionComingSoon);
    AddDisabled(hwnd, 172, 298, 130, 24, ui_strings::kCorrectionComingSoon);
    AddDisabled(hwnd, 30, 326, 130, 24, ui_strings::kSentenceModeComingSoon);
    AddDisabled(hwnd, 172, 326, 130, 24, ui_strings::kPredictionComingSoon);
    AddDisabled(hwnd, 30, 354, 190, 24,
                ui_strings::kCombineCandidatesComingSoon);

    AddGroup(hwnd, 354, 322, 330, 96, ui_strings::kSectionDictionary);
    AddDisabled(hwnd, 370, 350, 130, 26,
                ui_strings::kImportUserdbComingSoon);
    AddDisabled(hwnd, 512, 350, 130, 26,
                ui_strings::kExportUserdbComingSoon);

    AddGroup(hwnd, 14, 432, 670, 92, ui_strings::kSectionSchemas);
    AddText(hwnd, 30, 462, 356, 20, ui_strings::kInstalledSchemaSwitching);
    AddDisabled(hwnd, 30, 488, 180, 26,
                ui_strings::kImportSchemaComingSoon);
    AddButton(hwnd, kButtonRefresh, 548, 482, 110, 30, ui_strings::kRefresh);
}

void PaintPreview(HWND hwnd) {
    PAINTSTRUCT ps = {};
    HDC dc = BeginPaint(hwnd, &ps);
    RECT client = {};
    GetClientRect(hwnd, &client);

    yune_windows::LanguageBarState state;
    state.ascii_mode = g_state.ascii_mode;
    state.full_shape = g_state.full_shape;
    state.output_standard = g_state.output_standard;
    state.schema_id = g_state.schema_id;
    state.dpi = EffectiveWindowDpi(hwnd);
    state.skin_name = g_state.toolbar_skin;

    const yune_windows::ToolbarSkin skin =
        yune_windows::LoadToolbarSkin(ModuleDirectory(), g_state.toolbar_skin);
    if (!g_state.preview_surface.PaintLanguageBarPreview(
            hwnd, dc, client, state, skin)) {
        FillRect(dc, &client, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));
        DrawTextW(dc, ui_strings::kToolbarPreviewUnavailable, -1, &client,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }
    EndPaint(hwnd, &ps);
}

LRESULT CALLBACK PreviewProc(HWND hwnd, UINT message, WPARAM wparam,
                             LPARAM lparam) {
    switch (message) {
        case WM_PAINT:
            PaintPreview(hwnd);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        default:
            return DefWindowProcW(hwnd, message, wparam, lparam);
    }
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
    switch (message) {
        case WM_GETMINMAXINFO: {
            auto* minmax = reinterpret_cast<MINMAXINFO*>(lparam);
            if (!minmax) {
                return 0;
            }
            const UINT dpi = EffectiveWindowDpi(hwnd);
            const LONG_PTR current_style = GetWindowLongPtrW(hwnd, GWL_STYLE);
            const LONG_PTR current_ex_style =
                GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
            SIZE minimum = {};
            if (CalculateSettingsMinimumWindowSize(
                    dpi,
                    current_style == 0 ? kSettingsWindowStyle
                                       : static_cast<DWORD>(current_style),
                    current_ex_style == 0
                        ? kSettingsWindowExStyle
                        : static_cast<DWORD>(current_ex_style),
                    &minimum)) {
                MONITORINFO monitor_info = {};
                monitor_info.cbSize = sizeof(monitor_info);
                const HMONITOR monitor = MonitorFromWindow(
                    hwnd, MONITOR_DEFAULTTONEAREST);
                if (monitor && GetMonitorInfoW(monitor, &monitor_info)) {
                    minimum.cx = std::min(
                        minimum.cx,
                        static_cast<LONG>(monitor_info.rcWork.right -
                                          monitor_info.rcWork.left));
                    minimum.cy = std::min(
                        minimum.cy,
                        static_cast<LONG>(monitor_info.rcWork.bottom -
                                          monitor_info.rcWork.top));
                }
                minmax->ptMinTrackSize.x =
                    std::max(minmax->ptMinTrackSize.x, minimum.cx);
                minmax->ptMinTrackSize.y =
                    std::max(minmax->ptMinTrackSize.y, minimum.cy);
            }
            return 0;
        }
        case WM_CREATE:
            g_state.dpi = EffectiveWindowDpi(hwnd);
            RefreshUIFont(g_state.dpi);
            ApplyDwmPolish(hwnd);
            CreatePanelControls(hwnd);
            UpdateScrollBars(hwnd);
            if (!g_layout_smoke) {
                RefreshState(hwnd, false);
            }
            return 0;
        case WM_SIZE:
            UpdateScrollBars(hwnd);
            return 0;
        case WM_HSCROLL:
            ScrollSettingsWindow(hwnd, SB_HORZ, LOWORD(wparam),
                                 HIWORD(wparam));
            return 0;
        case WM_VSCROLL:
            ScrollSettingsWindow(hwnd, SB_VERT, LOWORD(wparam),
                                 HIWORD(wparam));
            return 0;
        case WM_MOUSEWHEEL:
            ScrollSettingsWindow(
                hwnd, SB_VERT,
                GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? SB_LINEUP : SB_LINEDOWN);
            return 0;
        case WM_DPICHANGED:
            g_state.dpi = HIWORD(wparam);
            g_state.scroll_x = 0;
            g_state.scroll_y = 0;
            if (lparam) {
                const RECT suggested =
                    *reinterpret_cast<const RECT*>(lparam);
                const RECT clamped =
                    ClampWindowRectToMonitorWorkArea(suggested);
                SetWindowPos(hwnd, nullptr, clamped.left, clamped.top,
                             clamped.right - clamped.left,
                             clamped.bottom - clamped.top,
                             SWP_NOZORDER | SWP_NOACTIVATE);
            }
            RefreshUIFont(g_state.dpi);
            UpdateScrollBars(hwnd);
            UpdatePreview();
            return 0;
        case WM_CTLCOLORSTATIC:
            if (reinterpret_cast<HWND>(lparam) == g_state.status_label) {
                HDC dc = reinterpret_cast<HDC>(wparam);
                SetTextColor(dc, kSettingsAccentColor);
                SetBkMode(dc, TRANSPARENT);
                return reinterpret_cast<LRESULT>(
                    GetSysColorBrush(COLOR_WINDOW));
            }
            break;
        case WM_COMMAND: {
            const int id = LOWORD(wparam);
            const int notification = HIWORD(wparam);
            switch (id) {
                case kButtonAscii:
                    ApplyOption(hwnd, "ascii_mode",
                                g_state.ascii_mode ? "0" : "1");
                    return 0;
                case kButtonFullShape:
                    ApplyOption(hwnd, "full_shape",
                                g_state.full_shape ? "0" : "1");
                    return 0;
                case kComboOutputStandard:
                    if (notification == CBN_SELCHANGE) {
                        ApplyOption(hwnd, "output_standard",
                                    Narrow(SelectedComboValue(
                                        g_state.output_combo,
                                        g_state.output_items)));
                    }
                    return 0;
                case kComboSchema:
                    if (notification == CBN_SELCHANGE) {
                        ApplySchema(hwnd,
                                    SelectedComboValue(g_state.schema_combo,
                                                       g_state.schema_items));
                    }
                    return 0;
                case kComboSkin:
                    if (notification == CBN_SELCHANGE) {
                        ApplySkin(hwnd, SelectedComboValue(g_state.skin_combo,
                                                           g_state.skin_items));
                    }
                    return 0;
                case kButtonRefresh:
                    RefreshState(hwnd);
                    return 0;
            }
            break;
        }
        case WM_DESTROY:
            g_state.preview_surface.DiscardDeviceResources();
            if (g_state.ui_font) {
                DeleteObject(g_state.ui_font);
                g_state.ui_font = nullptr;
            }
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool RegisterWindowClasses(HINSTANCE instance) {
    WNDCLASSEXW preview = {};
    preview.cbSize = sizeof(preview);
    preview.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    preview.hInstance = instance;
    preview.lpfnWndProc = PreviewProc;
    preview.lpszClassName = kPreviewClassName;
    preview.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    if (!RegisterClassExW(&preview) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return false;
    }

    WNDCLASSEXW settings = {};
    settings.cbSize = sizeof(settings);
    settings.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    settings.hInstance = instance;
    settings.lpfnWndProc = WindowProc;
    settings.lpszClassName = kWindowClassName;
    settings.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    return RegisterClassExW(&settings) ||
           GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

int SelfTest() {
    struct LayoutExpectation {
        UINT dpi;
        int client_width;
        int client_height;
    };
    constexpr std::array<LayoutExpectation, 4> layout_expectations = {{
        {96, 704, 542},
        {120, 880, 678},
        {144, 1056, 813},
        {192, 1408, 1084},
    }};
    for (const LayoutExpectation& expected : layout_expectations) {
        const SettingsLayoutMetrics layout =
            CalculateSettingsLayoutMetrics(expected.dpi);
        SIZE window_size = {};
        if (layout.client_width != expected.client_width ||
            layout.client_height != expected.client_height ||
            !CalculateSettingsWindowSize(
                expected.dpi, kSettingsWindowStyle,
                kSettingsWindowExStyle, &window_size) ||
            window_size.cx < layout.client_width ||
            window_size.cy < layout.client_height) {
            std::cerr << "settings DPI layout self-test failed at "
                      << expected.dpi << " DPI\n";
            return 1;
        }
    }
    const RECT constrained_work = {0, 0, 1000, 700};
    const RECT oversized_transition = {-80, -40, 1500, 1200};
    const RECT clamped_transition = ClampWindowRectToWorkArea(
        oversized_transition, constrained_work);
    if (clamped_transition.left < constrained_work.left ||
        clamped_transition.top < constrained_work.top ||
        clamped_transition.right > constrained_work.right ||
        clamped_transition.bottom > constrained_work.bottom ||
        clamped_transition.right - clamped_transition.left != 1000 ||
        clamped_transition.bottom - clamped_transition.top != 700) {
        std::cerr << "settings DPI transition clamp self-test failed\n";
        return 1;
    }

    g_state.skins = EnumerateInstalledSkins(ModuleDirectory());
    if (std::find(g_state.skins.begin(), g_state.skins.end(), L"default") ==
        g_state.skins.end()) {
        std::cerr << "default skin was not enumerated\n";
        return 1;
    }
    const char* state_json =
        "{\"ready\":true,\"state\":{\"boot_id\":\"self-test\","
        "\"revision\":0,\"schema_id\":\"jyut6ping3\","
        "\"ascii_mode\":false,\"full_shape\":true,"
        "\"output_standard\":\"hong_kong_traditional\","
        "\"toolbar\":{\"position_set\":false,\"x\":0,\"y\":0,"
        "\"skin\":\"default\"}},\"schemas\":[{\"schema_id\":\"jyut6ping3\"}]}\n";
    if (!ApplyStateJson(state_json) || g_state.toolbar_skin != L"default" ||
        g_state.schemas.empty()) {
        std::cerr << "settings state JSON self-test failed\n";
        return 1;
    }
    const char* malformed_revision_json =
        "{\"ready\":true,\"state\":{\"boot_id\":\"self-test\","
        "\"revision\":12junk,\"schema_id\":\"jyut6ping3\","
        "\"ascii_mode\":false,\"full_shape\":false,"
        "\"output_standard\":\"hong_kong_traditional\"}}";
    if (ApplyStateJson(malformed_revision_json)) {
        std::cerr << "settings accepted malformed state revision\n";
        return 1;
    }
    if (ClassifyMutationEnvelope(
            R"({"applied":true,"outcome":"unchanged"})") !=
            ServerRequestStatus::Success ||
        ClassifyMutationEnvelope(
            R"({"applied":true,"outcome":"unknown"})") !=
            ServerRequestStatus::Failure ||
        ClassifyMutationEnvelope(
            R"({"outcome":"applied"})") !=
            ServerRequestStatus::Failure ||
        ClassifyMutationEnvelope(
            R"({"applied":false,"outcome":"rejected","reason":"revision_conflict"})") !=
            ServerRequestStatus::Conflict ||
        ClassifyMutationEnvelope(
            R"({"applied":false,"outcome":"rejected","reason":"epoch_conflict"})") !=
            ServerRequestStatus::Conflict ||
        ClassifyMutationEnvelope(
            R"({"applied":false,"outcome":"rejected","reason":"invalid"})") !=
            ServerRequestStatus::Failure) {
        std::cerr << "settings mutation envelope self-test failed\n";
        return 1;
    }
    if (OutputStandardDisplayLabel(L"opencc_traditional") !=
            ui_strings::kOutputOpenccTraditional ||
        SchemaDisplayLabel(L"luna_pinyin_octagram") !=
            ui_strings::kSchemaLunaPinyinOctagram ||
        SkinDisplayLabel(L"default") != ui_strings::kSkinDefault) {
        std::cerr << "settings localized label self-test failed\n";
        return 1;
    }

    const yune_windows::ToolbarSkin skin =
        yune_windows::LoadToolbarSkin(ModuleDirectory(), L"default");
    if (skin.name.empty() ||
        yune_windows::ToolbarSegmentLabelForState(
            yune_windows::LanguageBarSegment::Settings,
            yune_windows::LanguageBarState{}, skin)
                .empty()) {
        std::cerr << "settings skin preview self-test failed\n";
        return 1;
    }

    HDC screen_dc = GetDC(nullptr);
    HDC memory_dc = screen_dc ? CreateCompatibleDC(screen_dc) : nullptr;
    HBITMAP bitmap =
        screen_dc ? CreateCompatibleBitmap(screen_dc, 360, 72) : nullptr;
    if (!screen_dc || !memory_dc || !bitmap) {
        if (bitmap) {
            DeleteObject(bitmap);
        }
        if (memory_dc) {
            DeleteDC(memory_dc);
        }
        if (screen_dc) {
            ReleaseDC(nullptr, screen_dc);
        }
        std::cerr << "settings preview HDC self-test setup failed\n";
        return 1;
    }
    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
    RECT preview_rect = {0, 0, 360, 72};
    yune_windows::LanguageBarState preview_state;
    preview_state.schema_id = L"jyut6ping3";
    preview_state.output_standard = L"hong_kong_traditional";
    preview_state.dpi = 96;
    const bool painted = g_state.preview_surface.PaintLanguageBarPreview(
        GetDesktopWindow(), memory_dc, preview_rect, preview_state, skin);
    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    if (!painted) {
        std::cerr << "settings preview render self-test failed\n";
        return 1;
    }
    std::cout << "settings self-test passed\n";
    return 0;
}

int LayoutWindowSmoke(HWND hwnd) {
    if (!hwnd) {
        return 1;
    }
    const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if ((style & WS_THICKFRAME) == 0 || (style & WS_MAXIMIZEBOX) == 0) {
        std::cerr << "settings layout smoke window is not resizable\n";
        return 1;
    }

    MINMAXINFO minmax = {};
    (void)SendMessageW(hwnd, WM_GETMINMAXINFO, 0,
                       reinterpret_cast<LPARAM>(&minmax));
    SIZE expected_minimum = {};
    if (!CalculateSettingsMinimumWindowSize(
            EffectiveWindowDpi(hwnd), static_cast<DWORD>(style),
            static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_EXSTYLE)),
            &expected_minimum)) {
        std::cerr << "settings layout smoke minimum calculation failed\n";
        return 1;
    }
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    const HMONITOR monitor =
        MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (monitor && GetMonitorInfoW(monitor, &monitor_info)) {
        expected_minimum.cx = std::min(
            expected_minimum.cx,
            monitor_info.rcWork.right - monitor_info.rcWork.left);
        expected_minimum.cy = std::min(
            expected_minimum.cy,
            monitor_info.rcWork.bottom - monitor_info.rcWork.top);
    }
    if (minmax.ptMinTrackSize.x < expected_minimum.cx ||
        minmax.ptMinTrackSize.y < expected_minimum.cy) {
        std::cerr << "settings layout smoke minimum tracking is invalid\n";
        return 1;
    }

    (void)SetWindowPos(hwnd, nullptr, 0, 0, expected_minimum.cx,
                       expected_minimum.cy,
                       SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    UpdateScrollBars(hwnd);
    RECT client = {};
    if (!GetClientRect(hwnd, &client)) {
        return 1;
    }
    SCROLLINFO horizontal = {};
    horizontal.cbSize = sizeof(horizontal);
    horizontal.fMask = SIF_ALL;
    SCROLLINFO vertical = horizontal;
    if (!GetScrollInfo(hwnd, SB_HORZ, &horizontal) ||
        !GetScrollInfo(hwnd, SB_VERT, &vertical) ||
        horizontal.nMax + 1 <= static_cast<int>(horizontal.nPage) ||
        vertical.nMax + 1 <= static_cast<int>(vertical.nPage)) {
        std::cerr << "settings layout smoke minimum has no scroll access\n";
        return 1;
    }
    ScrollSettingsWindow(hwnd, SB_HORZ, SB_RIGHT);
    ScrollSettingsWindow(hwnd, SB_VERT, SB_BOTTOM);
    if (g_state.scroll_x <= 0 || g_state.scroll_y <= 0) {
        std::cerr << "settings layout smoke could not reach content end\n";
        return 1;
    }
    if (!GetClientRect(hwnd, &client)) {
        return 1;
    }
    const SettingsLayoutMetrics content =
        CalculateSettingsLayoutMetrics(g_state.dpi);
    if (content.client_width - g_state.scroll_x > client.right - client.left ||
        content.client_height - g_state.scroll_y >
            client.bottom - client.top) {
        std::cerr << "settings layout smoke scroll range stops before canvas end\n";
        return 1;
    }

    SIZE design_window = {};
    if (!CalculateSettingsWindowSize(
            EffectiveWindowDpi(hwnd), static_cast<DWORD>(style),
            static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_EXSTYLE)),
            &design_window)) {
        return 1;
    }
    (void)SetWindowPos(hwnd, nullptr, 0, 0,
                       design_window.cx + Scale(64, g_state.dpi),
                       design_window.cy + Scale(64, g_state.dpi),
                       SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    ScrollSettingsWindow(hwnd, SB_HORZ, SB_LEFT);
    ScrollSettingsWindow(hwnd, SB_VERT, SB_TOP);
    UpdateScrollBars(hwnd);
    if (!GetClientRect(hwnd, &client)) {
        return 1;
    }
    for (HWND control : g_state.controls) {
        if (!control || !IsWindow(control) ||
            (GetWindowLongPtrW(control, GWL_STYLE) & WS_VISIBLE) == 0) {
            continue;
        }
        RECT bounds = {};
        if (!GetWindowRect(control, &bounds)) {
            return 1;
        }
        POINT corners[2] = {{bounds.left, bounds.top},
                            {bounds.right, bounds.bottom}};
        SetLastError(ERROR_SUCCESS);
        if ((MapWindowPoints(nullptr, hwnd, corners, 2) == 0 &&
             GetLastError() != ERROR_SUCCESS) ||
            corners[0].x < client.left || corners[0].y < client.top ||
            corners[1].x > client.right || corners[1].y > client.bottom) {
            std::cerr << "settings layout smoke larger window clipped a child\n";
            return 1;
        }
    }
    std::cout << "settings layout smoke passed at " << g_state.dpi
              << " DPI\n";
    return 0;
}

bool IsSupportedLayoutSmokeDpi(UINT dpi) {
    constexpr std::array<UINT, 4> supported = {96, 120, 144, 192};
    return std::find(supported.begin(), supported.end(), dpi) !=
           supported.end();
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    const HRESULT coinit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(coinit);
    INITCOMMONCONTROLSEX common_controls = {};
    common_controls.dwSize = sizeof(common_controls);
    common_controls.dwICC = ICC_STANDARD_CLASSES | ICC_WIN95_CLASSES;
    (void)InitCommonControlsEx(&common_controls);
    if (argc == 2 && std::wstring(argv[1]) == L"--self-test") {
        const int result = SelfTest();
        if (should_uninit) {
            CoUninitialize();
        }
        return result;
    }
    g_layout_smoke =
        argc == 2 && std::wstring(argv[1]) == L"--layout-smoke";
    if (argc >= 2 && std::wstring(argv[1]) == L"--layout-smoke-dpi") {
        if (argc != 3) {
            std::cerr << "--layout-smoke-dpi requires one DPI value\n";
            if (should_uninit) {
                CoUninitialize();
            }
            return 2;
        }
        try {
            const unsigned long parsed = std::stoul(argv[2]);
            if (!IsSupportedLayoutSmokeDpi(static_cast<UINT>(parsed))) {
                throw std::out_of_range("unsupported settings smoke DPI");
            }
            g_layout_smoke = true;
            g_layout_smoke_dpi = static_cast<UINT>(parsed);
        }
        catch (...) {
            std::cerr << "unsupported settings layout smoke DPI\n";
            if (should_uninit) {
                CoUninitialize();
            }
            return 2;
        }
    }

    HANDLE instance_mutex = g_layout_smoke
                                ? nullptr
                                : CreateMutexW(nullptr, TRUE,
                                               kInstanceMutexName);
    const DWORD mutex_error = GetLastError();
    if (instance_mutex && mutex_error == ERROR_ALREADY_EXISTS) {
        FocusSettingsWindow(WaitForSettingsWindow(1500));
        CloseHandle(instance_mutex);
        if (should_uninit) {
            CoUninitialize();
        }
        return 0;
    }

    HWND existing = g_layout_smoke ? nullptr : WaitForSettingsWindow(0);
    if (!g_layout_smoke && existing && IsWindow(existing)) {
        FocusSettingsWindow(existing);
        if (instance_mutex) {
            ReleaseMutex(instance_mutex);
            CloseHandle(instance_mutex);
        }
        if (should_uninit) {
            CoUninitialize();
        }
        return 0;
    }

    HINSTANCE instance = GetModuleHandleW(nullptr);
    if (!RegisterWindowClasses(instance)) {
        if (instance_mutex) {
            ReleaseMutex(instance_mutex);
            CloseHandle(instance_mutex);
        }
        if (should_uninit) {
            CoUninitialize();
        }
        return 1;
    }

    const InitialWindowPlacement initial = CalculateInitialWindowPlacement();
    HWND hwnd = CreateWindowExW(kSettingsWindowExStyle, kWindowClassName,
                                ui_strings::kSettingsWindowTitle,
                                kSettingsWindowStyle, initial.x, initial.y,
                                initial.width, initial.height, nullptr,
                                nullptr, instance, nullptr);
    if (!hwnd) {
        if (instance_mutex) {
            ReleaseMutex(instance_mutex);
            CloseHandle(instance_mutex);
        }
        if (should_uninit) {
            CoUninitialize();
        }
        return 1;
    }
    if (g_layout_smoke) {
        const int result = LayoutWindowSmoke(hwnd);
        DestroyWindow(hwnd);
        if (should_uninit) {
            CoUninitialize();
        }
        return result;
    }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    MSG message = {};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    if (instance_mutex) {
        ReleaseMutex(instance_mutex);
        CloseHandle(instance_mutex);
    }
    if (should_uninit) {
        CoUninitialize();
    }
    return 0;
}
