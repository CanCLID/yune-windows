#include "yune_windows_candidate_window.h"

#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
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
constexpr int kToolbarSegmentCount = 4;

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

float ScaleFloat(float value, UINT dpi) {
    return value * static_cast<float>(dpi == 0 ? 96 : dpi) / 96.0f;
}

D2D1_COLOR_F ToD2DColor(const ToolbarSkinColor& color) {
    return D2D1::ColorF(color.r, color.g, color.b, color.a);
}

std::filesystem::path ModuleDirectoryFromAddress() {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&ModuleDirectoryFromAddress),
                            &module)) {
        return {};
    }
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
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpfnWndProc = NativeCandidateWindow::WindowProc;
    wc.lpszClassName = kClassName;
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
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpfnWndProc = LanguageBarWindow::WindowProc;
    wc.lpszClassName = kLanguageBarClassName;
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
    return {Scale(std::max(220, skin.min_width), dpi),
            Scale(std::max(32, skin.height + skin.shadow_radius), dpi)};
}

std::wstring OutputStandardLabel(std::wstring_view value) {
    if (value == L"opencc_traditional") {
        return L"\x7e41";
    }
    if (value == L"hong_kong_traditional") {
        return L"\x6e2f";
    }
    if (value == L"taiwan_traditional") {
        return L"\x81fa";
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
    if (value == L"luna_pinyin") {
        return L"\x62fc";
    }
    return value.empty() ? L"\x6cd5" : std::wstring(value.substr(0, 1));
}

std::wstring LanguageBarLabel(LanguageBarSegment segment,
                              const LanguageBarState& state) {
    switch (segment) {
        case LanguageBarSegment::AsciiMode:
            return state.ascii_mode ? L"EN" : L"\x4e2d";
        case LanguageBarSegment::FullShape:
            return state.full_shape ? L"\x5168" : L"\x534a";
        case LanguageBarSegment::OutputStandard:
            return OutputStandardLabel(state.output_standard);
        case LanguageBarSegment::Schema:
            return SchemaLabel(state.schema_id);
    }
    return L"";
}

}  // namespace

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

    const char* label_keys[kToolbarSegmentCount] = {"ascii", "shape", "standard",
                                                    "schema"};
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

struct D2DSurface::Impl {
    ComPtr<ID2D1Factory> d2d_factory;
    ComPtr<IDWriteFactory> dwrite_factory;
    ComPtr<IWICImagingFactory> wic_factory;
};

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
    if (!impl_->wic_factory) {
        if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&impl_->wic_factory)))) {
            return false;
        }
    }
    return true;
}

void D2DSurface::DiscardDeviceResources() {
    if (impl_) {
        impl_->d2d_factory.Reset();
        impl_->dwrite_factory.Reset();
        impl_->wic_factory.Reset();
    }
}

bool D2DSurface::PresentLanguageBar(HWND hwnd, const LanguageBarState& state,
                                    const ToolbarSkin& skin,
                                    LanguageBarSegment hover_segment,
                                    LanguageBarSegment pressed_segment,
                                    bool has_hover,
                                    bool has_pressed) {
    if (!hwnd || !EnsureFactories()) {
        return false;
    }

    RECT window_rect = {};
    if (!GetWindowRect(hwnd, &window_rect)) {
        return false;
    }
    const int width = std::max(
        1, static_cast<int>(window_rect.right - window_rect.left));
    const int height = std::max(
        1, static_cast<int>(window_rect.bottom - window_rect.top));

    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return false;
    }
    HDC memory_dc = CreateCompatibleDC(screen_dc);
    if (!memory_dc) {
        ReleaseDC(nullptr, screen_dc);
        return false;
    }

    BITMAPINFO bitmap_info = {};
    bitmap_info.bmiHeader.biSize = sizeof(bitmap_info.bmiHeader);
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = -height;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HBITMAP bitmap =
        CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bitmap || !bits) {
        if (bitmap) {
            DeleteObject(bitmap);
        }
        DeleteDC(memory_dc);
        ReleaseDC(nullptr, screen_dc);
        return false;
    }
    std::fill_n(static_cast<unsigned char*>(bits),
                static_cast<size_t>(width) * static_cast<size_t>(height) * 4,
                static_cast<unsigned char>(0));

    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
    ComPtr<ID2D1DCRenderTarget> target;
    D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                          D2D1_ALPHA_MODE_PREMULTIPLIED),
        static_cast<FLOAT>(state.dpi == 0 ? 96 : state.dpi),
        static_cast<FLOAT>(state.dpi == 0 ? 96 : state.dpi));
    HRESULT hr = impl_->d2d_factory->CreateDCRenderTarget(&properties, &target);
    RECT bind_rect = {0, 0, width, height};
    if (SUCCEEDED(hr)) {
        hr = target->BindDC(memory_dc, &bind_rect);
    }

    if (SUCCEEDED(hr)) {
        target->BeginDraw();
        target->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));

        ComPtr<ID2D1SolidColorBrush> brush;
        if (SUCCEEDED(target->CreateSolidColorBrush(ToD2DColor(skin.shadow),
                                                    &brush))) {
            const float shadow = ScaleFloat(static_cast<float>(skin.shadow_radius),
                                            state.dpi);
            const D2D1_ROUNDED_RECT shadow_rect = D2D1::RoundedRect(
                D2D1::RectF(shadow * 0.55f, shadow * 0.70f,
                            static_cast<float>(width) - shadow * 0.45f,
                            static_cast<float>(height) - shadow * 0.35f),
                ScaleFloat(static_cast<float>(skin.corner_radius), state.dpi),
                ScaleFloat(static_cast<float>(skin.corner_radius), state.dpi));
            target->FillRoundedRectangle(shadow_rect, brush.Get());
            brush.Reset();
        }

        const float shadow_offset =
            ScaleFloat(static_cast<float>(skin.shadow_radius), state.dpi);
        const float pill_left = shadow_offset * 0.35f;
        const float pill_top = shadow_offset * 0.15f;
        const float pill_right = static_cast<float>(width) - shadow_offset * 0.35f;
        const float pill_bottom =
            std::min(static_cast<float>(height) - shadow_offset * 0.45f,
                     pill_top + ScaleFloat(static_cast<float>(skin.height),
                                           state.dpi));
        const float radius =
            ScaleFloat(static_cast<float>(skin.corner_radius), state.dpi);
        const D2D1_ROUNDED_RECT pill =
            D2D1::RoundedRect(D2D1::RectF(pill_left, pill_top, pill_right,
                                          pill_bottom),
                              radius, radius);
        if (SUCCEEDED(target->CreateSolidColorBrush(ToD2DColor(skin.background),
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
            for (int i = 0; i < 3; ++i) {
                const float x = segment_left + segment_width * (i + 1);
                target->DrawLine(D2D1::Point2F(x, pill_top + ScaleFloat(9.0f, state.dpi)),
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

        const LanguageBarSegment segments[] = {
            LanguageBarSegment::AsciiMode,
            LanguageBarSegment::FullShape,
            LanguageBarSegment::OutputStandard,
            LanguageBarSegment::Schema,
        };
        ComPtr<IDWriteTextFormat> text_format;
        hr = impl_->dwrite_factory->CreateTextFormat(
            skin.font_family.c_str(), nullptr, DWRITE_FONT_WEIGHT_SEMI_BOLD,
            DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
            ScaleFloat(skin.font_size, state.dpi), L"", &text_format);
        if (SUCCEEDED(hr)) {
            text_format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
            text_format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
            for (int i = 0; i < kToolbarSegmentCount; ++i) {
                const float left = segment_left + segment_width * i;
                const D2D1_RECT_F segment_rect =
                    D2D1::RectF(left + ScaleFloat(3.0f, state.dpi),
                                pill_top + ScaleFloat(4.0f, state.dpi),
                                left + segment_width - ScaleFloat(3.0f, state.dpi),
                                pill_bottom - ScaleFloat(4.0f, state.dpi));
                const bool pressed =
                    has_pressed && pressed_segment == segments[i];
                const bool hover = has_hover && hover_segment == segments[i];
                if ((pressed || hover) &&
                    SUCCEEDED(target->CreateSolidColorBrush(
                        ToD2DColor(pressed ? skin.pressed : skin.hover),
                        &brush))) {
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
                    const std::wstring label = LanguageBarLabel(segments[i], state);
                    target->DrawTextW(label.c_str(),
                                      static_cast<UINT32>(label.size()),
                                      text_format.Get(), segment_rect, brush.Get(),
                                      D2D1_DRAW_TEXT_OPTIONS_CLIP);
                    brush.Reset();
                }
            }
        }

        hr = target->EndDraw();
    }

    bool presented = false;
    if (hr == D2DERR_RECREATE_TARGET) {
        DiscardDeviceResources();
    } else if (SUCCEEDED(hr)) {
        POINT destination = {window_rect.left, window_rect.top};
        POINT source = {0, 0};
        SIZE size = {width, height};
        BLENDFUNCTION blend = {};
        blend.BlendOp = AC_SRC_OVER;
        blend.SourceConstantAlpha = 255;
        blend.AlphaFormat = AC_SRC_ALPHA;
        presented =
            UpdateLayeredWindow(hwnd, screen_dc, &destination, &size, memory_dc,
                                &source, 0, &blend, ULW_ALPHA) == TRUE;
    }

    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return presented;
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
                            kClassName, L"YuneWindows Candidates", WS_POPUP, 0, 0,
                            1, 1, owner, nullptr, GetModuleHandleW(nullptr),
                            this);
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
        hwnd_ = nullptr;
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
    if (hwnd_) {
        if (owner_ != owner) {
            SetWindowLongPtrW(hwnd_, GWLP_HWNDPARENT,
                              reinterpret_cast<LONG_PTR>(owner));
            owner_ = owner;
        }
        return true;
    }
    if (!RegisterLanguageBarWindowClass()) {
        return false;
    }

    hwnd_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW |
                                WS_EX_TOPMOST | WS_EX_LAYERED,
                            kLanguageBarClassName, L"YuneWindowsLanguageBar",
                            WS_POPUP, 0, 0, 1, 1, owner, nullptr,
                            GetModuleHandleW(nullptr), this);
    owner_ = owner;
    return hwnd_ != nullptr;
}

bool LanguageBarWindow::Update(const LanguageBarState& state, bool show) {
    if (!EnsureCreated(state.owner)) {
        return false;
    }
    state_ = state;
    skin_ = LoadToolbarSkin(ModuleDirectoryFromAddress(), state_.skin_name);
    if (show && !ForegroundMatchesOwner()) {
        Hide();
        return true;
    }

    const SIZE desired = LanguageBarDesiredSize(state_.dpi, skin_);
    const RECT rect = ComputeToolbarWindowRect(
        state_.anchor, desired, state_.dpi, state_.toolbar_position);
    SetWindowPos(hwnd_, HWND_TOPMOST, rect.left, rect.top, rect.right - rect.left,
                 rect.bottom - rect.top,
                 SWP_NOACTIVATE | (show ? SWP_SHOWWINDOW : SWP_NOZORDER));
    Render();
    return true;
}

void LanguageBarWindow::Hide() {
    if (hwnd_) {
        if (pointer_captured_) {
            ReleaseCapture();
            pointer_captured_ = false;
        }
        ShowWindow(hwnd_, SW_HIDE);
    }
}

bool LanguageBarWindow::ForegroundMatchesOwner() const {
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
    switch (message) {
        case WM_PAINT:
            ValidateRect(hwnd_, nullptr);
            Render();
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_DPICHANGED:
            state_.dpi = HIWORD(wparam);
            if (lparam) {
                const RECT* suggested = reinterpret_cast<const RECT*>(lparam);
                SetWindowPos(hwnd_, HWND_TOPMOST, suggested->left, suggested->top,
                             suggested->right - suggested->left,
                             suggested->bottom - suggested->top,
                             SWP_NOACTIVATE);
            }
            Render();
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
            has_hover_segment_ = false;
            Render();
            return 0;
        case WM_CAPTURECHANGED:
            pointer_captured_ = false;
            dragging_ = false;
            has_pressed_segment_ = false;
            Render();
            return 0;
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
    const int segment_width = std::max(1, width / 4);
    const int point_x = std::max(0, static_cast<int>(point.x) - grip_width);
    const int index = std::max(0, std::min(3, point_x / segment_width));
    switch (index) {
        case 0:
            return LanguageBarSegment::AsciiMode;
        case 1:
            return LanguageBarSegment::FullShape;
        case 2:
            return LanguageBarSegment::OutputStandard;
        default:
            return LanguageBarSegment::Schema;
    }
}

void LanguageBarWindow::Render() {
    if (!hwnd_) {
        return;
    }
    if (!surface_.PresentLanguageBar(hwnd_, state_, skin_, hover_segment_,
                                     pressed_segment_, has_hover_segment_,
                                     has_pressed_segment_)) {
        surface_.DiscardDeviceResources();
    }
}

bool LanguageBarWindow::IsPointInDragZone(POINT point) const {
    RECT client = {};
    GetClientRect(hwnd_, &client);
    const int grip_width = Scale(24, state_.dpi);
    return point.x >= client.left && point.x <= client.left + grip_width &&
           point.y >= client.top && point.y <= client.bottom;
}

void LanguageBarWindow::BeginPointerInteraction(POINT client_point) {
    pointer_down_client_ = client_point;
    drag_allowed_ = IsPointInDragZone(client_point);
    dragging_ = false;
    SetCapture(hwnd_);
    pointer_captured_ = true;
    drag_start_screen_ = client_point;
    ClientToScreen(hwnd_, &drag_start_screen_);
    GetWindowRect(hwnd_, &drag_start_rect_);
    pressed_segment_ = SegmentFromPoint(client_point);
    has_pressed_segment_ = true;
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
    }

    RECT desired = drag_start_rect_;
    OffsetRect(&desired, dx, dy);
    const RECT clamped = ClampToolbarRectToVisibleMonitor(desired, state_.dpi);
    SetWindowPos(hwnd_, nullptr, clamped.left, clamped.top,
                 clamped.right - clamped.left, clamped.bottom - clamped.top,
                 SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOSIZE);
    Render();
}

void LanguageBarWindow::EndPointerInteraction(POINT client_point) {
    const bool was_dragging = dragging_;
    if (pointer_captured_) {
        ReleaseCapture();
    }
    pointer_captured_ = false;
    dragging_ = false;
    has_pressed_segment_ = false;

    if (was_dragging) {
        RECT rect = {};
        if (GetWindowRect(hwnd_, &rect) && position_changed_handler_) {
            position_changed_handler_(rect.left, rect.top,
                                      position_changed_context_);
        }
        Render();
        return;
    }

    if (!drag_allowed_ && click_handler_) {
        click_handler_(SegmentFromPoint(client_point), click_context_);
    }
    Render();
}

}  // namespace yune_windows
