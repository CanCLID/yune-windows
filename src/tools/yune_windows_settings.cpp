#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <windowsx.h>

#include <algorithm>
#include <filesystem>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

#include "../candidate_window/yune_windows_candidate_window.h"

namespace {

constexpr const wchar_t* kPipeName = L"\\\\.\\pipe\\yune-windows-ime";
constexpr const wchar_t* kWindowClassName = L"YuneWindowsSettingsWindow";
constexpr const wchar_t* kPreviewClassName = L"YuneWindowsSettingsPreview";
constexpr const wchar_t* kInstanceMutexName =
    L"Local\\YuneWindowsSettingsInstance";

constexpr int kButtonAscii = 1001;
constexpr int kButtonFullShape = 1002;
constexpr int kComboOutputStandard = 1003;
constexpr int kComboSchema = 1004;
constexpr int kButtonRefresh = 1005;
constexpr int kComboSkin = 1006;
constexpr int kPreviewToolbar = 1007;

struct SettingsState {
    bool ready = false;
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
    yune_windows::D2DSurface preview_surface;
};

SettingsState g_state;

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
    const std::string output_standard = JsonStringValue(json, "output_standard");
    const std::string toolbar_skin = JsonStringValue(json, "skin");
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
    if (!toolbar_skin.empty()) {
        g_state.toolbar_skin = Widen(toolbar_skin);
    }
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

std::wstring OutputStandardLabel(std::wstring_view value) {
    if (value == L"opencc_traditional") {
        return L"OpenCC traditional";
    }
    if (value == L"hong_kong_traditional") {
        return L"Hong Kong traditional";
    }
    if (value == L"taiwan_traditional") {
        return L"Taiwan traditional";
    }
    if (value == L"mainland_simplified") {
        return L"Mainland simplified";
    }
    return L"Unknown";
}

std::wstring SkinDisplayLabel(std::wstring_view skin) {
    return L"Skin: " + std::wstring(skin);
}

void ResetCombo(HWND combo) {
    if (combo) {
        SendMessageW(combo, CB_RESETCONTENT, 0, 0);
    }
}

void AddComboItem(HWND combo, const std::wstring& value) {
    SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(value.c_str()));
}

void SelectComboItem(HWND combo, std::wstring_view value) {
    if (!combo) {
        return;
    }
    const LRESULT count = SendMessageW(combo, CB_GETCOUNT, 0, 0);
    for (LRESULT i = 0; i < count; ++i) {
        wchar_t text[256] = {};
        SendMessageW(combo, CB_GETLBTEXT, static_cast<WPARAM>(i),
                     reinterpret_cast<LPARAM>(text));
        if (value == text) {
            SendMessageW(combo, CB_SETCURSEL, static_cast<WPARAM>(i), 0);
            return;
        }
    }
    SendMessageW(combo, CB_SETCURSEL, 0, 0);
}

std::wstring SelectedComboText(HWND combo) {
    if (!combo) {
        return {};
    }
    const LRESULT index = SendMessageW(combo, CB_GETCURSEL, 0, 0);
    if (index == CB_ERR) {
        return {};
    }
    wchar_t text[256] = {};
    SendMessageW(combo, CB_GETLBTEXT, static_cast<WPARAM>(index),
                 reinterpret_cast<LPARAM>(text));
    return text;
}

void UpdatePreview() {
    if (g_state.preview_window) {
        InvalidateRect(g_state.preview_window, nullptr, TRUE);
    }
}

void UpdateControls() {
    if (g_state.ascii_button) {
        SetWindowTextW(g_state.ascii_button,
                       g_state.ascii_mode ? L"Mode: English" : L"Mode: Chinese");
    }
    if (g_state.full_shape_button) {
        SetWindowTextW(g_state.full_shape_button,
                       g_state.full_shape ? L"Shape: Full" : L"Shape: Half");
    }
    if (g_state.output_combo) {
        ResetCombo(g_state.output_combo);
        AddComboItem(g_state.output_combo, L"opencc_traditional");
        AddComboItem(g_state.output_combo, L"hong_kong_traditional");
        AddComboItem(g_state.output_combo, L"taiwan_traditional");
        AddComboItem(g_state.output_combo, L"mainland_simplified");
        SelectComboItem(g_state.output_combo, g_state.output_standard);
    }
    if (g_state.schema_combo) {
        ResetCombo(g_state.schema_combo);
        for (const std::wstring& schema : g_state.schemas) {
            AddComboItem(g_state.schema_combo, schema);
        }
        SelectComboItem(g_state.schema_combo, g_state.schema_id);
    }
    if (g_state.skin_combo) {
        ResetCombo(g_state.skin_combo);
        for (const std::wstring& skin : g_state.skins) {
            AddComboItem(g_state.skin_combo, skin);
        }
        SelectComboItem(g_state.skin_combo, g_state.toolbar_skin);
    }
    if (g_state.status_label) {
        const std::wstring status =
            L"State: " + std::wstring(g_state.ready ? L"connected" : L"offline") +
            L" | " + OutputStandardLabel(g_state.output_standard) +
            L" | " + SkinDisplayLabel(g_state.toolbar_skin);
        SetWindowTextW(g_state.status_label, status.c_str());
    }
    UpdatePreview();
}

void RefreshSkinList() {
    g_state.skins = EnumerateInstalledSkins(ModuleDirectory());
}

void RefreshState(HWND hwnd, bool show_error = true) {
    RefreshSkinList();
    if (!SendServerRequest("op=get-state\n.\n")) {
        g_state.ready = false;
        if (show_error) {
            MessageBoxW(hwnd, L"Yune Windows server is not available.",
                        L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
        }
        UpdateControls();
        return;
    }
    (void)SendServerRequest("op=list-schemas\n.\n");
    UpdateControls();
}

void ApplyOption(HWND hwnd, std::string_view name, std::string_view value) {
    std::string payload = "op=set-option\nname=" + std::string(name) +
                          "\nvalue=" + std::string(value) + "\n.\n";
    if (!SendServerRequest(payload)) {
        MessageBoxW(hwnd, L"Unable to update Yune Windows state.",
                    L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
    }
    UpdateControls();
}

void ApplySchema(HWND hwnd, const std::wstring& schema_id) {
    if (schema_id.empty()) {
        return;
    }
    std::string payload = "op=select-schema\nschema=" + Narrow(schema_id) + "\n.\n";
    if (!SendServerRequest(payload)) {
        MessageBoxW(hwnd, L"Unable to update Yune Windows schema.",
                    L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
    }
    UpdateControls();
}

void ApplySkin(HWND hwnd, const std::wstring& skin_name) {
    if (skin_name.empty()) {
        return;
    }
    std::string payload = "op=set-skin\nname=" + Narrow(skin_name) + "\n.\n";
    if (!SendServerRequest(payload)) {
        MessageBoxW(hwnd, L"Unable to update Yune Windows skin.",
                    L"Yune Windows Settings", MB_OK | MB_ICONWARNING);
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

HWND AddText(HWND hwnd, int x, int y, int w, int h, const wchar_t* text) {
    return CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE,
                           x, y, w, h, hwnd, nullptr, GetModuleHandleW(nullptr),
                           nullptr);
}

HWND AddGroup(HWND hwnd, int x, int y, int w, int h, const wchar_t* text) {
    return CreateWindowExW(0, L"BUTTON", text,
                           WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
                           x, y, w, h, hwnd, nullptr, GetModuleHandleW(nullptr),
                           nullptr);
}

HWND AddButton(HWND hwnd, int id, int x, int y, int w, int h,
               const wchar_t* text) {
    return CreateWindowExW(0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                           x, y, w, h, hwnd,
                           reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                           GetModuleHandleW(nullptr), nullptr);
}

HWND AddCombo(HWND hwnd, int id, int x, int y, int w, int h) {
    return CreateWindowExW(0, L"COMBOBOX", L"",
                           WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
                           x, y, w, h, hwnd,
                           reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                           GetModuleHandleW(nullptr), nullptr);
}

HWND AddDisabled(HWND hwnd, int x, int y, int w, int h, const wchar_t* text) {
    return CreateWindowExW(0, L"BUTTON", text,
                           WS_CHILD | WS_VISIBLE | WS_DISABLED | BS_AUTOCHECKBOX,
                           x, y, w, h, hwnd, nullptr, GetModuleHandleW(nullptr),
                           nullptr);
}

void CreatePanelControls(HWND hwnd) {
    AddText(hwnd, 18, 12, 640, 20, L"Native settings panel");
    g_state.status_label = AddText(hwnd, 18, 34, 640, 22, L"State: offline");

    AddGroup(hwnd, 14, 64, 320, 190, L"Input / session");
    g_state.ascii_button = AddButton(hwnd, kButtonAscii, 30, 92, 130, 30,
                                     L"Mode: Chinese");
    g_state.full_shape_button = AddButton(hwnd, kButtonFullShape, 172, 92, 130,
                                          30, L"Shape: Half");
    AddText(hwnd, 30, 132, 110, 20, L"Output standard");
    g_state.output_combo = AddCombo(hwnd, kComboOutputStandard, 146, 128, 156, 150);
    AddText(hwnd, 30, 170, 110, 20, L"Schema switch");
    g_state.schema_combo = AddCombo(hwnd, kComboSchema, 146, 166, 156, 150);
    AddDisabled(hwnd, 30, 208, 230, 24, L"Extended charset (coming soon)");

    AddGroup(hwnd, 354, 64, 330, 242, L"Appearance");
    AddText(hwnd, 370, 92, 80, 20, L"Skin");
    g_state.skin_combo = AddCombo(hwnd, kComboSkin, 450, 88, 190, 150);
    g_state.preview_window = CreateWindowExW(
        WS_EX_CLIENTEDGE, kPreviewClassName, L"",
        WS_CHILD | WS_VISIBLE, 370, 130, 292, 68, hwnd,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPreviewToolbar)),
        GetModuleHandleW(nullptr), nullptr);
    AddDisabled(hwnd, 370, 212, 250, 24, L"Candidate page size (coming soon)");
    AddDisabled(hwnd, 370, 238, 250, 24, L"Candidate layout (coming soon)");
    AddDisabled(hwnd, 370, 264, 250, 24, L"Romanization display (coming soon)");

    AddGroup(hwnd, 14, 270, 320, 145, L"Engine");
    AddDisabled(hwnd, 30, 298, 130, 24, L"Completion (coming soon)");
    AddDisabled(hwnd, 172, 298, 130, 24, L"Correction (coming soon)");
    AddDisabled(hwnd, 30, 326, 130, 24, L"Sentence mode (coming soon)");
    AddDisabled(hwnd, 172, 326, 130, 24, L"Prediction (coming soon)");
    AddDisabled(hwnd, 30, 354, 190, 24, L"Combine candidates (coming soon)");

    AddGroup(hwnd, 354, 322, 330, 96, L"Dictionary");
    AddDisabled(hwnd, 370, 350, 130, 26, L"Import userdb (coming soon)");
    AddDisabled(hwnd, 512, 350, 130, 26, L"Export userdb (coming soon)");

    AddGroup(hwnd, 14, 432, 670, 92, L"Schemas");
    AddText(hwnd, 30, 462, 356, 20,
            L"Installed schema switching is available above.");
    AddDisabled(hwnd, 30, 488, 180, 26, L"Import schema (coming soon)");
    AddButton(hwnd, kButtonRefresh, 548, 482, 110, 30, L"Refresh");
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
    state.dpi = GetDpiForWindow(hwnd);
    state.skin_name = g_state.toolbar_skin;

    const yune_windows::ToolbarSkin skin =
        yune_windows::LoadToolbarSkin(ModuleDirectory(), g_state.toolbar_skin);
    if (!g_state.preview_surface.PaintLanguageBarPreview(
            hwnd, dc, client, state, skin)) {
        FillRect(dc, &client, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));
        DrawTextW(dc, L"Toolbar preview unavailable", -1, &client,
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
        case WM_CREATE:
            CreatePanelControls(hwnd);
            RefreshState(hwnd, false);
            return 0;
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
                                    Narrow(SelectedComboText(g_state.output_combo)));
                    }
                    return 0;
                case kComboSchema:
                    if (notification == CBN_SELCHANGE) {
                        ApplySchema(hwnd, SelectedComboText(g_state.schema_combo));
                    }
                    return 0;
                case kComboSkin:
                    if (notification == CBN_SELCHANGE) {
                        ApplySkin(hwnd, SelectedComboText(g_state.skin_combo));
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
    g_state.skins = EnumerateInstalledSkins(ModuleDirectory());
    if (std::find(g_state.skins.begin(), g_state.skins.end(), L"default") ==
        g_state.skins.end()) {
        std::cerr << "default skin was not enumerated\n";
        return 1;
    }
    const char* state_json =
        "{\"ready\":true,\"state\":{\"schema_id\":\"jyut6ping3\","
        "\"ascii_mode\":false,\"full_shape\":true,"
        "\"output_standard\":\"hong_kong_traditional\","
        "\"toolbar\":{\"position_set\":false,\"x\":0,\"y\":0,"
        "\"skin\":\"default\"}},\"schemas\":[{\"schema_id\":\"jyut6ping3\"}]}\n";
    if (!ApplyStateJson(state_json) || g_state.toolbar_skin != L"default" ||
        g_state.schemas.empty()) {
        std::cerr << "settings state JSON self-test failed\n";
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

}  // namespace

int wmain(int argc, wchar_t** argv) {
    const HRESULT coinit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(coinit);
    if (argc == 2 && std::wstring(argv[1]) == L"--self-test") {
        const int result = SelfTest();
        if (should_uninit) {
            CoUninitialize();
        }
        return result;
    }

    HANDLE instance_mutex = CreateMutexW(nullptr, TRUE, kInstanceMutexName);
    const DWORD mutex_error = GetLastError();
    if (instance_mutex && mutex_error == ERROR_ALREADY_EXISTS) {
        FocusSettingsWindow(WaitForSettingsWindow(1500));
        CloseHandle(instance_mutex);
        if (should_uninit) {
            CoUninitialize();
        }
        return 0;
    }

    HWND existing = WaitForSettingsWindow(0);
    if (existing && IsWindow(existing)) {
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

    HWND hwnd = CreateWindowExW(WS_EX_APPWINDOW, kWindowClassName,
                                L"Yune Windows Settings",
                                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU |
                                    WS_MINIMIZEBOX,
                                CW_USEDEFAULT, CW_USEDEFAULT, 720, 580, nullptr,
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
