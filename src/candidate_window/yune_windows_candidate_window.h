#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

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

std::wstring SanitizeCandidateComment(std::wstring_view raw_comment);
int ClampCandidateHighlight(int highlighted_index, int candidate_count);
int CandidatePageCount(int candidate_count, int page_size);
int ClampCandidatePageIndex(int page_index, int candidate_count, int page_size);
int CandidatePageStartIndex(int page_index, int page_size);
RECT ComputeCandidateWindowRect(const RECT& anchor, SIZE desired_size, UINT dpi);

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

}  // namespace yune_windows
