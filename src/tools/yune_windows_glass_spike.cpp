// yune_windows_glass_spike.cpp - throwaway M11 Slice C toolbar-glass prototype v2
// (instrumented). DirectComposition + Direct2D content over a DWM acrylic backdrop.
// Writes a diagnostic log to %TEMP%\yune-glass-spike.log so failures are visible.
// Left-drag to move; RIGHT-click to close. NOT a product binary.

#include <windows.h>
#include <windowsx.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d2d1_1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <dcomp.h>
#include <dwmapi.h>
#include <uxtheme.h>
#include <wrl/client.h>
#include <cstdio>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "dcomp.lib")
#pragma comment(lib, "dwmapi.lib")

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

using Microsoft::WRL::ComPtr;

namespace {

constexpr int kSegmentCount = 5;
const wchar_t* const kGlyphs[kSegmentCount] = {L"\x4e2d", L"\x5168", L"\x50b3",
                                               L"\x7cb5", L"\x2699"};
const bool kActive[kSegmentCount] = {true, true, false, false, false};

ComPtr<ID2D1DeviceContext> g_dc;
ComPtr<IDCompositionDevice> g_dcomp;
ComPtr<IDCompositionTarget> g_target;
ComPtr<IDCompositionVisual> g_visual;
ComPtr<IDCompositionSurface> g_surface;
ComPtr<IDWriteTextFormat> g_format;

int g_hover = -1;
bool g_dragging = false;
POINT g_drag_anchor = {};
RECT g_drag_start = {};
int g_width = 0;
int g_height = 0;

void LogPath(char* out, size_t n) {
    char dir[MAX_PATH];
    GetTempPathA(MAX_PATH, dir);
    sprintf_s(out, n, "%syune-glass-spike.log", dir);
}
void LogLine(const char* line) {
    char path[MAX_PATH];
    LogPath(path, sizeof(path));
    FILE* f = nullptr;
    fopen_s(&f, path, "a");
    if (f) {
        fputs(line, f);
        fputc('\n', f);
        fclose(f);
    }
}
void LogHr(const char* label, HRESULT hr) {
    char b[256];
    sprintf_s(b, sizeof(b), "%s: 0x%08lX", label, static_cast<unsigned long>(hr));
    LogLine(b);
}
void ClearLog() {
    char path[MAX_PATH];
    LogPath(path, sizeof(path));
    FILE* f = nullptr;
    fopen_s(&f, path, "w");
    if (f) fclose(f);
}

int Scale(int value, UINT dpi) { return MulDiv(value, static_cast<int>(dpi), 96); }

bool InitGraphics(HWND hwnd, UINT dpi) {
    ComPtr<ID3D11Device> d3d;
    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, &d3d,
        nullptr, nullptr);
    LogHr("D3D11 hardware", hr);
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
                               D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                               D3D11_SDK_VERSION, &d3d, nullptr, nullptr);
        LogHr("D3D11 warp", hr);
    }
    if (FAILED(hr)) return false;

    ComPtr<IDXGIDevice> dxgi;
    hr = d3d.As(&dxgi);
    LogHr("query IDXGIDevice", hr);
    if (FAILED(hr)) return false;

    ComPtr<ID2D1Factory1> factory;
    hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                           __uuidof(ID2D1Factory1),
                           reinterpret_cast<void**>(factory.GetAddressOf()));
    LogHr("D2D1CreateFactory", hr);
    if (FAILED(hr)) return false;
    ComPtr<ID2D1Device> d2d_device;
    hr = factory->CreateDevice(dxgi.Get(), &d2d_device);
    LogHr("D2D CreateDevice", hr);
    if (FAILED(hr)) return false;
    hr = d2d_device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &g_dc);
    LogHr("D2D CreateDeviceContext", hr);
    if (FAILED(hr)) return false;
    g_dc->SetDpi(96.0f, 96.0f);

    hr = DCompositionCreateDevice(dxgi.Get(), __uuidof(IDCompositionDevice),
                                  reinterpret_cast<void**>(
                                      g_dcomp.GetAddressOf()));
    LogHr("DCompositionCreateDevice", hr);
    if (FAILED(hr)) return false;
    hr = g_dcomp->CreateTargetForHwnd(hwnd, TRUE, &g_target);
    LogHr("CreateTargetForHwnd", hr);
    if (FAILED(hr)) return false;
    hr = g_dcomp->CreateVisual(&g_visual);
    LogHr("CreateVisual", hr);
    if (FAILED(hr)) return false;
    hr = g_dcomp->CreateSurface(static_cast<UINT>(g_width),
                                static_cast<UINT>(g_height),
                                DXGI_FORMAT_B8G8R8A8_UNORM,
                                DXGI_ALPHA_MODE_PREMULTIPLIED, &g_surface);
    LogHr("CreateSurface", hr);
    if (FAILED(hr)) return false;
    hr = g_visual->SetContent(g_surface.Get());
    LogHr("SetContent", hr);
    hr = g_target->SetRoot(g_visual.Get());
    LogHr("SetRoot", hr);

    ComPtr<IDWriteFactory> dwrite;
    hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                             reinterpret_cast<IUnknown**>(dwrite.GetAddressOf()));
    LogHr("DWriteCreateFactory", hr);
    if (FAILED(hr)) return false;
    hr = dwrite->CreateTextFormat(
        L"Microsoft JhengHei UI", nullptr, DWRITE_FONT_WEIGHT_SEMI_BOLD,
        DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        static_cast<float>(Scale(17, dpi)), L"", &g_format);
    LogHr("CreateTextFormat", hr);
    if (FAILED(hr)) return false;
    g_format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
    g_format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    LogLine("InitGraphics OK");
    return true;
}

void Render() {
    if (!g_surface || !g_dc) return;
    ComPtr<IDXGISurface> dxgi_surface;
    POINT offset = {};
    HRESULT hr = g_surface->BeginDraw(
        nullptr, __uuidof(IDXGISurface),
        reinterpret_cast<void**>(dxgi_surface.GetAddressOf()), &offset);
    LogHr("surface BeginDraw", hr);
    if (FAILED(hr)) return;
    char ob[64];
    sprintf_s(ob, sizeof(ob), "offset: %ld,%ld  size: %dx%d", offset.x, offset.y,
              g_width, g_height);
    LogLine(ob);

    D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                          D2D1_ALPHA_MODE_PREMULTIPLIED));
    ComPtr<ID2D1Bitmap1> bitmap;
    hr = g_dc->CreateBitmapFromDxgiSurface(dxgi_surface.Get(), &props, &bitmap);
    LogHr("CreateBitmapFromDxgiSurface", hr);
    if (FAILED(hr)) {
        g_surface->EndDraw();
        return;
    }
    g_dc->SetTarget(bitmap.Get());
    g_dc->BeginDraw();
    g_dc->SetTransform(D2D1::Matrix3x2F::Translation(
        static_cast<float>(offset.x), static_cast<float>(offset.y)));
    g_dc->Clear(D2D1::ColorF(0, 0, 0, 0));

    const float w = static_cast<float>(g_width);
    const float h = static_cast<float>(g_height);
    const float seg = w / kSegmentCount;

    if (g_hover >= 0 && g_hover < kSegmentCount) {
        D2D1_ROUNDED_RECT hover = {
            {g_hover * seg + 3.0f, 3.0f, (g_hover + 1) * seg - 3.0f, h - 3.0f},
            8.0f, 8.0f};
        ComPtr<ID2D1SolidColorBrush> brush;
        g_dc->CreateSolidColorBrush(D2D1::ColorF(1.0f, 1.0f, 1.0f, 0.35f), &brush);
        if (brush) g_dc->FillRoundedRectangle(hover, brush.Get());
    }

    ComPtr<ID2D1SolidColorBrush> divider;
    g_dc->CreateSolidColorBrush(D2D1::ColorF(0.42f, 0.46f, 0.52f, 0.45f), &divider);
    for (int i = 1; i < kSegmentCount && divider; ++i) {
        g_dc->DrawLine({i * seg, h * 0.28f}, {i * seg, h * 0.72f}, divider.Get(),
                       1.0f);
    }

    ComPtr<ID2D1SolidColorBrush> active_brush;
    ComPtr<ID2D1SolidColorBrush> normal_brush;
    g_dc->CreateSolidColorBrush(D2D1::ColorF(0.03f, 0.46f, 0.75f, 1.0f),
                                &active_brush);
    g_dc->CreateSolidColorBrush(D2D1::ColorF(0.09f, 0.10f, 0.13f, 1.0f),
                                &normal_brush);
    for (int i = 0; i < kSegmentCount; ++i) {
        D2D1_RECT_F rect = {i * seg, 0.0f, (i + 1) * seg, h};
        ID2D1SolidColorBrush* b =
            kActive[i] ? active_brush.Get() : normal_brush.Get();
        if (b) g_dc->DrawText(kGlyphs[i], 1, g_format.Get(), rect, b);
    }

    hr = g_dc->EndDraw();
    LogHr("D2D EndDraw", hr);
    g_dc->SetTarget(nullptr);
    hr = g_surface->EndDraw();
    LogHr("surface EndDraw", hr);
    hr = g_dcomp->Commit();
    LogHr("Commit", hr);
}

void ApplyAcrylic(HWND hwnd) {
    const MARGINS sheet = {-1, -1, -1, -1};
    LogHr("extend frame", DwmExtendFrameIntoClientArea(hwnd, &sheet));
    DWORD corner = 2;  // DWMWCP_ROUND
    LogHr("corner pref", DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                                               &corner, sizeof(corner)));
    DWORD backdrop = 3;  // DWMSBT_TRANSIENTWINDOW = Desktop Acrylic
    LogHr("systembackdrop", DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE,
                                                  &backdrop, sizeof(backdrop)));
}

int SegmentAt(int x) {
    if (g_width <= 0) return -1;
    const int seg = g_width / kSegmentCount;
    if (seg <= 0) return -1;
    const int i = x / seg;
    return (i < 0) ? 0 : (i >= kSegmentCount ? kSegmentCount - 1 : i);
}

LRESULT CALLBACK Proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_LBUTTONDOWN:
            g_dragging = true;
            g_drag_anchor = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            ClientToScreen(hwnd, &g_drag_anchor);
            GetWindowRect(hwnd, &g_drag_start);
            SetCapture(hwnd);
            return 0;
        case WM_MOUSEMOVE:
            if (g_dragging) {
                POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
                ClientToScreen(hwnd, &p);
                RECT r = g_drag_start;
                OffsetRect(&r, p.x - g_drag_anchor.x, p.y - g_drag_anchor.y);
                SetWindowPos(hwnd, nullptr, r.left, r.top, 0, 0,
                             SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            } else {
                const int seg = SegmentAt(GET_X_LPARAM(lp));
                if (seg != g_hover) {
                    g_hover = seg;
                    Render();
                }
                TRACKMOUSEEVENT tme = {sizeof(tme), TME_LEAVE, hwnd, 0};
                TrackMouseEvent(&tme);
            }
            return 0;
        case WM_LBUTTONUP:
            if (g_dragging) {
                g_dragging = false;
                ReleaseCapture();
            }
            return 0;
        case WM_MOUSELEAVE:
            g_hover = -1;
            Render();
            return 0;
        case WM_RBUTTONUP:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    ClearLog();
    LogLine("== glass spike start ==");
    WNDCLASSW wc = {};
    wc.lpfnWndProc = Proc;
    wc.hInstance = instance;
    wc.lpszClassName = L"YuneToolbarGlassPrototype";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassW(&wc);

    const UINT dpi = GetDpiForSystem();
    g_width = Scale(330, dpi);
    g_height = Scale(44, dpi);
    const int x = (GetSystemMetrics(SM_CXSCREEN) - g_width) / 2;
    const int y = GetSystemMetrics(SM_CYSCREEN) / 3;
    HWND hwnd = CreateWindowExW(
        WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TOOLWINDOW |
            WS_EX_NOREDIRECTIONBITMAP,
        wc.lpszClassName, L"Yune Toolbar Glass Prototype", WS_POPUP, x, y, g_width,
        g_height, nullptr, nullptr, instance, nullptr);
    if (!hwnd) {
        LogLine("CreateWindow failed");
        return 1;
    }

    ApplyAcrylic(hwnd);
    if (!InitGraphics(hwnd, dpi)) {
        LogLine("InitGraphics FAILED");
        MessageBoxW(nullptr, L"Graphics init failed - see log.", L"Glass spike",
                    MB_OK);
        return 2;
    }
    Render();
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}
