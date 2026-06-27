#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <iostream>
#include <string>

#include "yune_windows_candidate_window.h"

namespace {

bool ContainsRawMarker(const std::wstring& value) {
    return value.find(L'\f') != std::wstring::npos ||
           value.find(L'\r') != std::wstring::npos ||
           value.find(L"\\f") != std::wstring::npos ||
           value.find(L"\\r") != std::wstring::npos;
}

int SelfTest() {
    const std::wstring rich = yune_windows::SanitizeCandidateComment(
        L"\f\r1,ngo5hai6go3,composition");
    const std::wstring literal = yune_windows::SanitizeCandidateComment(L"\\fngo5hai6");
    if (ContainsRawMarker(rich) || ContainsRawMarker(literal)) {
        std::cerr << "comment sanitizer leaked raw markers\n";
        return 1;
    }
    if (yune_windows::ClampCandidateHighlight(10, 3) != 2 ||
        yune_windows::ClampCandidateHighlight(-2, 3) != 0) {
        std::cerr << "highlight clamp failed\n";
        return 1;
    }

    RECT anchor = {32000, 32000, 32100, 32120};
    RECT rect = yune_windows::ComputeCandidateWindowRect(anchor, {420, 180}, 144);
    if (rect.right <= rect.left || rect.bottom <= rect.top) {
        std::cerr << "candidate rect is invalid\n";
        return 1;
    }
    RECT near_anchor = {10, 10, 20, 30};
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(monitor_info);
    HMONITOR monitor = MonitorFromRect(&near_anchor, MONITOR_DEFAULTTONEAREST);
    if (!monitor || !GetMonitorInfoW(monitor, &monitor_info)) {
        std::cerr << "failed to read monitor work area\n";
        return 1;
    }
    RECT oversized_rect =
        yune_windows::ComputeCandidateWindowRect(near_anchor, {99999, 99999}, 96);
    const RECT work = monitor_info.rcWork;
    if (oversized_rect.left < work.left || oversized_rect.top < work.top ||
        oversized_rect.right > work.right || oversized_rect.bottom > work.bottom) {
        std::cerr << "candidate rect escaped monitor work area\n";
        return 1;
    }

    yune_windows::NativeCandidateWindow window;
    yune_windows::CandidateWindowState state;
    state.anchor = {10, 10, 18, 28};
    state.dpi = 144;
    state.page_size = 5;
    state.highlighted_index = 1;
    state.candidates = {
        {L"candidate-one", L"\\fngo5hai6"},
        {L"candidate-two", L"\f\r1,go3,composition"},
    };
    if (!window.Update(state, false)) {
        std::cerr << "candidate window failed to create: " << GetLastError()
                  << "\n";
        return 1;
    }
    window.Hide();

    std::cout << "candidate window smoke passed\n";
    return 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && std::wstring(argv[1]) == L"--self-test") {
        return SelfTest();
    }
    std::cerr << "usage: YuneWindowsCandidateWindowSmoke.exe --self-test\n";
    return 2;
}
