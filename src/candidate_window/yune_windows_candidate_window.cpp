#include "yune_windows_candidate_window.h"

#include <d2d1_1.h>
#include <d2d1helper.h>
#include <d3d11.h>
#include <dcomp.h>
#include <dwrite.h>
#include <dwmapi.h>
#include <dxgi1_2.h>
#include <uxtheme.h>
#include <wrl/client.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cwchar>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <new>
#include <sstream>

namespace yune_windows {
namespace {

using Microsoft::WRL::ComPtr;

constexpr const wchar_t* kClassName = L"YuneWindowsCandidateWindow";
constexpr const wchar_t* kLanguageBarClassName = L"YuneWindowsLanguageBar";
constexpr COLORREF kBorderColor = RGB(87, 93, 101);
constexpr COLORREF kBackgroundColor = RGB(255, 255, 255);
constexpr COLORREF kHighlightColor = RGB(229, 241, 255);
constexpr COLORREF kTextColor = RGB(20, 24, 31);
constexpr COLORREF kCommentColor = RGB(88, 94, 104);
constexpr int kLanguageBarDragThreshold = 4;
constexpr int kToolbarSegmentCount = 5;
constexpr UINT_PTR kLanguageBarForegroundTimer = 0x59554e45;
constexpr UINT kLanguageBarForegroundIntervalMs = 250;
constexpr const wchar_t* kToolbarSupersededMessageName =
    L"YuneWindows.ToolbarSuperseded.v1";

#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMSBT_TRANSIENTWINDOW
#define DWMSBT_TRANSIENTWINDOW 3
#endif
#ifndef DWMSBT_NONE
#define DWMSBT_NONE 1
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

float ScaleFloat(float value, UINT dpi) {
    return value * static_cast<float>(dpi == 0 ? 96 : dpi) / 96.0f;
}

D2D1_COLOR_F ToD2DColor(const ToolbarSkinColor& color) {
    return D2D1::ColorF(color.r, color.g, color.b, color.a);
}

HMODULE ModuleHandleFromAddress() {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&ModuleHandleFromAddress),
                            &module)) {
        return GetModuleHandleW(nullptr);
    }
    return module ? module : GetModuleHandleW(nullptr);
}

std::wstring ModuleScopedClassName(const wchar_t* base_name) {
    wchar_t buffer[128] = {};
    swprintf_s(buffer, L"%s_%p", base_name, ModuleHandleFromAddress());
    return buffer;
}

const std::wstring& CandidateWindowClassName() {
    static const std::wstring name = ModuleScopedClassName(kClassName);
    return name;
}

const std::wstring& LanguageBarClassName() {
    static const std::wstring name = ModuleScopedClassName(kLanguageBarClassName);
    return name;
}

UINT ToolbarSupersededMessage() {
    static const UINT message =
        RegisterWindowMessageW(kToolbarSupersededMessageName);
    return message;
}

std::mutex g_visible_toolbar_mutex;
HWND g_visible_toolbar = nullptr;

HWND RootOwnerWindow(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) {
        return nullptr;
    }
    HWND root = GetAncestor(hwnd, GA_ROOTOWNER);
    return root ? root : hwnd;
}

bool WindowOwnerMatchesForeground(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd) || !IsWindowVisible(hwnd)) {
        return false;
    }
    const HWND owner = GetWindow(hwnd, GW_OWNER);
    const HWND owner_root = RootOwnerWindow(owner);
    const HWND foreground_root = RootOwnerWindow(GetForegroundWindow());
    return owner_root && foreground_root && owner_root == foreground_root;
}

bool IsLanguageBarWindow(HWND hwnd) {
    wchar_t class_name[192] = {};
    if (!GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name))) {
        return false;
    }
    constexpr std::wstring_view prefix = L"YuneWindowsLanguageBar_";
    return std::wstring_view(class_name).starts_with(prefix);
}

struct SupersedeToolbarContext {
    HWND claimant = nullptr;
    UINT message = 0;
};

BOOL CALLBACK SupersedeToolbarWindow(HWND hwnd, LPARAM parameter) {
    auto* context =
        reinterpret_cast<SupersedeToolbarContext*>(parameter);
    if (!context || hwnd == context->claimant || !IsLanguageBarWindow(hwnd)) {
        return TRUE;
    }
    (void)PostMessageW(hwnd, context->message,
                       reinterpret_cast<WPARAM>(context->claimant), 0);
    return TRUE;
}

void SupersedeOtherToolbarWindows(HWND claimant) {
    SupersedeToolbarContext context = {claimant, ToolbarSupersededMessage()};
    if (context.message != 0) {
        (void)EnumWindows(&SupersedeToolbarWindow,
                          reinterpret_cast<LPARAM>(&context));
    }
}

std::filesystem::path ModuleDirectoryFromAddress() {
    HMODULE module = ModuleHandleFromAddress();
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(module, module_path, ARRAYSIZE(module_path))) {
        return {};
    }
    return std::filesystem::path(module_path).parent_path();
}

std::string NarrowAscii(std::wstring_view value) {
    std::string output;
    output.reserve(value.size());
    for (wchar_t ch : value) {
        output.push_back(ch >= 0 && ch <= 0x7f ? static_cast<char>(ch) : '_');
    }
    return output;
}

std::wstring WidenUtf8(std::string_view value) {
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

std::string ReadTextFileUtf8(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return {};
    }
    std::ostringstream buffer;
    buffer << in.rdbuf();
    return buffer.str();
}

std::string JsonStringValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\"";
    const size_t key_pos = json.find(needle);
    if (key_pos == std::string::npos) {
        return {};
    }
    const size_t colon_pos = json.find(':', key_pos + needle.size());
    if (colon_pos == std::string::npos) {
        return {};
    }
    const size_t quote_pos = json.find('"', colon_pos + 1);
    if (quote_pos == std::string::npos) {
        return {};
    }
    std::string output;
    for (size_t i = quote_pos + 1; i < json.size(); ++i) {
        const char ch = json[i];
        if (ch == '"') {
            return output;
        }
        if (ch == '\\' && i + 1 < json.size()) {
            const char escaped = json[++i];
            switch (escaped) {
                case 'n':
                    output.push_back('\n');
                    break;
                case 'r':
                    output.push_back('\r');
                    break;
                case 't':
                    output.push_back('\t');
                    break;
                case 'u':
                    if (i + 4 < json.size()) {
                        const std::string hex(json.substr(i + 1, 4));
                        wchar_t* end = nullptr;
                        const unsigned long code =
                            wcstoul(std::wstring(hex.begin(), hex.end()).c_str(),
                                    &end, 16);
                        if (end && *end == L'\0' && code <= 0xffff) {
                            const wchar_t wide = static_cast<wchar_t>(code);
                            std::string utf8(4, '\0');
                            const int bytes = WideCharToMultiByte(
                                CP_UTF8, 0, &wide, 1, utf8.data(),
                                static_cast<int>(utf8.size()), nullptr, nullptr);
                            if (bytes > 0) {
                                output.append(utf8.data(), bytes);
                            }
                        }
                        i += 4;
                    }
                    break;
                default:
                    output.push_back(escaped);
                    break;
            }
            continue;
        }
        output.push_back(ch);
    }
    return {};
}

bool JsonNumberValue(std::string_view json, std::string_view key, double* value) {
    const std::string needle = "\"" + std::string(key) + "\"";
    const size_t key_pos = json.find(needle);
    if (key_pos == std::string::npos) {
        return false;
    }
    const size_t colon_pos = json.find(':', key_pos + needle.size());
    if (colon_pos == std::string::npos) {
        return false;
    }
    size_t value_pos = colon_pos + 1;
    while (value_pos < json.size() &&
           static_cast<unsigned char>(json[value_pos]) <= 0x20) {
        ++value_pos;
    }
    size_t end_pos = value_pos;
    while (end_pos < json.size()) {
        const char ch = json[end_pos];
        if ((ch >= '0' && ch <= '9') || ch == '-' || ch == '+' || ch == '.') {
            ++end_pos;
            continue;
        }
        break;
    }
    if (end_pos == value_pos) {
        return false;
    }
    char* end = nullptr;
    const std::string number(json.substr(value_pos, end_pos - value_pos));
    const double parsed = strtod(number.c_str(), &end);
    if (!end || *end != '\0') {
        return false;
    }
    *value = parsed;
    return true;
}

int JsonIntValueOr(std::string_view json, std::string_view key, int fallback) {
    double value = 0.0;
    if (!JsonNumberValue(json, key, &value)) {
        return fallback;
    }
    return static_cast<int>(std::lround(value));
}

float JsonFloatValueOr(std::string_view json, std::string_view key,
                       float fallback) {
    double value = 0.0;
    if (!JsonNumberValue(json, key, &value)) {
        return fallback;
    }
    return static_cast<float>(value);
}

int HexNibble(char ch) {
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
        return ch - 'a' + 10;
    }
    if (ch >= 'A' && ch <= 'F') {
        return ch - 'A' + 10;
    }
    return -1;
}

bool ParseHexByte(std::string_view value, size_t offset, unsigned char* byte) {
    if (offset + 1 >= value.size()) {
        return false;
    }
    const int hi = HexNibble(value[offset]);
    const int lo = HexNibble(value[offset + 1]);
    if (hi < 0 || lo < 0) {
        return false;
    }
    *byte = static_cast<unsigned char>((hi << 4) | lo);
    return true;
}

bool ParseColor(std::string_view value, ToolbarSkinColor* color) {
    if (value.size() != 7 && value.size() != 9) {
        return false;
    }
    if (value[0] != '#') {
        return false;
    }
    unsigned char a = 255;
    unsigned char r = 0;
    unsigned char g = 0;
    unsigned char b = 0;
    size_t offset = 1;
    if (value.size() == 9) {
        if (!ParseHexByte(value, offset, &a)) {
            return false;
        }
        offset += 2;
    }
    if (!ParseHexByte(value, offset, &r) ||
        !ParseHexByte(value, offset + 2, &g) ||
        !ParseHexByte(value, offset + 4, &b)) {
        return false;
    }
    color->r = static_cast<float>(r) / 255.0f;
    color->g = static_cast<float>(g) / 255.0f;
    color->b = static_cast<float>(b) / 255.0f;
    color->a = static_cast<float>(a) / 255.0f;
    return true;
}

void LoadSkinColor(std::string_view json, std::string_view key,
                   ToolbarSkinColor* color) {
    const std::string value = JsonStringValue(json, key);
    if (!value.empty()) {
        (void)ParseColor(value, color);
    }
}

ToolbarGlassMechanism ParseGlassMechanism(std::string_view value) {
    if (value == "static_tint") {
        return ToolbarGlassMechanism::StaticTint;
    }
    return ToolbarGlassMechanism::DwmAcrylic;
}

bool IsSafeSkinName(std::wstring_view value) {
    if (value.empty() || value.size() > 64) {
        return false;
    }
    for (wchar_t ch : value) {
        if ((ch >= L'0' && ch <= L'9') || (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'a' && ch <= L'z') || ch == L'_' || ch == L'-') {
            continue;
        }
        return false;
    }
    return true;
}

bool IsControlOrMarker(wchar_t ch) {
    return ch < 0x20 || ch == 0x7f;
}

bool RegisterCandidateWindowClass() {
    static ATOM registered = 0;
    if (registered != 0) {
        return true;
    }

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hInstance = ModuleHandleFromAddress();
    wc.lpfnWndProc = NativeCandidateWindow::WindowProc;
    wc.lpszClassName = CandidateWindowClassName().c_str();
    wc.style = CS_HREDRAW | CS_VREDRAW;
    registered = RegisterClassExW(&wc);
    return registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

bool RegisterLanguageBarWindowClass() {
    static ATOM registered = 0;
    if (registered != 0) {
        return true;
    }

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hInstance = ModuleHandleFromAddress();
    wc.lpfnWndProc = LanguageBarWindow::WindowProc;
    wc.lpszClassName = LanguageBarClassName().c_str();
    wc.style = CS_HREDRAW | CS_VREDRAW;
    registered = RegisterClassExW(&wc);
    return registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

SIZE DesiredSize(const CandidateWindowState& state) {
    const int start =
        CandidatePageStartIndex(state.page_index, std::max(1, state.page_size));
    const int remaining =
        std::max(0, static_cast<int>(state.candidates.size()) - start);
    const int visible_rows =
        std::max(1, std::min(remaining, std::max(1, state.page_size)));
    const int page_indicator_rows =
        CandidatePageCount(static_cast<int>(state.candidates.size()),
                           state.page_size) > 1 ? 1 : 0;
    return {Scale(420, state.dpi),
            Scale(12 + visible_rows * 34 + page_indicator_rows * 22, state.dpi)};
}

void FillSolid(HDC dc, const RECT& rect, COLORREF color) {
    HBRUSH brush = CreateSolidBrush(color);
    FillRect(dc, &rect, brush);
    DeleteObject(brush);
}

std::wstring RowLabel(size_t index, const CandidateWindowCandidate& candidate) {
    std::wstring output = std::to_wstring(index + 1);
    output += L". ";
    output += candidate.text;
    return output;
}

SIZE LanguageBarDesiredSize(UINT dpi, const ToolbarSkin& skin) {
    return {Scale(std::max(270, skin.min_width), dpi),
            Scale(std::max(32, skin.height + skin.shadow_radius), dpi)};
}

std::wstring OutputStandardLabel(std::wstring_view value) {
    if (value == L"opencc_traditional") {
        return L"\x50b3";
    }
    if (value == L"hong_kong_traditional") {
        return L"\x6e2f";
    }
    if (value == L"taiwan_traditional") {
        return L"\x53f0";
    }
    if (value == L"mainland_simplified") {
        return L"\x7b80";
    }
    return L"\x6587";
}

std::wstring SchemaLabel(std::wstring_view value) {
    if (value == L"jyut6ping3") {
        return L"\x7cb5";
    }
    if (value == L"cangjie5") {
        return L"\x5009";
    }
    if (value == L"luna_pinyin" || value == L"luna_pinyin_octagram") {
        return L"\x6719";
    }
    return L"\x6cd5";
}

std::wstring SkinSegmentLabelOr(const ToolbarSkin& skin, size_t index,
                                std::wstring_view fallback) {
    if (index < skin.segment_labels.size() &&
        !skin.segment_labels[index].empty()) {
        return skin.segment_labels[index];
    }
    return std::wstring(fallback);
}

}  // namespace

std::wstring ToolbarSegmentLabelForState(LanguageBarSegment segment,
                                         const LanguageBarState& state,
                                         const ToolbarSkin& skin) {
    switch (segment) {
        case LanguageBarSegment::AsciiMode:
            return state.ascii_mode
                       ? L"\x82f1"
                       : SkinSegmentLabelOr(skin, 0, L"\x4e2d");
        case LanguageBarSegment::FullShape:
            return state.full_shape
                       ? L"\x5168"
                       : SkinSegmentLabelOr(skin, 1, L"\x534a");
        case LanguageBarSegment::OutputStandard:
            if (state.output_standard.empty() ||
                state.output_standard == L"hong_kong_traditional") {
                return SkinSegmentLabelOr(
                    skin, 2, OutputStandardLabel(state.output_standard));
            }
            return OutputStandardLabel(state.output_standard);
        case LanguageBarSegment::Schema:
            if (state.schema_id.empty() || state.schema_id == L"jyut6ping3") {
                return SkinSegmentLabelOr(skin, 3, SchemaLabel(state.schema_id));
            }
            return SchemaLabel(state.schema_id);
        case LanguageBarSegment::Settings:
            return SkinSegmentLabelOr(skin, 4, L"\x2699");
    }
    return L"";
}

std::wstring SanitizeCandidateComment(std::wstring_view raw_comment) {
    std::wstring output;
    output.reserve(raw_comment.size());

    for (size_t i = 0; i < raw_comment.size(); ++i) {
        const wchar_t ch = raw_comment[i];
        if (IsControlOrMarker(ch)) {
            continue;
        }
        if (ch == L'\\' && i + 1 < raw_comment.size() &&
            (raw_comment[i + 1] == L'f' || raw_comment[i + 1] == L'r')) {
            ++i;
            continue;
        }
        output.push_back(ch);
    }

    while (!output.empty() && (output.front() == L',' || output.front() == L' ')) {
        output.erase(output.begin());
    }
    while (!output.empty() && output.back() == L' ') {
        output.pop_back();
    }
    return output;
}

int ClampCandidateHighlight(int highlighted_index, int candidate_count) {
    if (candidate_count <= 0) {
        return 0;
    }
    return std::max(0, std::min(highlighted_index, candidate_count - 1));
}

int CandidatePageCount(int candidate_count, int page_size) {
    if (candidate_count <= 0) {
        return 1;
    }
    page_size = std::max(1, page_size);
    return (candidate_count + page_size - 1) / page_size;
}

int ClampCandidatePageIndex(int page_index, int candidate_count, int page_size) {
    const int page_count = CandidatePageCount(candidate_count, page_size);
    return std::max(0, std::min(page_index, page_count - 1));
}

int CandidatePageStartIndex(int page_index, int page_size) {
    return std::max(0, page_index) * std::max(1, page_size);
}

RECT ComputeCandidateWindowRect(const RECT& anchor, SIZE desired_size, UINT dpi) {
    RECT target = {
        anchor.left,
        anchor.bottom + Scale(6, dpi),
        anchor.left + desired_size.cx,
        anchor.bottom + Scale(6, dpi) + desired_size.cy,
    };

    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    if (monitor && GetMonitorInfoW(monitor, &info)) {
        const RECT work = info.rcWork;
        const int work_width = work.right - work.left;
        const int work_height = work.bottom - work.top;
        if ((target.right - target.left) > work_width) {
            target.left = work.left;
            target.right = work.right;
        }
        if ((target.bottom - target.top) > work_height) {
            target.top = work.top;
            target.bottom = work.bottom;
        }
        if (target.right > work.right) {
            const int width = target.right - target.left;
            target.left = work.right - width;
            target.right = work.right;
        }
        if (target.bottom > work.bottom) {
            const int height = target.bottom - target.top;
            target.bottom = anchor.top - Scale(6, dpi);
            target.top = target.bottom - height;
        }
        if (target.left < work.left) {
            const int width = target.right - target.left;
            target.left = work.left;
            target.right = target.left + width;
        }
        if (target.top < work.top) {
            const int height = target.bottom - target.top;
            target.top = work.top;
            target.bottom = target.top + height;
        }
    }

    return target;
}

ToolbarSkin LoadToolbarSkin(const std::filesystem::path& install_root,
                            std::wstring_view skin_name) {
    ToolbarSkin skin;
    const std::wstring safe_name =
        IsSafeSkinName(skin_name) ? std::wstring(skin_name) : L"default";
    const std::filesystem::path manifest =
        install_root / L"skins" / safe_name / L"theme.json";
    const std::string json = ReadTextFileUtf8(manifest);
    if (json.empty()) {
        return skin;
    }

    const std::string manifest_name = JsonStringValue(json, "name");
    if (!manifest_name.empty()) {
        skin.name = WidenUtf8(manifest_name);
    }
    const std::string font_family = JsonStringValue(json, "family");
    if (!font_family.empty()) {
        skin.font_family = WidenUtf8(font_family);
    }
    skin.font_size = std::max(9.0f, JsonFloatValueOr(json, "size", skin.font_size));
    skin.height = std::max(28, JsonIntValueOr(json, "height", skin.height));
    skin.min_width = std::max(180, JsonIntValueOr(json, "min_width", skin.min_width));
    skin.padding_x = std::max(4, JsonIntValueOr(json, "padding_x", skin.padding_x));
    skin.padding_y = std::max(2, JsonIntValueOr(json, "padding_y", skin.padding_y));
    skin.segment_gap = std::max(0, JsonIntValueOr(json, "segment_gap", skin.segment_gap));
    skin.corner_radius =
        std::max(4, JsonIntValueOr(json, "corner_radius", skin.corner_radius));
    skin.shadow_radius =
        std::max(0, JsonIntValueOr(json, "shadow_radius", skin.shadow_radius));

    LoadSkinColor(json, "background", &skin.background);
    LoadSkinColor(json, "text", &skin.text);
    LoadSkinColor(json, "accent", &skin.accent);
    LoadSkinColor(json, "hover", &skin.hover);
    LoadSkinColor(json, "pressed", &skin.pressed);
    LoadSkinColor(json, "separator", &skin.separator);
    LoadSkinColor(json, "shadow", &skin.shadow);
    const std::string glass_mechanism = JsonStringValue(json, "glass_mechanism");
    skin.glass_mechanism = ParseGlassMechanism(glass_mechanism);
    const std::string glass_fallback = JsonStringValue(json, "glass_fallback");
    if (!glass_fallback.empty()) {
        skin.glass_fallback = ParseGlassMechanism(glass_fallback);
    }

    const char* label_keys[kToolbarSegmentCount] = {
        "ascii", "shape", "standard", "schema", "settings"};
    for (int i = 0; i < kToolbarSegmentCount; ++i) {
        const std::string label = JsonStringValue(json, label_keys[i]);
        if (!label.empty()) {
            skin.segment_labels[static_cast<size_t>(i)] = WidenUtf8(label);
        }
    }
    return skin;
}

RECT ClampToolbarRectToVisibleMonitor(const RECT& desired_rect, UINT dpi) {
    RECT target = desired_rect;
    if (target.right <= target.left || target.bottom <= target.top) {
        target.right = target.left + Scale(268, dpi);
        target.bottom = target.top + Scale(42, dpi);
    }

    HMONITOR monitor = MonitorFromRect(&target, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    RECT work = {};
    if (monitor && GetMonitorInfoW(monitor, &info)) {
        work = info.rcWork;
    } else {
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    }

    const int width = target.right - target.left;
    const int height = target.bottom - target.top;
    const int work_width = work.right - work.left;
    const int work_height = work.bottom - work.top;
    if (width >= work_width) {
        target.left = work.left;
        target.right = work.right;
    } else {
        if (target.left < work.left) {
            target.left = work.left;
            target.right = target.left + width;
        }
        if (target.right > work.right) {
            target.right = work.right;
            target.left = target.right - width;
        }
    }
    if (height >= work_height) {
        target.top = work.top;
        target.bottom = work.bottom;
    } else {
        if (target.top < work.top) {
            target.top = work.top;
            target.bottom = target.top + height;
        }
        if (target.bottom > work.bottom) {
            target.bottom = work.bottom;
            target.top = target.bottom - height;
        }
    }
    return target;
}

RECT ComputeToolbarWindowRect(const RECT& anchor, SIZE desired_size, UINT dpi,
                              const ToolbarPosition& saved_position) {
    RECT target = {};
    if (saved_position.present) {
        target.left = saved_position.x;
        target.top = saved_position.y;
        target.right = target.left + desired_size.cx;
        target.bottom = target.top + desired_size.cy;
        return ClampToolbarRectToVisibleMonitor(target, dpi);
    }

    target.left = anchor.left;
    target.top = anchor.top;
    if (target.left == 0 && target.top == 0) {
        RECT work = {};
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
        target.right = work.right - Scale(12, dpi);
        target.left = target.right - desired_size.cx;
        target.top = work.top + Scale(12, dpi);
    }
    target.right = target.left + desired_size.cx;
    target.bottom = target.top + desired_size.cy;
    return ClampToolbarRectToVisibleMonitor(target, dpi);
}

DWORD WindowsBuildNumber() {
    using RtlGetVersionProc = LONG(WINAPI*)(OSVERSIONINFOW*);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    auto rtl_get_version = ntdll ? reinterpret_cast<RtlGetVersionProc>(
                                      GetProcAddress(ntdll, "RtlGetVersion"))
                                : nullptr;
    if (!rtl_get_version) {
        return 0;
    }
    OSVERSIONINFOW version = {};
    version.dwOSVersionInfoSize = sizeof(version);
    if (rtl_get_version(&version) != 0) {
        return 0;
    }
    return version.dwBuildNumber;
}

// The OS build number does not change during a session; cache it so per-present
// render paths do not repeatedly probe ntdll.
DWORD CachedWindowsBuildNumber() {
    static const DWORD build = WindowsBuildNumber();
    return build;
}

namespace {

#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
ToolbarBackdropTestHooks g_toolbar_backdrop_test_hooks;
#endif

DWORD EffectiveWindowsBuildNumber() {
#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
    if (g_toolbar_backdrop_test_hooks.windows_build_number != 0) {
        return g_toolbar_backdrop_test_hooks.windows_build_number;
    }
#endif
    return CachedWindowsBuildNumber();
}

HRESULT SetToolbarWindowAttribute(HWND hwnd, DWORD attribute,
                                  const void* value, DWORD value_size) {
#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
    if (g_toolbar_backdrop_test_hooks.set_window_attribute) {
        return g_toolbar_backdrop_test_hooks.set_window_attribute(
            hwnd, attribute, value, value_size);
    }
#endif
    return DwmSetWindowAttribute(hwnd, attribute, value, value_size);
}

HRESULT ExtendToolbarFrame(HWND hwnd, const MARGINS& margins) {
#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
    if (g_toolbar_backdrop_test_hooks.extend_frame) {
        return g_toolbar_backdrop_test_hooks.extend_frame(
            hwnd, margins.cxLeftWidth, margins.cxRightWidth,
            margins.cyTopHeight, margins.cyBottomHeight);
    }
#endif
    return DwmExtendFrameIntoClientArea(hwnd, &margins);
}

ToolbarSkinColor EffectiveToolbarPillBackground(
    const ToolbarSkin& skin, bool acrylic_backdrop_active) {
    ToolbarSkinColor background = skin.background;
    if (!acrylic_backdrop_active) {
        background.a = 1.0f;
    }
    return background;
}

}  // namespace

#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
void SetToolbarBackdropTestHooksForTesting(
    const ToolbarBackdropTestHooks* hooks) {
    g_toolbar_backdrop_test_hooks = hooks ? *hooks : ToolbarBackdropTestHooks{};
}

ToolbarSkinColor EffectiveToolbarPillBackgroundForTesting(
    const ToolbarSkin& skin, bool acrylic_backdrop_active) {
    return EffectiveToolbarPillBackground(skin, acrylic_backdrop_active);
}
#endif

bool ApplyDwmTransientAcrylic(HWND hwnd) {
    // DWMWA_SYSTEMBACKDROP_TYPE is supported starting with Windows 11 22621.
    if (!hwnd || EffectiveWindowsBuildNumber() < 22621) {
        return false;
    }
    const MARGINS sheet = {-1, -1, -1, -1};
    if (FAILED(ExtendToolbarFrame(hwnd, sheet))) {
        return false;
    }
    const DWORD corner = DWMWCP_ROUND;
    (void)SetToolbarWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                                    &corner, sizeof(corner));
    const DWORD backdrop = DWMSBT_TRANSIENTWINDOW;
    return SUCCEEDED(SetToolbarWindowAttribute(
        hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop, sizeof(backdrop)));
}

void ClearToolbarGlassBackdrop(HWND hwnd) {
    if (!hwnd) {
        return;
    }
    if (EffectiveWindowsBuildNumber() >= 22621) {
        const DWORD backdrop = DWMSBT_NONE;
        (void)SetToolbarWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE,
                                        &backdrop, sizeof(backdrop));
    }
    const MARGINS client_only = {0, 0, 0, 0};
    (void)ExtendToolbarFrame(hwnd, client_only);
}

bool ApplyToolbarGlassBackdrop(HWND hwnd, const ToolbarSkin& skin) {
    if (!hwnd) {
        return false;
    }
    if (skin.glass_mechanism == ToolbarGlassMechanism::DwmAcrylic &&
        ApplyDwmTransientAcrylic(hwnd)) {
        return true;
    }
    if (skin.glass_fallback == ToolbarGlassMechanism::DwmAcrylic &&
        skin.glass_fallback != skin.glass_mechanism &&
        ApplyDwmTransientAcrylic(hwnd)) {
        return true;
    }
    ClearToolbarGlassBackdrop(hwnd);
    return false;
}

bool IsDeviceLoss(HRESULT hr) {
    return hr == D2DERR_RECREATE_TARGET ||
           hr == DXGI_ERROR_DEVICE_REMOVED ||
           hr == DXGI_ERROR_DEVICE_RESET ||
           hr == DXGI_ERROR_DEVICE_HUNG;
}

struct D2DSurface::Impl {
    ComPtr<ID2D1Factory> d2d_factory;
    ComPtr<IDWriteFactory> dwrite_factory;
};

HRESULT DrawLanguageBarContent(ID2D1RenderTarget* target,
                               IDWriteFactory* dwrite_factory,
                               SIZE size,
                               const LanguageBarState& state,
                               const ToolbarSkin& skin,
                               LanguageBarSegment hover_segment,
                               LanguageBarSegment pressed_segment,
                               bool has_hover,
                               bool has_pressed,
                               bool acrylic_backdrop_active,
                               D2D1_COLOR_F clear_color) {
    target->Clear(clear_color);

    ComPtr<ID2D1SolidColorBrush> brush;
    if (SUCCEEDED(target->CreateSolidColorBrush(ToD2DColor(skin.shadow),
                                                &brush))) {
        const float shadow =
            ScaleFloat(static_cast<float>(skin.shadow_radius), state.dpi);
        const D2D1_ROUNDED_RECT shadow_rect = D2D1::RoundedRect(
            D2D1::RectF(shadow * 0.55f, shadow * 0.70f,
                        static_cast<float>(size.cx) - shadow * 0.45f,
                        static_cast<float>(size.cy) - shadow * 0.35f),
            ScaleFloat(static_cast<float>(skin.corner_radius), state.dpi),
            ScaleFloat(static_cast<float>(skin.corner_radius), state.dpi));
        target->FillRoundedRectangle(shadow_rect, brush.Get());
        brush.Reset();
    }

    const float shadow_offset =
        ScaleFloat(static_cast<float>(skin.shadow_radius), state.dpi);
    const float pill_left = shadow_offset * 0.35f;
    const float pill_top = shadow_offset * 0.15f;
    const float pill_right = static_cast<float>(size.cx) - shadow_offset * 0.35f;
    const float pill_bottom =
        std::min(static_cast<float>(size.cy) - shadow_offset * 0.45f,
                 pill_top + ScaleFloat(static_cast<float>(skin.height),
                                       state.dpi));
    const float radius =
        ScaleFloat(static_cast<float>(skin.corner_radius), state.dpi);
    const D2D1_ROUNDED_RECT pill =
        D2D1::RoundedRect(D2D1::RectF(pill_left, pill_top, pill_right,
                                      pill_bottom),
                          radius, radius);
    // On the flat path (Windows 10, or any skin without the acrylic backdrop) the
    // composition surface is transparent with nothing frosting behind it, so a
    // low-alpha pill would show the live desktop through it and wash out the text.
    // Force the pill opaque there; keep the skin's glass alpha when acrylic is on.
    const ToolbarSkinColor pill_background =
        EffectiveToolbarPillBackground(skin, acrylic_backdrop_active);
    if (SUCCEEDED(target->CreateSolidColorBrush(ToD2DColor(pill_background),
                                                &brush))) {
        target->FillRoundedRectangle(pill, brush.Get());
        brush.Reset();
    }

    const float grip_width = ScaleFloat(24.0f, state.dpi);
    const float segment_left = pill_left + grip_width;
    const float segment_width = std::max(
        1.0f, (pill_right - segment_left -
               ScaleFloat(static_cast<float>(skin.padding_x), state.dpi)) /
                  static_cast<float>(kToolbarSegmentCount));

    if (SUCCEEDED(target->CreateSolidColorBrush(ToD2DColor(skin.separator),
                                                &brush))) {
        for (int i = 0; i < kToolbarSegmentCount - 1; ++i) {
            const float x = segment_left + segment_width * (i + 1);
            target->DrawLine(
                D2D1::Point2F(x, pill_top + ScaleFloat(9.0f, state.dpi)),
                D2D1::Point2F(x, pill_bottom - ScaleFloat(9.0f, state.dpi)),
                brush.Get(), ScaleFloat(1.0f, state.dpi));
        }
        const float dot_x = pill_left + ScaleFloat(9.0f, state.dpi);
        const float dot_gap = ScaleFloat(5.0f, state.dpi);
        for (int i = 0; i < 3; ++i) {
            const D2D1_ELLIPSE dot = D2D1::Ellipse(
                D2D1::Point2F(dot_x, (pill_top + pill_bottom) * 0.5f +
                                         (static_cast<float>(i) - 1.0f) * dot_gap),
                ScaleFloat(1.2f, state.dpi), ScaleFloat(1.2f, state.dpi));
            target->FillEllipse(dot, brush.Get());
        }
        brush.Reset();
    }

    const LanguageBarSegment segments[kToolbarSegmentCount] = {
        LanguageBarSegment::AsciiMode,
        LanguageBarSegment::FullShape,
        LanguageBarSegment::OutputStandard,
        LanguageBarSegment::Schema,
        LanguageBarSegment::Settings,
    };
    ComPtr<IDWriteTextFormat> text_format;
    HRESULT hr = dwrite_factory->CreateTextFormat(
        skin.font_family.c_str(), nullptr, DWRITE_FONT_WEIGHT_SEMI_BOLD,
        DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        ScaleFloat(skin.font_size, state.dpi), L"", &text_format);
    if (FAILED(hr)) {
        return hr;
    }
    text_format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
    text_format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    for (int i = 0; i < kToolbarSegmentCount; ++i) {
        const float left = segment_left + segment_width * i;
        const D2D1_RECT_F segment_rect =
            D2D1::RectF(left + ScaleFloat(3.0f, state.dpi),
                        pill_top + ScaleFloat(4.0f, state.dpi),
                        left + segment_width - ScaleFloat(3.0f, state.dpi),
                        pill_bottom - ScaleFloat(4.0f, state.dpi));
        const bool pressed = has_pressed && pressed_segment == segments[i];
        const bool hover = has_hover && hover_segment == segments[i];
        if ((pressed || hover) &&
            SUCCEEDED(target->CreateSolidColorBrush(
                ToD2DColor(pressed ? skin.pressed : skin.hover), &brush))) {
            const D2D1_ROUNDED_RECT hover_rect =
                D2D1::RoundedRect(segment_rect,
                                  ScaleFloat(12.0f, state.dpi),
                                  ScaleFloat(12.0f, state.dpi));
            target->FillRoundedRectangle(hover_rect, brush.Get());
            brush.Reset();
        }

        ToolbarSkinColor text_color = skin.text;
        if ((segments[i] == LanguageBarSegment::AsciiMode &&
             !state.ascii_mode) ||
            (segments[i] == LanguageBarSegment::FullShape &&
             state.full_shape)) {
            text_color = skin.accent;
        }
        if (SUCCEEDED(target->CreateSolidColorBrush(ToD2DColor(text_color),
                                                    &brush))) {
            const std::wstring label =
                ToolbarSegmentLabelForState(segments[i], state, skin);
            target->DrawTextW(label.c_str(), static_cast<UINT32>(label.size()),
                              text_format.Get(), segment_rect, brush.Get(),
                              D2D1_DRAW_TEXT_OPTIONS_CLIP);
            brush.Reset();
        }
    }
    return S_OK;
}

D2DSurface::~D2DSurface() {
    delete impl_;
    impl_ = nullptr;
}

bool D2DSurface::EnsureFactories() {
    if (!impl_) {
        impl_ = new (std::nothrow) Impl();
        if (!impl_) {
            return false;
        }
    }
    if (!impl_->d2d_factory) {
        if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                                     IID_PPV_ARGS(&impl_->d2d_factory)))) {
            return false;
        }
    }
    if (!impl_->dwrite_factory) {
        if (FAILED(DWriteCreateFactory(
                DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                reinterpret_cast<IUnknown**>(
                    impl_->dwrite_factory.GetAddressOf())))) {
            return false;
        }
    }
    return true;
}

void D2DSurface::DiscardDeviceResources() {
    if (impl_) {
        impl_->d2d_factory.Reset();
        impl_->dwrite_factory.Reset();
    }
}

bool D2DSurface::PaintLanguageBarPreview(HWND hwnd, HDC dc, const RECT& bounds,
                                         const LanguageBarState& state,
                                         const ToolbarSkin& skin) {
    if (!hwnd || !dc || !EnsureFactories()) {
        return false;
    }
    const int width =
        std::max(1, static_cast<int>(bounds.right - bounds.left));
    const int height =
        std::max(1, static_cast<int>(bounds.bottom - bounds.top));

    ComPtr<ID2D1DCRenderTarget> target;
    D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                          D2D1_ALPHA_MODE_IGNORE),
        // 96 DPI (1 DIP = 1 px); ScaleFloat already applies DPI (avoid double-scale).
        96.0f, 96.0f);
    HRESULT hr = impl_->d2d_factory->CreateDCRenderTarget(&properties, &target);
    if (SUCCEEDED(hr)) {
        RECT bind_rect = bounds;
        hr = target->BindDC(dc, &bind_rect);
    }
    if (FAILED(hr)) {
        return false;
    }

    target->BeginDraw();
    const HRESULT draw_hr = DrawLanguageBarContent(
        target.Get(), impl_->dwrite_factory.Get(), {width, height}, state, skin,
        LanguageBarSegment::Settings, LanguageBarSegment::Settings, false, false,
        false, D2D1::ColorF(0.96f, 0.97f, 0.98f, 1.0f));
    const HRESULT end_hr = target->EndDraw();
    hr = FAILED(draw_hr) ? draw_hr : end_hr;
    if (hr == D2DERR_RECREATE_TARGET) {
        DiscardDeviceResources();
        return false;
    }
    return SUCCEEDED(hr);
}

struct GlassSurface::Impl {
    ComPtr<ID3D11Device> d3d_device;
    ComPtr<IDXGIDevice> dxgi_device;
    ComPtr<ID2D1Factory1> d2d_factory;
    ComPtr<ID2D1Device> d2d_device;
    ComPtr<ID2D1DeviceContext> d2d_context;
    ComPtr<IDWriteFactory> dwrite_factory;
    ComPtr<IDCompositionDevice> dcomp_device;
    ComPtr<IDCompositionTarget> dcomp_target;
    ComPtr<IDCompositionVisual> dcomp_visual;
    ComPtr<IDCompositionSurface> dcomp_surface;
    HWND hwnd = nullptr;
    SIZE surface_size = {0, 0};
    ToolbarGlassMechanism requested_backdrop =
        ToolbarGlassMechanism::StaticTint;
    ToolbarGlassMechanism requested_fallback =
        ToolbarGlassMechanism::StaticTint;
    bool backdrop_configured = false;
    bool acrylic_backdrop_active = false;
};

GlassSurface::~GlassSurface() {
    DiscardDeviceResources();
}

#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
bool GlassSurface::acrylic_backdrop_active_for_testing() const {
    return impl_ && impl_->acrylic_backdrop_active;
}
#endif

bool GlassSurface::EnsureDeviceResources(HWND hwnd, SIZE size,
                                         const ToolbarSkin& skin) {
    if (!hwnd || size.cx <= 0 || size.cy <= 0) {
        return false;
    }
    if (!impl_) {
        impl_ = new (std::nothrow) Impl();
        if (!impl_) {
            return false;
        }
    }
    if (impl_->dcomp_surface && impl_->d2d_context && impl_->dwrite_factory &&
        impl_->hwnd == hwnd && impl_->surface_size.cx == size.cx &&
        impl_->surface_size.cy == size.cy) {
        if (!impl_->backdrop_configured ||
            impl_->requested_backdrop != skin.glass_mechanism ||
            impl_->requested_fallback != skin.glass_fallback) {
            impl_->requested_backdrop = skin.glass_mechanism;
            impl_->requested_fallback = skin.glass_fallback;
            impl_->acrylic_backdrop_active =
                ApplyToolbarGlassBackdrop(hwnd, skin);
            impl_->backdrop_configured = true;
        }
        return true;
    }

    impl_->d3d_device.Reset();
    impl_->dxgi_device.Reset();
    impl_->d2d_factory.Reset();
    impl_->d2d_device.Reset();
    impl_->d2d_context.Reset();
    impl_->dwrite_factory.Reset();
    impl_->dcomp_device.Reset();
    impl_->dcomp_target.Reset();
    impl_->dcomp_visual.Reset();
    impl_->dcomp_surface.Reset();

    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
        &impl_->d3d_device, nullptr, nullptr);
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(
            nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
            &impl_->d3d_device, nullptr, nullptr);
    }
    if (FAILED(hr) || FAILED(impl_->d3d_device.As(&impl_->dxgi_device))) {
        DiscardDeviceResources();
        return false;
    }

    hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                           IID_PPV_ARGS(&impl_->d2d_factory));
    if (SUCCEEDED(hr)) {
        hr = impl_->d2d_factory->CreateDevice(impl_->dxgi_device.Get(),
                                              &impl_->d2d_device);
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->d2d_device->CreateDeviceContext(
            D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &impl_->d2d_context);
    }
    if (SUCCEEDED(hr)) {
        impl_->d2d_context->SetDpi(96.0f, 96.0f);
        hr = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown**>(
                impl_->dwrite_factory.GetAddressOf()));
    }
    if (SUCCEEDED(hr)) {
        hr = DCompositionCreateDevice(
            impl_->dxgi_device.Get(), __uuidof(IDCompositionDevice),
            reinterpret_cast<void**>(impl_->dcomp_device.GetAddressOf()));
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->dcomp_device->CreateTargetForHwnd(
            hwnd, TRUE, &impl_->dcomp_target);
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->dcomp_device->CreateVisual(&impl_->dcomp_visual);
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->dcomp_device->CreateSurface(
            static_cast<UINT>(size.cx), static_cast<UINT>(size.cy),
            DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_ALPHA_MODE_PREMULTIPLIED,
            &impl_->dcomp_surface);
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->dcomp_visual->SetContent(impl_->dcomp_surface.Get());
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->dcomp_target->SetRoot(impl_->dcomp_visual.Get());
    }
    if (SUCCEEDED(hr)) {
        hr = impl_->dcomp_device->Commit();
    }
    if (FAILED(hr)) {
        DiscardDeviceResources();
        return false;
    }

    impl_->hwnd = hwnd;
    impl_->surface_size = size;
    if (!impl_->backdrop_configured ||
        impl_->requested_backdrop != skin.glass_mechanism ||
        impl_->requested_fallback != skin.glass_fallback) {
        impl_->requested_backdrop = skin.glass_mechanism;
        impl_->requested_fallback = skin.glass_fallback;
        impl_->acrylic_backdrop_active =
            ApplyToolbarGlassBackdrop(hwnd, skin);
        impl_->backdrop_configured = true;
    }
    return true;
}

HRESULT GlassSurface::RenderLanguageBar(const LanguageBarState& state,
                                        const ToolbarSkin& skin,
                                        LanguageBarSegment hover_segment,
                                        LanguageBarSegment pressed_segment,
                                        bool has_hover,
                                        bool has_pressed) {
    if (!impl_ || !impl_->dcomp_surface || !impl_->d2d_context ||
        !impl_->dwrite_factory) {
        return E_FAIL;
    }

    ComPtr<IDXGISurface> dxgi_surface;
    POINT offset = {};
    HRESULT hr = impl_->dcomp_surface->BeginDraw(
        nullptr, __uuidof(IDXGISurface),
        reinterpret_cast<void**>(dxgi_surface.GetAddressOf()), &offset);
    if (FAILED(hr)) {
        return hr;
    }

    D2D1_BITMAP_PROPERTIES1 properties = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                          D2D1_ALPHA_MODE_PREMULTIPLIED));
    ComPtr<ID2D1Bitmap1> bitmap;
    hr = impl_->d2d_context->CreateBitmapFromDxgiSurface(
        dxgi_surface.Get(), &properties, &bitmap);
    if (FAILED(hr)) {
        const HRESULT end_surface_hr = impl_->dcomp_surface->EndDraw();
        return FAILED(end_surface_hr) ? end_surface_hr : hr;
    }

    impl_->d2d_context->SetTarget(bitmap.Get());
    impl_->d2d_context->BeginDraw();
    impl_->d2d_context->SetTransform(D2D1::Matrix3x2F::Translation(
        static_cast<float>(offset.x), static_cast<float>(offset.y)));
    const HRESULT draw_hr = DrawLanguageBarContent(
        impl_->d2d_context.Get(), impl_->dwrite_factory.Get(),
        impl_->surface_size, state, skin, hover_segment, pressed_segment,
        has_hover, has_pressed, impl_->acrylic_backdrop_active,
        D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));
    const HRESULT end_draw_hr = impl_->d2d_context->EndDraw();
    impl_->d2d_context->SetTransform(D2D1::Matrix3x2F::Identity());
    impl_->d2d_context->SetTarget(nullptr);
    const HRESULT end_surface_hr = impl_->dcomp_surface->EndDraw();
    if (FAILED(draw_hr)) {
        return draw_hr;
    }
    if (FAILED(end_draw_hr)) {
        return end_draw_hr;
    }
    if (FAILED(end_surface_hr)) {
        return end_surface_hr;
    }
    return impl_->dcomp_device->Commit();
}

bool GlassSurface::PresentLanguageBar(HWND hwnd, const LanguageBarState& state,
                                      const ToolbarSkin& skin,
                                      LanguageBarSegment hover_segment,
                                      LanguageBarSegment pressed_segment,
                                      bool has_hover,
                                      bool has_pressed) {
    if (!hwnd) {
        return false;
    }
    RECT window_rect = {};
    if (!GetWindowRect(hwnd, &window_rect)) {
        return false;
    }
    const SIZE size = {
        std::max(1, static_cast<int>(window_rect.right - window_rect.left)),
        std::max(1, static_cast<int>(window_rect.bottom - window_rect.top)),
    };
    if (!EnsureDeviceResources(hwnd, size, skin)) {
        return false;
    }
    HRESULT hr = RenderLanguageBar(state, skin, hover_segment, pressed_segment,
                                   has_hover, has_pressed);
    if (SUCCEEDED(hr)) {
        return true;
    }

    DiscardDeviceResources();
    if (!IsDeviceLoss(hr) || !EnsureDeviceResources(hwnd, size, skin)) {
        return false;
    }
    hr = RenderLanguageBar(state, skin, hover_segment, pressed_segment,
                           has_hover, has_pressed);
    if (FAILED(hr)) {
        DiscardDeviceResources();
        return false;
    }
    return true;
}

bool GlassSurface::PaintLanguageBarPreview(HWND hwnd, HDC dc, const RECT& bounds,
                                           const LanguageBarState& state,
                                           const ToolbarSkin& skin) {
    return preview_surface_.PaintLanguageBarPreview(hwnd, dc, bounds, state, skin);
}

void GlassSurface::DiscardDeviceResources() {
    if (impl_ && impl_->hwnd && impl_->backdrop_configured) {
        ClearToolbarGlassBackdrop(impl_->hwnd);
    }
    delete impl_;
    impl_ = nullptr;
    preview_surface_.DiscardDeviceResources();
}

NativeCandidateWindow::~NativeCandidateWindow() {
    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
}

bool NativeCandidateWindow::EnsureCreated(HWND owner) {
    if (hwnd_) {
        if (owner_ != owner) {
            SetWindowLongPtrW(hwnd_, GWLP_HWNDPARENT,
                              reinterpret_cast<LONG_PTR>(owner));
            owner_ = owner;
        }
        return true;
    }
    if (!RegisterCandidateWindowClass()) {
        return false;
    }

    hwnd_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                            CandidateWindowClassName().c_str(),
                            L"YuneWindows Candidates", WS_POPUP, 0, 0, 1, 1,
                            owner, nullptr, ModuleHandleFromAddress(), this);
    owner_ = owner;
    return hwnd_ != nullptr;
}

bool NativeCandidateWindow::Update(const CandidateWindowState& state, bool show) {
    if (!EnsureCreated(state.owner)) {
        return false;
    }

    state_ = state;
    state_.page_size = std::max(1, state_.page_size);
    state_.page_index = ClampCandidatePageIndex(
        state_.page_index, static_cast<int>(state_.candidates.size()),
        state_.page_size);
    const int page_start =
        CandidatePageStartIndex(state_.page_index, state_.page_size);
    const int visible_count =
        std::min(state_.page_size,
                 std::max(0, static_cast<int>(state_.candidates.size()) -
                                  page_start));
    state_.highlighted_index = ClampCandidateHighlight(
        state_.highlighted_index, visible_count);
    for (auto& candidate : state_.candidates) {
        candidate.comment = SanitizeCandidateComment(candidate.comment);
    }

    if (show && !ForegroundMatchesOwner()) {
        Hide();
        return true;
    }

    const SIZE desired = DesiredSize(state_);
    const RECT rect = ComputeCandidateWindowRect(state_.anchor, desired, state_.dpi);
    SetWindowPos(hwnd_, HWND_TOPMOST, rect.left, rect.top, rect.right - rect.left,
                 rect.bottom - rect.top,
                 SWP_NOACTIVATE | (show ? SWP_SHOWWINDOW : SWP_NOZORDER));
    InvalidateRect(hwnd_, nullptr, TRUE);
    if (show) {
        UpdateWindow(hwnd_);
    }
    return true;
}

void NativeCandidateWindow::Hide() {
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

bool NativeCandidateWindow::ForegroundMatchesOwner() const {
    if (!owner_ || !IsWindow(owner_)) {
        return true;
    }
    HWND foreground = GetForegroundWindow();
    if (!foreground || foreground == hwnd_ || foreground == owner_ ||
        IsChild(owner_, foreground)) {
        return true;
    }
    HWND owner_root = GetAncestor(owner_, GA_ROOTOWNER);
    HWND foreground_root = GetAncestor(foreground, GA_ROOTOWNER);
    return owner_root && foreground_root && owner_root == foreground_root;
}

LRESULT CALLBACK NativeCandidateWindow::WindowProc(HWND hwnd, UINT message,
                                                   WPARAM wparam, LPARAM lparam) {
    NativeCandidateWindow* window =
        reinterpret_cast<NativeCandidateWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
        window = reinterpret_cast<NativeCandidateWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
        if (window) {
            window->hwnd_ = hwnd;
            return TRUE;
        }
    }
    if (window) {
        if (!window->hwnd_) {
            window->hwnd_ = hwnd;
        }
        return window->HandleMessage(message, wparam, lparam);
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT NativeCandidateWindow::HandleMessage(UINT message, WPARAM wparam,
                                             LPARAM lparam) {
    switch (message) {
        case WM_PAINT:
            Paint();
            return 0;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_NCHITTEST:
            return HTTRANSPARENT;
        default:
            return DefWindowProcW(hwnd_, message, wparam, lparam);
    }
}

void NativeCandidateWindow::Paint() {
    PAINTSTRUCT ps = {};
    HDC dc = BeginPaint(hwnd_, &ps);
    RECT client = {};
    GetClientRect(hwnd_, &client);

    FillSolid(dc, client, kBackgroundColor);
    HPEN border_pen = CreatePen(PS_SOLID, Scale(1, state_.dpi), kBorderColor);
    HGDIOBJ old_pen = SelectObject(dc, border_pen);
    HGDIOBJ old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    Rectangle(dc, client.left, client.top, client.right, client.bottom);
    SelectObject(dc, old_brush);
    SelectObject(dc, old_pen);
    DeleteObject(border_pen);

    HFONT font = CreateFontW(-Scale(17, state_.dpi), 0, 0, 0, FW_NORMAL, FALSE,
                             FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HGDIOBJ old_font = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);

    const int row_height = Scale(34, state_.dpi);
    const int padding = Scale(8, state_.dpi);
    const int page_start =
        CandidatePageStartIndex(state_.page_index, state_.page_size);
    const int visible_rows =
        std::min(state_.page_size,
                 std::max(0, static_cast<int>(state_.candidates.size()) -
                                  page_start));
    for (int i = 0; i < visible_rows; ++i) {
        const int candidate_index = page_start + i;
        RECT row = {padding, padding + i * row_height, client.right - padding,
                    padding + (i + 1) * row_height};
        if (i == state_.highlighted_index) {
            FillSolid(dc, row, kHighlightColor);
        }
        RECT text_rect = row;
        text_rect.left += Scale(8, state_.dpi);
        text_rect.right = text_rect.left + Scale(190, state_.dpi);
        SetTextColor(dc, kTextColor);
        const std::wstring label =
            RowLabel(static_cast<size_t>(i),
                     state_.candidates[static_cast<size_t>(candidate_index)]);
        DrawTextW(dc, label.c_str(), static_cast<int>(label.size()), &text_rect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

        RECT comment_rect = row;
        comment_rect.left += Scale(210, state_.dpi);
        comment_rect.right -= Scale(8, state_.dpi);
        SetTextColor(dc, kCommentColor);
        const std::wstring& comment =
            state_.candidates[static_cast<size_t>(candidate_index)].comment;
        DrawTextW(dc, comment.c_str(), static_cast<int>(comment.size()),
                  &comment_rect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }

    const int page_count =
        CandidatePageCount(static_cast<int>(state_.candidates.size()),
                           state_.page_size);
    if (page_count > 1) {
        RECT page_rect = {padding,
                          padding + visible_rows * row_height,
                          client.right - padding,
                          client.bottom - padding};
        std::wstring page_label = L"Page ";
        page_label += std::to_wstring(state_.page_index + 1);
        page_label += L"/";
        page_label += std::to_wstring(page_count);
        SetTextColor(dc, kCommentColor);
        DrawTextW(dc, page_label.c_str(), static_cast<int>(page_label.size()),
                  &page_rect,
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }

    SelectObject(dc, old_font);
    DeleteObject(font);
    EndPaint(hwnd_, &ps);
}

LanguageBarWindow::~LanguageBarWindow() {
    if (hwnd_) {
        DestroyWindow(hwnd_);
    }
}

void LanguageBarWindow::SetClickHandler(LanguageBarClickHandler handler,
                                        void* context) {
    click_handler_ = handler;
    click_context_ = context;
}

void LanguageBarWindow::SetPositionChangedHandler(
    LanguageBarPositionChangedHandler handler, void* context) {
    position_changed_handler_ = handler;
    position_changed_context_ = context;
}

bool LanguageBarWindow::EnsureCreated(HWND owner) {
    owner = RootOwnerWindow(owner);
    if (!owner) {
        return false;
    }
    if (hwnd_) {
        const HWND actual_owner = RootOwnerWindow(GetWindow(hwnd_, GW_OWNER));
        if (actual_owner != owner) {
            SetLastError(ERROR_SUCCESS);
            const LONG_PTR previous = SetWindowLongPtrW(
                hwnd_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
            if (previous == 0 && GetLastError() != ERROR_SUCCESS) {
                owner_ = nullptr;
                Hide();
                return false;
            }
        }
        if (RootOwnerWindow(GetWindow(hwnd_, GW_OWNER)) != owner) {
            owner_ = nullptr;
            Hide();
            return false;
        }
        owner_ = owner;
        return true;
    }
    if (!RegisterLanguageBarWindowClass()) {
        return false;
    }

    hwnd_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW |
                                WS_EX_TOPMOST | WS_EX_NOREDIRECTIONBITMAP,
                            LanguageBarClassName().c_str(),
                            L"YuneWindowsLanguageBar",
                            WS_POPUP, 0, 0, 1, 1, owner, nullptr,
                            ModuleHandleFromAddress(), this);
    if (hwnd_ && RootOwnerWindow(GetWindow(hwnd_, GW_OWNER)) == owner) {
        owner_ = owner;
    } else if (hwnd_) {
        const HWND invalid_window = hwnd_;
        hwnd_ = nullptr;
        SetWindowLongPtrW(invalid_window, GWLP_USERDATA, 0);
        DestroyWindow(invalid_window);
        owner_ = nullptr;
        return false;
    }
    if (hwnd_ && ToolbarSupersededMessage() != 0) {
        CHANGEFILTERSTRUCT filter = {};
        filter.cbSize = sizeof(filter);
        (void)ChangeWindowMessageFilterEx(hwnd_, ToolbarSupersededMessage(),
                                          MSGFLT_ALLOW, &filter);
    }
    return hwnd_ != nullptr;
}

bool LanguageBarWindow::Update(const LanguageBarState& state, bool show) {
    state_ = state;
    state_.owner = RootOwnerWindow(state.owner);
    skin_ = LoadToolbarSkin(ModuleDirectoryFromAddress(), state_.skin_name);

    // Render the bar at a fixed, compact 1x size regardless of caret/display DPI.
    // The anchor DPI is only valid while composing and falls back to 96 when idle,
    // which made the bar oscillate size (idle 96 vs composing 144) -- the
    // enlarge/cut-off. A small floating indicator reads best at a consistent
    // compact size; DPI scale-up is intentionally skipped here.
    state_.dpi = 96;

    if (!show || !state_.owner) {
        Hide();
        return true;
    }
    if ((pointer_captured_ || finishing_pointer_interaction_) &&
        owner_ != state_.owner) {
        // Ownership changes mean focus moved. Finish the old drag before any
        // GWLP_HWNDPARENT mutation, then let this update bind/show the new owner.
        Hide();
    }
    if (!EnsureCreated(state_.owner)) {
        return false;
    }
    if (!ForegroundMatchesOwner()) {
        Hide();
        return true;
    }

    // During capture the persistent DComp visual moves with the HWND. Cache any
    // state/layout change and flush it once capture ends; presenting on every
    // move is the compositor churn that the validated spike deliberately avoids.
    if (pointer_captured_ || finishing_pointer_interaction_) {
        QueueRender(true, false);
        return true;
    }

    const SIZE desired = LanguageBarDesiredSize(state_.dpi, skin_);
    const RECT rect = ComputeToolbarWindowRect(
        state_.anchor, desired, state_.dpi, state_.toolbar_position);
    if (SetTimer(hwnd_, kLanguageBarForegroundTimer,
                 kLanguageBarForegroundIntervalMs, nullptr) == 0) {
        Hide();
        return false;
    }
    ClaimVisibleToolbar();
    if (!SetWindowPos(hwnd_, HWND_TOPMOST, rect.left, rect.top,
                      rect.right - rect.left, rect.bottom - rect.top,
                      SWP_NOACTIVATE | SWP_SHOWWINDOW)) {
        Hide();
        return false;
    }
    SupersedeOtherToolbarWindows(hwnd_);
    Render();
    return true;
}

void LanguageBarWindow::Hide() {
    if (hwnd_) {
        if (pointer_captured_) {
            FinishPointerInteraction(pointer_down_client_, false, true, false);
        }
        click_allowed_ = false;
        tracking_mouse_leave_ = false;
        has_hover_segment_ = false;
        (void)KillTimer(hwnd_, kLanguageBarForegroundTimer);
        ShowWindow(hwnd_, SW_HIDE);
        ReleaseVisibleToolbar();
        render_pending_ = false;
        layout_pending_ = false;
        surface_reset_pending_ = false;
    }
}

void LanguageBarWindow::HideForSupersededFocus() {
    Hide();
}

bool LanguageBarWindow::ForegroundMatchesOwner() const {
    if (!hwnd_ || !owner_ || !IsWindow(owner_)) {
        return false;
    }
    const HWND owner_root = RootOwnerWindow(GetWindow(hwnd_, GW_OWNER));
    if (!owner_root || owner_root != RootOwnerWindow(owner_)) {
        return false;
    }
    const HWND foreground_root = RootOwnerWindow(GetForegroundWindow());
    return owner_root && foreground_root && owner_root == foreground_root;
}

void LanguageBarWindow::ClaimVisibleToolbar() {
    HWND previous = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_visible_toolbar_mutex);
        if (g_visible_toolbar != hwnd_) {
            previous = g_visible_toolbar;
            g_visible_toolbar = hwnd_;
        }
    }
    if (previous && IsWindow(previous)) {
        (void)ShowWindowAsync(previous, SW_HIDE);
    }
}

void LanguageBarWindow::ReleaseVisibleToolbar() {
    std::lock_guard<std::mutex> lock(g_visible_toolbar_mutex);
    if (g_visible_toolbar == hwnd_) {
        g_visible_toolbar = nullptr;
    }
}

void LanguageBarWindow::QueueRender(bool layout_changed, bool reset_surface) {
    render_pending_ = true;
    layout_pending_ = layout_pending_ || layout_changed;
    surface_reset_pending_ = surface_reset_pending_ || reset_surface;
}

void LanguageBarWindow::FlushQueuedRender() {
    if (pointer_captured_ || !hwnd_ || !IsWindowVisible(hwnd_)) {
        return;
    }
    if (surface_reset_pending_) {
        surface_.DiscardDeviceResources();
    }
    if (layout_pending_) {
        RECT rect = {};
        if (GetWindowRect(hwnd_, &rect)) {
            const SIZE desired = LanguageBarDesiredSize(state_.dpi, skin_);
            SetWindowPos(hwnd_, nullptr, rect.left, rect.top,
                         desired.cx, desired.cy,
                         SWP_NOACTIVATE | SWP_NOZORDER);
        }
    }
    const bool should_render = render_pending_ || layout_pending_ ||
                               surface_reset_pending_;
    render_pending_ = false;
    layout_pending_ = false;
    surface_reset_pending_ = false;
    if (should_render) {
        Render();
    }
}

LRESULT CALLBACK LanguageBarWindow::WindowProc(HWND hwnd, UINT message,
                                               WPARAM wparam, LPARAM lparam) {
    LanguageBarWindow* window =
        reinterpret_cast<LanguageBarWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
        window = reinterpret_cast<LanguageBarWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
        if (window) {
            window->hwnd_ = hwnd;
            return TRUE;
        }
    }
    if (window) {
        if (!window->hwnd_) {
            window->hwnd_ = hwnd;
        }
        return window->HandleMessage(message, wparam, lparam);
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT LanguageBarWindow::HandleMessage(UINT message, WPARAM wparam,
                                         LPARAM lparam) {
    if (message == ToolbarSupersededMessage()) {
        const HWND claimant = reinterpret_cast<HWND>(wparam);
        if (claimant && claimant != hwnd_ &&
            IsLanguageBarWindow(claimant) &&
            WindowOwnerMatchesForeground(claimant)) {
            Hide();
        }
        return 0;
    }
    switch (message) {
        case WM_PAINT:
            ValidateRect(hwnd_, nullptr);
            if (pointer_captured_) {
                QueueRender();
            } else {
                Render();
            }
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_DPICHANGED:
            (void)wparam;
            state_.dpi = 96;
            if (pointer_captured_) {
                QueueRender(true, true);
                return 0;
            }
            surface_.DiscardDeviceResources();
            if (lparam) {
                const RECT* suggested = reinterpret_cast<const RECT*>(lparam);
                const SIZE desired = LanguageBarDesiredSize(state_.dpi, skin_);
                SetWindowPos(hwnd_, HWND_TOPMOST, suggested->left, suggested->top,
                             desired.cx, desired.cy,
                             SWP_NOACTIVATE);
            }
            Render();
            return 0;
        case WM_ACTIVATEAPP:
            if (wparam == FALSE) {
#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
                if (ignore_activate_app_for_testing_) {
                    ++activate_app_bypass_count_for_testing_;
                    return 0;
                }
#endif
                Hide();
            }
            return 0;
        case WM_TIMER:
            if (wparam == kLanguageBarForegroundTimer &&
                !ForegroundMatchesOwner()) {
                Hide();
            }
            return 0;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_NCHITTEST:
            return HTCLIENT;
        case WM_LBUTTONDOWN: {
            POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
            BeginPointerInteraction(point);
            return 0;
        }
        case WM_MOUSEMOVE: {
            POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
            if (pointer_captured_) {
                ContinuePointerInteraction(point);
            } else {
                TrackMouseLeave();
                const LanguageBarSegment segment = SegmentFromPoint(point);
                if (!has_hover_segment_ || hover_segment_ != segment) {
                    hover_segment_ = segment;
                    has_hover_segment_ = true;
                    Render();
                }
            }
            return 0;
        }
        case WM_LBUTTONUP:
            EndPointerInteraction({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
            return 0;
        case WM_MOUSELEAVE:
            tracking_mouse_leave_ = false;
            has_hover_segment_ = false;
            if (pointer_captured_) {
                QueueRender();
            } else {
                Render();
            }
            return 0;
        case WM_CAPTURECHANGED:
            if (pointer_captured_ && !finishing_pointer_interaction_) {
                FinishPointerInteraction(pointer_down_client_, false, true,
                                         IsWindowVisible(hwnd_) != FALSE);
            }
            return 0;
        case WM_CANCELMODE:
            if (pointer_captured_) {
                FinishPointerInteraction(pointer_down_client_, false, true,
                                         IsWindowVisible(hwnd_) != FALSE);
            }
            return 0;
        case WM_NCDESTROY: {
            const HWND destroyed = hwnd_;
            (void)KillTimer(destroyed, kLanguageBarForegroundTimer);
            ReleaseVisibleToolbar();
            surface_.DiscardDeviceResources();
            owner_ = nullptr;
            pointer_captured_ = false;
            dragging_ = false;
            drag_allowed_ = false;
            click_allowed_ = false;
            has_hover_segment_ = false;
            has_pressed_segment_ = false;
            tracking_mouse_leave_ = false;
            finishing_pointer_interaction_ = false;
            render_pending_ = false;
            layout_pending_ = false;
            surface_reset_pending_ = false;
            hwnd_ = nullptr;
            SetWindowLongPtrW(destroyed, GWLP_USERDATA, 0);
            return DefWindowProcW(destroyed, message, wparam, lparam);
        }
        default:
            return DefWindowProcW(hwnd_, message, wparam, lparam);
    }
}

LanguageBarSegment LanguageBarWindow::SegmentFromPoint(POINT point) const {
    RECT client = {};
    GetClientRect(hwnd_, &client);
    const int grip_width = Scale(24, state_.dpi);
    const int width = std::max(
        1, static_cast<int>(client.right - client.left) - grip_width);
    const int segment_width = std::max(1, width / kToolbarSegmentCount);
    const int point_x = std::max(0, static_cast<int>(point.x) - grip_width);
    const int index =
        std::max(0, std::min(kToolbarSegmentCount - 1, point_x / segment_width));
    switch (index) {
        case 0:
            return LanguageBarSegment::AsciiMode;
        case 1:
            return LanguageBarSegment::FullShape;
        case 2:
            return LanguageBarSegment::OutputStandard;
        case 3:
            return LanguageBarSegment::Schema;
        default:
            return LanguageBarSegment::Settings;
    }
}

void LanguageBarWindow::Render() {
    if (!hwnd_) {
        return;
    }
#ifdef YUNE_WINDOWS_LANGUAGE_BAR_SMOKE_HOOKS
    ++render_count_;
#endif
    if (!surface_.PresentLanguageBar(hwnd_, state_, skin_, hover_segment_,
                                     pressed_segment_, has_hover_segment_,
                                     has_pressed_segment_)) {
        surface_.DiscardDeviceResources();
    }
}

bool LanguageBarWindow::IsPointInDragZone(POINT point) const {
    return IsPointInGripZone(point) || IsPointInSettingsSegment(point);
}

bool LanguageBarWindow::IsPointInGripZone(POINT point) const {
    RECT client = {};
    GetClientRect(hwnd_, &client);
    const int grip_width = Scale(24, state_.dpi);
    return point.x >= client.left && point.x <= client.left + grip_width &&
           point.y >= client.top && point.y <= client.bottom;
}

bool LanguageBarWindow::IsPointInSettingsSegment(POINT point) const {
    RECT client = {};
    GetClientRect(hwnd_, &client);
    return point.x >= client.left && point.x <= client.right &&
           point.y >= client.top && point.y <= client.bottom &&
           SegmentFromPoint(point) == LanguageBarSegment::Settings;
}

void LanguageBarWindow::TrackMouseLeave() {
    if (tracking_mouse_leave_) {
        return;
    }
    TRACKMOUSEEVENT event = {};
    event.cbSize = sizeof(event);
    event.dwFlags = TME_LEAVE;
    event.hwndTrack = hwnd_;
    if (TrackMouseEvent(&event)) {
        tracking_mouse_leave_ = true;
    }
}

void LanguageBarWindow::BeginPointerInteraction(POINT client_point) {
    pointer_down_client_ = client_point;
    const bool in_grip = IsPointInGripZone(client_point);
    drag_allowed_ = in_grip || IsPointInSettingsSegment(client_point);
    click_allowed_ = !in_grip;
    dragging_ = false;
    SetCapture(hwnd_);
    pointer_captured_ = GetCapture() == hwnd_;
    if (!pointer_captured_) {
        click_allowed_ = false;
        drag_allowed_ = false;
        return;
    }
    drag_start_screen_ = client_point;
    ClientToScreen(hwnd_, &drag_start_screen_);
    GetWindowRect(hwnd_, &drag_start_rect_);
    pressed_segment_ = SegmentFromPoint(client_point);
    has_pressed_segment_ = click_allowed_;
    Render();
}

void LanguageBarWindow::ContinuePointerInteraction(POINT client_point) {
    if (!pointer_captured_) {
        return;
    }
    POINT current_screen = client_point;
    ClientToScreen(hwnd_, &current_screen);
    const int dx = current_screen.x - drag_start_screen_.x;
    const int dy = current_screen.y - drag_start_screen_.y;
    if (!dragging_) {
        const int threshold = Scale(kLanguageBarDragThreshold, state_.dpi);
        if (!drag_allowed_ ||
            (std::abs(dx) < threshold && std::abs(dy) < threshold)) {
            return;
        }
        dragging_ = true;
        has_pressed_segment_ = false;
        QueueRender();
    }

    RECT desired = drag_start_rect_;
    OffsetRect(&desired, dx, dy);
    const RECT clamped = ClampToolbarRectToVisibleMonitor(desired, state_.dpi);
    SetWindowPos(hwnd_, nullptr, clamped.left, clamped.top,
                 clamped.right - clamped.left, clamped.bottom - clamped.top,
                 SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOSIZE);
}

void LanguageBarWindow::EndPointerInteraction(POINT client_point) {
    FinishPointerInteraction(client_point, true, true, true);
}

void LanguageBarWindow::FinishPointerInteraction(POINT client_point,
                                                  bool allow_click,
                                                  bool persist_position,
                                                  bool flush_render) {
    if (finishing_pointer_interaction_) {
        return;
    }
    finishing_pointer_interaction_ = true;
    const bool was_dragging = dragging_;
    const bool click_allowed = click_allowed_;
    const LanguageBarSegment pressed_segment = pressed_segment_;
    RECT final_rect = {};
    const bool has_final_rect =
        was_dragging && persist_position && hwnd_ &&
        GetWindowRect(hwnd_, &final_rect);
    pointer_captured_ = false;
    dragging_ = false;
    has_pressed_segment_ = false;
    click_allowed_ = false;
    drag_allowed_ = false;
    if (GetCapture() == hwnd_) {
        ReleaseCapture();
    }

    if (has_final_rect && position_changed_handler_) {
        position_changed_handler_(final_rect.left, final_rect.top,
                                  position_changed_context_);
    }

    if (!was_dragging && allow_click) {
        POINT release_screen = client_point;
        ClientToScreen(hwnd_, &release_screen);
        const int dx = release_screen.x - drag_start_screen_.x;
        const int dy = release_screen.y - drag_start_screen_.y;
        RECT client = {};
        GetClientRect(hwnd_, &client);
        const bool release_inside =
            client_point.x >= client.left && client_point.x <= client.right &&
            client_point.y >= client.top && client_point.y <= client.bottom;
        const int threshold = Scale(kLanguageBarDragThreshold, state_.dpi);
        const bool stayed_within_click_threshold =
            std::abs(dx) < threshold && std::abs(dy) < threshold;
        const bool released_on_pressed_segment =
            release_inside && SegmentFromPoint(client_point) == pressed_segment;

        if (click_allowed && stayed_within_click_threshold &&
            released_on_pressed_segment && click_handler_) {
            click_handler_(pressed_segment, click_context_);
        }
    }
    const bool visible_after_callbacks =
        hwnd_ && IsWindowVisible(hwnd_) != FALSE;
    if (visible_after_callbacks) {
        QueueRender();
    } else {
        render_pending_ = false;
        layout_pending_ = false;
        surface_reset_pending_ = false;
    }
    finishing_pointer_interaction_ = false;
    if (flush_render && visible_after_callbacks) {
        FlushQueuedRender();
    }
}

}  // namespace yune_windows
