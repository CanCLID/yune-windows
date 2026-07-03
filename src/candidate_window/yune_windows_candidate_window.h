#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <array>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace yune_windows {

struct CandidateWindowCandidate {
    std::wstring text;
    std::wstring comment;
};

struct CandidateWindowState {
    std::vector<CandidateWindowCandidate> candidates;
    int page_size = 5;
    int page_index = 0;
    int highlighted_index = 0;
    RECT anchor = {0, 0, 0, 0};
    HWND owner = nullptr;
    UINT dpi = 96;
};

enum class LanguageBarSegment {
    AsciiMode,
    FullShape,
    OutputStandard,
    Schema,
    Settings,
};

struct ToolbarPosition {
    bool present = false;
    int x = 0;
    int y = 0;
};

struct ToolbarSkinColor {
    float r = 0.0f;
    float g = 0.0f;
    float b = 0.0f;
    float a = 1.0f;
};

struct ToolbarSkin {
    std::wstring name = L"default";
    std::wstring font_family = L"Segoe UI";
    float font_size = 14.0f;
    int height = 42;
    int min_width = 318;
    int padding_x = 12;
    int padding_y = 8;
    int segment_gap = 6;
    int corner_radius = 18;
    int shadow_radius = 8;
    ToolbarSkinColor background = {0.96f, 0.97f, 0.98f, 0.90f};
    ToolbarSkinColor text = {0.08f, 0.09f, 0.11f, 1.0f};
    ToolbarSkinColor accent = {0.0f, 0.45f, 0.82f, 1.0f};
    ToolbarSkinColor hover = {0.86f, 0.92f, 1.0f, 0.74f};
    ToolbarSkinColor pressed = {0.74f, 0.84f, 0.96f, 0.90f};
    ToolbarSkinColor separator = {0.33f, 0.38f, 0.45f, 0.28f};
    ToolbarSkinColor shadow = {0.0f, 0.0f, 0.0f, 0.24f};
    std::array<std::wstring, 5> segment_labels = {
        L"\x4e2d", L"\x534a", L"\x6e2f", L"\x7cb5", L"\x2699"};
};

struct LanguageBarState {
    bool ascii_mode = false;
    bool full_shape = false;
    std::wstring output_standard;
    std::wstring schema_id;
    RECT anchor = {0, 0, 0, 0};
    HWND owner = nullptr;
    UINT dpi = 96;
    ToolbarPosition toolbar_position;
    std::wstring skin_name = L"default";
};

using LanguageBarClickHandler = void (*)(LanguageBarSegment segment, void* context);
using LanguageBarPositionChangedHandler = void (*)(int x, int y, void* context);

std::wstring SanitizeCandidateComment(std::wstring_view raw_comment);
int ClampCandidateHighlight(int highlighted_index, int candidate_count);
int CandidatePageCount(int candidate_count, int page_size);
int ClampCandidatePageIndex(int page_index, int candidate_count, int page_size);
int CandidatePageStartIndex(int page_index, int page_size);
RECT ComputeCandidateWindowRect(const RECT& anchor, SIZE desired_size, UINT dpi);
ToolbarSkin LoadToolbarSkin(const std::filesystem::path& install_root,
                            std::wstring_view skin_name);
std::wstring ToolbarSegmentLabelForState(LanguageBarSegment segment,
                                         const LanguageBarState& state,
                                         const ToolbarSkin& skin);
RECT ClampToolbarRectToVisibleMonitor(const RECT& desired_rect, UINT dpi);
RECT ComputeToolbarWindowRect(const RECT& anchor, SIZE desired_size, UINT dpi,
                              const ToolbarPosition& saved_position);

class D2DSurface {
public:
    D2DSurface() = default;
    ~D2DSurface();

    D2DSurface(const D2DSurface&) = delete;
    D2DSurface& operator=(const D2DSurface&) = delete;

    bool PresentLanguageBar(HWND hwnd, const LanguageBarState& state,
                            const ToolbarSkin& skin,
                            LanguageBarSegment hover_segment,
                            LanguageBarSegment pressed_segment,
                            bool has_hover,
                            bool has_pressed);
    bool PaintLanguageBarPreview(HWND hwnd, HDC dc, const RECT& bounds,
                                 const LanguageBarState& state,
                                 const ToolbarSkin& skin);
    void DiscardDeviceResources();
    bool device_loss_recovery_available() const { return true; }

private:
    bool EnsureFactories();

    struct Impl;
    Impl* impl_ = nullptr;
};

class NativeCandidateWindow {
public:
    NativeCandidateWindow() = default;
    ~NativeCandidateWindow();

    NativeCandidateWindow(const NativeCandidateWindow&) = delete;
    NativeCandidateWindow& operator=(const NativeCandidateWindow&) = delete;

    bool EnsureCreated(HWND owner);
    bool Update(const CandidateWindowState& state, bool show);
    void Hide();

    static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam);

private:
    LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
    bool ForegroundMatchesOwner() const;
    void Paint();

    HWND hwnd_ = nullptr;
    HWND owner_ = nullptr;
    CandidateWindowState state_;
};

class LanguageBarWindow {
public:
    LanguageBarWindow() = default;
    ~LanguageBarWindow();

    LanguageBarWindow(const LanguageBarWindow&) = delete;
    LanguageBarWindow& operator=(const LanguageBarWindow&) = delete;

    void SetClickHandler(LanguageBarClickHandler handler, void* context);
    void SetPositionChangedHandler(LanguageBarPositionChangedHandler handler,
                                   void* context);
    bool EnsureCreated(HWND owner);
    bool Update(const LanguageBarState& state, bool show);
    void Hide();

    static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam);

private:
    LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
    bool ForegroundMatchesOwner() const;
    LanguageBarSegment SegmentFromPoint(POINT point) const;
    void Render();
    bool IsPointInDragZone(POINT point) const;
    bool IsPointInGripZone(POINT point) const;
    bool IsPointInSettingsSegment(POINT point) const;
    void TrackMouseLeave();
    void BeginPointerInteraction(POINT client_point);
    void ContinuePointerInteraction(POINT client_point);
    void EndPointerInteraction(POINT client_point);

    HWND hwnd_ = nullptr;
    HWND owner_ = nullptr;
    LanguageBarState state_;
    ToolbarSkin skin_;
    D2DSurface surface_;
    LanguageBarClickHandler click_handler_ = nullptr;
    void* click_context_ = nullptr;
    LanguageBarPositionChangedHandler position_changed_handler_ = nullptr;
    void* position_changed_context_ = nullptr;
    bool pointer_captured_ = false;
    bool dragging_ = false;
    bool drag_allowed_ = false;
    bool click_allowed_ = false;
    POINT drag_start_screen_ = {0, 0};
    RECT drag_start_rect_ = {0, 0, 0, 0};
    POINT pointer_down_client_ = {0, 0};
    LanguageBarSegment hover_segment_ = LanguageBarSegment::AsciiMode;
    LanguageBarSegment pressed_segment_ = LanguageBarSegment::AsciiMode;
    bool has_hover_segment_ = false;
    bool has_pressed_segment_ = false;
    bool tracking_mouse_leave_ = false;
};

}  // namespace yune_windows
