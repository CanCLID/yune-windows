#include "yune_windows_candidate_window.h"

#include <windowsx.h>

#include <algorithm>

namespace yune_windows {
namespace {

constexpr const wchar_t* kClassName = L"YuneWindowsCandidateWindow";
constexpr const wchar_t* kLanguageBarClassName = L"YuneWindowsLanguageBar";
constexpr COLORREF kBorderColor = RGB(87, 93, 101);
constexpr COLORREF kBackgroundColor = RGB(255, 255, 255);
constexpr COLORREF kHighlightColor = RGB(229, 241, 255);
constexpr COLORREF kTextColor = RGB(20, 24, 31);
constexpr COLORREF kCommentColor = RGB(88, 94, 104);

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
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

SIZE LanguageBarDesiredSize(UINT dpi) {
    return {Scale(360, dpi), Scale(34, dpi)};
}

RECT ComputeLanguageBarRect(const RECT& anchor, SIZE desired_size, UINT dpi) {
    RECT target = {
        anchor.left,
        anchor.top,
        anchor.left + desired_size.cx,
        anchor.top + desired_size.cy,
    };
    if (target.left == 0 && target.top == 0 && target.right == desired_size.cx &&
        target.bottom == desired_size.cy) {
        RECT work = {};
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
        target.right = work.right - Scale(12, dpi);
        target.left = target.right - desired_size.cx;
        target.top = work.top + Scale(12, dpi);
        target.bottom = target.top + desired_size.cy;
        return target;
    }

    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    if (monitor && GetMonitorInfoW(monitor, &info)) {
        const RECT work = info.rcWork;
        if (target.right > work.right) {
            const int width = target.right - target.left;
            target.left = work.right - width;
            target.right = work.right;
        }
        if (target.bottom > work.bottom) {
            const int height = target.bottom - target.top;
            target.top = work.bottom - height;
            target.bottom = work.bottom;
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

std::wstring OutputStandardLabel(std::wstring_view value) {
    if (value == L"opencc_traditional") {
        return L"OpenCC";
    }
    if (value == L"hong_kong_traditional") {
        return L"HK";
    }
    if (value == L"taiwan_traditional") {
        return L"TW";
    }
    if (value == L"mainland_simplified") {
        return L"Sim";
    }
    return L"Std";
}

std::wstring LanguageBarLabel(LanguageBarSegment segment,
                              const LanguageBarState& state) {
    switch (segment) {
        case LanguageBarSegment::AsciiMode:
            return state.ascii_mode ? L"EN" : L"CN";
        case LanguageBarSegment::FullShape:
            return state.full_shape ? L"Full" : L"Half";
        case LanguageBarSegment::OutputStandard:
            return OutputStandardLabel(state.output_standard);
        case LanguageBarSegment::Schema:
            return state.schema_id.empty() ? L"Schema" : state.schema_id;
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

    hwnd_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
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
    if (show && !ForegroundMatchesOwner()) {
        Hide();
        return true;
    }

    const SIZE desired = LanguageBarDesiredSize(state_.dpi);
    const RECT rect = ComputeLanguageBarRect(state_.anchor, desired, state_.dpi);
    SetWindowPos(hwnd_, HWND_TOPMOST, rect.left, rect.top, rect.right - rect.left,
                 rect.bottom - rect.top,
                 SWP_NOACTIVATE | (show ? SWP_SHOWWINDOW : SWP_NOZORDER));
    InvalidateRect(hwnd_, nullptr, TRUE);
    if (show) {
        UpdateWindow(hwnd_);
    }
    return true;
}

void LanguageBarWindow::Hide() {
    if (hwnd_) {
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
            Paint();
            return 0;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_NCHITTEST:
            return HTCLIENT;
        case WM_LBUTTONUP:
            if (click_handler_) {
                POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
                click_handler_(SegmentFromPoint(point), click_context_);
            }
            return 0;
        default:
            return DefWindowProcW(hwnd_, message, wparam, lparam);
    }
}

LanguageBarSegment LanguageBarWindow::SegmentFromPoint(POINT point) const {
    RECT client = {};
    GetClientRect(hwnd_, &client);
    const int width =
        std::max(1, static_cast<int>(client.right - client.left));
    const int segment_width = std::max(1, width / 4);
    const int point_x = static_cast<int>(point.x);
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

void LanguageBarWindow::Paint() {
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

    HFONT font = CreateFontW(-Scale(15, state_.dpi), 0, 0, 0, FW_NORMAL, FALSE,
                             FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HGDIOBJ old_font = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, kTextColor);

    const LanguageBarSegment segments[] = {
        LanguageBarSegment::AsciiMode,
        LanguageBarSegment::FullShape,
        LanguageBarSegment::OutputStandard,
        LanguageBarSegment::Schema,
    };
    const int segment_width =
        std::max(1, static_cast<int>(client.right - client.left) / 4);
    for (int i = 0; i < 4; ++i) {
        RECT segment_rect = {client.left + i * segment_width, client.top,
                             i == 3 ? client.right
                                    : client.left + (i + 1) * segment_width,
                             client.bottom};
        if (i > 0) {
            MoveToEx(dc, segment_rect.left, segment_rect.top + Scale(6, state_.dpi),
                     nullptr);
            LineTo(dc, segment_rect.left,
                   segment_rect.bottom - Scale(6, state_.dpi));
        }
        segment_rect.left += Scale(6, state_.dpi);
        segment_rect.right -= Scale(6, state_.dpi);
        const std::wstring label = LanguageBarLabel(segments[i], state_);
        DrawTextW(dc, label.c_str(), static_cast<int>(label.size()),
                  &segment_rect,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }

    SelectObject(dc, old_font);
    DeleteObject(font);
    EndPaint(hwnd_, &ps);
}

}  // namespace yune_windows
