#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>

#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr const wchar_t* kPipeName = L"\\\\.\\pipe\\yune-windows-ime";
constexpr const wchar_t* kWindowClassName = L"YuneWindowsSettingsWindow";
constexpr int kButtonAscii = 1001;
constexpr int kButtonFullShape = 1002;
constexpr int kButtonStandard = 1003;
constexpr int kButtonSchema = 1004;
constexpr int kButtonRefresh = 1005;

struct SettingsState {
    bool ready = false;
    std::wstring schema_id = L"jyut6ping3";
    bool ascii_mode = false;
    bool full_shape = false;
    std::wstring output_standard = L"hong_kong_traditional";
    std::vector<std::wstring> schemas;
    HWND ascii_button = nullptr;
    HWND full_shape_button = nullptr;
    HWND standard_button = nullptr;
    HWND schema_button = nullptr;
};

SettingsState g_state;

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

bool JsonReady(std::string_view json) {
    return json.find("\"ready\":true") != std::string::npos;
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
        const std::string schema = JsonStringValue(json.substr(pos, end - pos + 1),
                                                   "schema_id");
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
    const std::string output_standard = JsonStringValue(json, "output_standard");
    bool ascii_mode = false;
    bool full_shape = false;
    if (schema_id.empty() || output_standard.empty() ||
        !JsonBoolValue(json, "ascii_mode", &ascii_mode) ||
        !JsonBoolValue(json, "full_shape", &full_shape)) {
        return false;
    }
    g_state.ready = true;
    g_state.schema_id = Widen(schema_id);
    g_state.output_standard = Widen(output_standard);
    g_state.ascii_mode = ascii_mode;
    g_state.full_shape = full_shape;
    const std::vector<std::wstring> schemas = JsonSchemaIds(json);
    if (!schemas.empty()) {
        g_state.schemas = schemas;
    }
    return true;
}

bool SendServerRequest(const std::string& payload) {
    char response[65536] = {};
    DWORD read = 0;
    if (!CallNamedPipeW(kPipeName, const_cast<char*>(payload.data()),
                        static_cast<DWORD>(payload.size()), response,
                        sizeof(response) - 1, &read, 5000)) {
        return false;
    }
    return ApplyStateJson(std::string_view(response, read));
}

std::wstring OutputStandardLabel() {
    if (g_state.output_standard == L"opencc_traditional") {
        return L"Output: OpenCC";
    }
    if (g_state.output_standard == L"hong_kong_traditional") {
        return L"Output: HK traditional";
    }
    if (g_state.output_standard == L"taiwan_traditional") {
        return L"Output: Taiwan traditional";
    }
    if (g_state.output_standard == L"mainland_simplified") {
        return L"Output: Mainland simplified";
    }
    return L"Output: unknown";
}

void UpdateButtons() {
    if (g_state.ascii_button) {
        SetWindowTextW(g_state.ascii_button,
                       g_state.ascii_mode ? L"Mode: English" : L"Mode: Chinese");
    }
    if (g_state.full_shape_button) {
        SetWindowTextW(g_state.full_shape_button,
                       g_state.full_shape ? L"Shape: Full" : L"Shape: Half");
    }
    if (g_state.standard_button) {
        SetWindowTextW(g_state.standard_button, OutputStandardLabel().c_str());
    }
    if (g_state.schema_button) {
        std::wstring label = L"Schema: " + g_state.schema_id;
        SetWindowTextW(g_state.schema_button, label.c_str());
    }
}

void RefreshState(HWND hwnd) {
    if (!SendServerRequest("op=get-state\n.\n")) {
        MessageBoxW(hwnd, L"Yune Windows server is not available.",
                    L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
        return;
    }
    (void)SendServerRequest("op=list-schemas\n.\n");
    UpdateButtons();
}

std::wstring NextOutputStandard() {
    const std::wstring standards[] = {
        L"opencc_traditional",
        L"hong_kong_traditional",
        L"taiwan_traditional",
        L"mainland_simplified",
    };
    constexpr size_t count = sizeof(standards) / sizeof(standards[0]);
    for (size_t i = 0; i < count; ++i) {
        if (g_state.output_standard == standards[i]) {
            return standards[(i + 1) % count];
        }
    }
    return L"hong_kong_traditional";
}

std::wstring NextSchema() {
    if (g_state.schemas.empty()) {
        g_state.schemas = {L"jyut6ping3", L"cangjie5", L"luna_pinyin"};
    }
    for (size_t i = 0; i < g_state.schemas.size(); ++i) {
        if (g_state.schema_id == g_state.schemas[i]) {
            return g_state.schemas[(i + 1) % g_state.schemas.size()];
        }
    }
    return g_state.schemas.front();
}

void ApplyOption(HWND hwnd, std::string_view name, std::string_view value) {
    std::string payload = "op=set-option\nname=" + std::string(name) +
                          "\nvalue=" + std::string(value) + "\n.\n";
    if (!SendServerRequest(payload)) {
        MessageBoxW(hwnd, L"Unable to update Yune Windows state.",
                    L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
    }
    UpdateButtons();
}

void ApplySchema(HWND hwnd, const std::wstring& schema_id) {
    std::string payload = "op=select-schema\nschema=" + Narrow(schema_id) + "\n.\n";
    if (!SendServerRequest(payload)) {
        MessageBoxW(hwnd, L"Unable to update Yune Windows schema.",
                    L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
    }
    UpdateButtons();
}

HWND AddButton(HWND hwnd, int id, int y, const wchar_t* text) {
    return CreateWindowExW(0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                           18, y, 340, 34, hwnd,
                           reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                           GetModuleHandleW(nullptr), nullptr);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
        case WM_CREATE:
            g_state.ascii_button = AddButton(hwnd, kButtonAscii, 18, L"Mode");
            g_state.full_shape_button =
                AddButton(hwnd, kButtonFullShape, 60, L"Shape");
            g_state.standard_button =
                AddButton(hwnd, kButtonStandard, 102, L"Output");
            g_state.schema_button = AddButton(hwnd, kButtonSchema, 144, L"Schema");
            AddButton(hwnd, kButtonRefresh, 186, L"Refresh");
            RefreshState(hwnd);
            return 0;
        case WM_COMMAND:
            switch (LOWORD(wparam)) {
                case kButtonAscii:
                    ApplyOption(hwnd, "ascii_mode",
                                g_state.ascii_mode ? "0" : "1");
                    return 0;
                case kButtonFullShape:
                    ApplyOption(hwnd, "full_shape",
                                g_state.full_shape ? "0" : "1");
                    return 0;
                case kButtonStandard:
                    ApplyOption(hwnd, "output_standard",
                                Narrow(NextOutputStandard()));
                    return 0;
                case kButtonSchema:
                    ApplySchema(hwnd, NextSchema());
                    return 0;
                case kButtonRefresh:
                    RefreshState(hwnd);
                    return 0;
            }
            break;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

int wmain() {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    HINSTANCE instance = GetModuleHandleW(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hInstance = instance;
    wc.lpfnWndProc = WindowProc;
    wc.lpszClassName = kWindowClassName;
    RegisterClassExW(&wc);

    HWND hwnd = CreateWindowExW(WS_EX_APPWINDOW, kWindowClassName,
                                L"Yune Windows Settings",
                                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU |
                                    WS_MINIMIZEBOX,
                                CW_USEDEFAULT, CW_USEDEFAULT, 394, 280, nullptr,
                                nullptr, instance, nullptr);
    if (!hwnd) {
        CoUninitialize();
        return 1;
    }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    MSG message = {};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    CoUninitialize();
    return 0;
}
