#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <msctf.h>
#include <strsafe.h>

#include <atomic>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <new>
#include <string>
#include <string_view>
#include <vector>

#include "../candidate_window/yune_windows_candidate_window.h"

namespace {

// {1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}
const CLSID kTextServiceClsid = {
    0x1788dba7,
    0xcc9a,
    0x49e2,
    {0x9c, 0x4c, 0xe9, 0xdb, 0xf0, 0xbe, 0x25, 0x67}};

// {3AE69B8D-19B4-4267-8F21-E239666D6632}
const GUID kProfileGuid = {
    0x3ae69b8d,
    0x19b4,
    0x4267,
    {0x8f, 0x21, 0xe2, 0x39, 0x66, 0x6d, 0x66, 0x32}};

constexpr LANGID kTextServiceLangId = 0x0c04;
constexpr const wchar_t* kTextServiceDesc = L"Yune Windows";
constexpr const wchar_t* kThreadingModel = L"Apartment";
constexpr const wchar_t* kPipeName = L"\\\\.\\pipe\\yune-windows-ime";
constexpr DWORD kServerQueryTimeoutMs = 5000;

HINSTANCE g_instance = nullptr;
std::atomic<long> g_dll_refs = 0;
std::atomic<unsigned long> g_structural_event_sequence = 0;
std::mutex g_structural_log_mutex;

void DllAddRef() {
    ++g_dll_refs;
}

void DllRelease() {
    --g_dll_refs;
}

bool IsHandledKey(WPARAM key) {
    return (key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z') ||
           key == VK_SPACE || key == VK_RETURN ||
           (key >= L'1' && key <= L'9') || key == VK_BACK ||
           key == VK_ESCAPE;
}

bool IsShortcutModifierDown() {
    return (GetKeyState(VK_CONTROL) & 0x8000) != 0 ||
           (GetKeyState(VK_MENU) & 0x8000) != 0 ||
           (GetKeyState(VK_LWIN) & 0x8000) != 0 ||
           (GetKeyState(VK_RWIN) & 0x8000) != 0;
}

wchar_t LowerAscii(WPARAM key) {
    if (key >= L'A' && key <= L'Z') {
        return static_cast<wchar_t>(key - L'A' + L'a');
    }
    return static_cast<wchar_t>(key);
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
                                         static_cast<int>(value.size()), nullptr, 0);
    if (size <= 0) {
        return {};
    }
    std::wstring output(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        output.data(), size);
    return output;
}

std::filesystem::path ModuleDirectory() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(g_instance, module_path, ARRAYSIZE(module_path))) {
        return {};
    }
    return std::filesystem::path(module_path).parent_path();
}

void WriteStructuralEvent(const char* event_name, int buffer_length = -1,
                          int candidate_count = -1) {
    try {
        const std::filesystem::path module_dir = ModuleDirectory();
        if (module_dir.empty()) {
            return;
        }
        const std::filesystem::path log_dir = module_dir / L"logs";
        std::filesystem::create_directories(log_dir);

        std::lock_guard<std::mutex> lock(g_structural_log_mutex);
        std::ofstream log(log_dir / L"tsf-events.log", std::ios::app);
        if (!log) {
            return;
        }
        log << "event=" << event_name
            << " sequence=" << ++g_structural_event_sequence;
        if (buffer_length >= 0) {
            log << " buffer_length=" << buffer_length;
        }
        if (candidate_count >= 0) {
            log << " candidate_count=" << candidate_count;
        }
        log << "\n";
    } catch (...) {
    }
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
            const char escaped = json[pos++];
            switch (escaped) {
                case 'n':
                    value.push_back('\n');
                    break;
                case 'r':
                    value.push_back('\r');
                    break;
                case 't':
                    value.push_back('\t');
                    break;
                case 'f':
                    value.push_back('\f');
                    break;
                case '\\':
                case '"':
                    value.push_back(escaped);
                    break;
                default:
                    break;
            }
        } else {
            value.push_back(ch);
        }
    }
    return value;
}

bool JsonBoolTrueValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":true";
    return json.find(needle) != std::string::npos;
}

bool JsonHasArrayValue(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\":[";
    return json.find(needle) != std::string::npos;
}

struct ServerResponse {
    bool ok = false;
    std::wstring commit_text;
    std::vector<yune_windows::CandidateWindowCandidate> candidates;
};

ServerResponse ServerQueryFailure(const std::wstring& input) {
    WriteStructuralEvent("server_query_failed", static_cast<int>(input.size()));
    return {};
}

std::vector<yune_windows::CandidateWindowCandidate> JsonCandidates(std::string_view json) {
    std::vector<yune_windows::CandidateWindowCandidate> candidates;
    const size_t array_start = json.find("\"candidates\":[");
    if (array_start == std::string::npos) {
        return candidates;
    }

    size_t pos = json.find('{', array_start);
    while (pos != std::string::npos) {
        const size_t end = json.find('}', pos);
        if (end == std::string::npos) {
            break;
        }
        const size_t array_end = json.find(']', array_start);
        if (array_end != std::string::npos && end > array_end) {
            break;
        }
        const std::string_view object = json.substr(pos, end - pos + 1);
        const std::string text = JsonStringValue(object, "text");
        if (!text.empty()) {
            candidates.push_back(
                yune_windows::CandidateWindowCandidate{Widen(text),
                                                   Widen(JsonStringValue(object,
                                                                         "comment"))});
        }
        pos = json.find('{', end + 1);
    }
    return candidates;
}

ServerResponse QueryServer(const std::wstring& input, bool commit) {
    auto wait_for_pipe_io = [](HANDLE pipe, OVERLAPPED& overlapped,
                               DWORD& transferred) -> bool {
        const DWORD wait = WaitForSingleObject(overlapped.hEvent,
                                               kServerQueryTimeoutMs);
        if (wait != WAIT_OBJECT_0) {
            CancelIo(pipe);
            WaitForSingleObject(overlapped.hEvent, 1000);
            return false;
        }
        return GetOverlappedResult(pipe, &overlapped, &transferred, FALSE) == TRUE;
    };

    auto write_pipe = [&](HANDLE pipe, const std::string& request,
                          DWORD& written) -> bool {
        HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!event) {
            return false;
        }
        OVERLAPPED overlapped = {};
        overlapped.hEvent = event;
        const DWORD request_size = static_cast<DWORD>(request.size());
        const BOOL started =
            WriteFile(pipe, request.data(), request_size, nullptr, &overlapped);
        bool ok = false;
        if (started) {
            ok = GetOverlappedResult(pipe, &overlapped, &written, FALSE) == TRUE;
        } else if (GetLastError() == ERROR_IO_PENDING) {
            ok = wait_for_pipe_io(pipe, overlapped, written);
        }
        CloseHandle(event);
        return ok && written == request_size;
    };

    auto read_pipe = [&](HANDLE pipe, char* response, DWORD response_size,
                         DWORD& read) -> bool {
        HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!event) {
            return false;
        }
        OVERLAPPED overlapped = {};
        overlapped.hEvent = event;
        const BOOL started =
            ReadFile(pipe, response, response_size, nullptr, &overlapped);
        bool ok = false;
        if (started) {
            ok = GetOverlappedResult(pipe, &overlapped, &read, FALSE) == TRUE;
        } else if (GetLastError() == ERROR_IO_PENDING) {
            ok = wait_for_pipe_io(pipe, overlapped, read);
        }
        CloseHandle(event);
        return ok && read > 0;
    };

    HANDLE pipe = CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                              OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
        return ServerQueryFailure(input);
    }

    DWORD mode = PIPE_READMODE_MESSAGE;
    if (!SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)) {
        CloseHandle(pipe);
        return ServerQueryFailure(input);
    }

    std::string request = "input=" + Narrow(input) + "\n";
    request += commit ? "commit=1\n.\n" : "commit=0\n.\n";
    DWORD written = 0;
    if (!write_pipe(pipe, request, written)) {
        CloseHandle(pipe);
        return ServerQueryFailure(input);
    }

    char response[65536] = {};
    DWORD read = 0;
    if (!read_pipe(pipe, response, sizeof(response) - 1, read)) {
        CloseHandle(pipe);
        return ServerQueryFailure(input);
    }
    CloseHandle(pipe);

    const std::string json(response, read);
    if (!JsonBoolTrueValue(json, "ready") ||
        JsonStringValue(json, "schema_id").empty() ||
        !JsonHasArrayValue(json, "candidates")) {
        return ServerQueryFailure(input);
    }

    ServerResponse result;
    result.ok = true;
    result.commit_text = Widen(JsonStringValue(json, "commit_text"));
    result.candidates = JsonCandidates(json);
    if (!commit && result.commit_text.empty() && !result.candidates.empty()) {
        result.commit_text = result.candidates.front().text;
    }
    return result;
}

class InsertTextEditSession final : public ITfEditSession {
public:
    InsertTextEditSession(ITfContext* context, std::wstring text)
        : ref_(1), context_(context), text_(std::move(text)) {
        if (context_) {
            context_->AddRef();
        }
        DllAddRef();
    }

    ~InsertTextEditSession() {
        if (context_) {
            context_->Release();
        }
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_ITfEditSession)) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        const HRESULT selection_hr = SetSelectionText(cookie, E_FAIL);
        if (SUCCEEDED(selection_hr)) {
            return selection_hr;
        }

        ITfInsertAtSelection* insert = nullptr;
        const HRESULT query_hr =
            context_ ? context_->QueryInterface(IID_ITfInsertAtSelection,
                                                reinterpret_cast<void**>(&insert))
                     : E_FAIL;
        HRESULT insert_hr = FAILED(query_hr) ? query_hr : E_NOINTERFACE;
        if (SUCCEEDED(query_hr) && insert) {
            insert_hr = insert->InsertTextAtSelection(
                cookie, TF_IAS_NOQUERY, text_.c_str(),
                static_cast<LONG>(text_.size()), nullptr);
            insert->Release();
            insert = nullptr;
            if (SUCCEEDED(insert_hr)) {
                return insert_hr;
            }
        }
        if (insert) {
            insert->Release();
        }
        return FAILED(insert_hr) ? insert_hr : selection_hr;
    }

private:
    HRESULT SetSelectionText(TfEditCookie cookie, HRESULT prior_hr) {
        if (!context_) {
            return FAILED(prior_hr) ? prior_hr : E_FAIL;
        }

        TF_SELECTION selection = {};
        ULONG fetched = 0;
        const HRESULT selection_hr =
            context_->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection,
                                   &fetched);
        if (FAILED(selection_hr) || fetched == 0 || !selection.range) {
            return FAILED(selection_hr) ? selection_hr
                                        : (FAILED(prior_hr) ? prior_hr
                                                            : E_NOINTERFACE);
        }

        const HRESULT set_hr =
            selection.range->SetText(cookie, 0, text_.c_str(),
                                     static_cast<LONG>(text_.size()));
        if (SUCCEEDED(set_hr)) {
            (void)selection.range->Collapse(cookie, TF_ANCHOR_END);
        }
        selection.range->Release();
        return set_hr;
    }

    std::atomic<long> ref_;
    ITfContext* context_;
    std::wstring text_;
};

class TextService final : public ITfTextInputProcessorEx, public ITfKeyEventSink {
public:
    TextService() : ref_(1) {
        DllAddRef();
    }

    ~TextService() {
        Deactivate();
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) ||
            IsEqualIID(iid, IID_ITfTextInputProcessor)) {
            *object = static_cast<ITfTextInputProcessor*>(this);
        } else if (IsEqualIID(iid, IID_ITfTextInputProcessorEx)) {
            *object = static_cast<ITfTextInputProcessorEx*>(this);
        } else if (IsEqualIID(iid, IID_ITfKeyEventSink)) {
            *object = static_cast<ITfKeyEventSink*>(this);
        }
        if (*object) {
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) override {
        return ActivateEx(thread_mgr, client_id, 0);
    }

    STDMETHODIMP ActivateEx(ITfThreadMgr* thread_mgr, TfClientId client_id,
                            DWORD) override {
        if (thread_mgr_) {
            Deactivate();
        }
        if (!thread_mgr) {
            return E_INVALIDARG;
        }

        ITfKeystrokeMgr* keystroke_mgr = nullptr;
        const HRESULT query_hr =
            thread_mgr->QueryInterface(IID_ITfKeystrokeMgr,
                                       reinterpret_cast<void**>(&keystroke_mgr));
        if (FAILED(query_hr) || !keystroke_mgr) {
            return FAILED(query_hr) ? query_hr : E_NOINTERFACE;
        }
        const HRESULT hr =
            keystroke_mgr->AdviseKeyEventSink(client_id, this, TRUE);
        keystroke_mgr->Release();
        if (FAILED(hr)) {
            return hr;
        }

        thread_mgr_ = thread_mgr;
        thread_mgr_->AddRef();
        client_id_ = client_id;
        WriteStructuralEvent("profile_activate");
        return S_OK;
    }

    STDMETHODIMP Deactivate() override {
        const bool was_active = thread_mgr_ != nullptr ||
                                client_id_ != TF_CLIENTID_NULL ||
                                !buffer_.empty() ||
                                !candidate_.empty() ||
                                !last_candidates_.empty();
        if (thread_mgr_) {
            ITfKeystrokeMgr* keystroke_mgr = nullptr;
            if (SUCCEEDED(thread_mgr_->QueryInterface(
                    IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke_mgr)))) {
                keystroke_mgr->UnadviseKeyEventSink(client_id_);
                keystroke_mgr->Release();
            }
            thread_mgr_->Release();
            thread_mgr_ = nullptr;
        }
        client_id_ = TF_CLIENTID_NULL;
        if (was_active) {
            WriteStructuralEvent("profile_deactivate",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
        }
        buffer_.clear();
        candidate_.clear();
        last_candidates_.clear();
        candidate_window_.Hide();
        return S_OK;
    }

    STDMETHODIMP OnSetFocus(BOOL focused) override {
        if (!focused) {
            WriteStructuralEvent("focus_lost", static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            buffer_.clear();
            candidate_.clear();
            last_candidates_.clear();
            candidate_window_.Hide();
        }
        return S_OK;
    }

    STDMETHODIMP OnTestKeyDown(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        *eaten = ShouldHandleKeyDown(key);
        return S_OK;
    }

    STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        *eaten = FALSE;
        if (!ShouldHandleKeyDown(key)) {
            return S_OK;
        }
        if ((key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z')) {
            buffer_.push_back(LowerAscii(key));
            ServerResponse response = QueryServer(buffer_, false);
            *eaten = TRUE;
            if (!response.ok) {
                candidate_.clear();
                last_candidates_.clear();
                candidate_window_.Hide();
                return S_OK;
            }
            last_candidates_ = response.candidates;
            candidate_ = last_candidates_.empty() ? std::wstring{}
                                                  : last_candidates_[0].text;
            const int buffer_length = static_cast<int>(buffer_.size());
            const int candidate_count = static_cast<int>(last_candidates_.size());
            WriteStructuralEvent("key_down", buffer_length, candidate_count);
            if (ShowCandidates(context, last_candidates_)) {
                WriteStructuralEvent("candidate_update", buffer_length,
                                     candidate_count);
            }
            return S_OK;
        }
        if (key == VK_BACK) {
            if (!buffer_.empty()) {
                buffer_.pop_back();
                if (buffer_.empty()) {
                    candidate_.clear();
                    last_candidates_.clear();
                    WriteStructuralEvent("key_backspace", 0, 0);
                    candidate_window_.Hide();
                    *eaten = TRUE;
                    return S_OK;
                }
                ServerResponse response = QueryServer(buffer_, false);
                if (!response.ok) {
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_window_.Hide();
                    *eaten = TRUE;
                    return S_OK;
                }
                last_candidates_ = response.candidates;
                candidate_ = last_candidates_.empty() ? std::wstring{}
                                                      : last_candidates_[0].text;
                const int buffer_length = static_cast<int>(buffer_.size());
                const int candidate_count =
                    static_cast<int>(last_candidates_.size());
                WriteStructuralEvent("key_backspace", buffer_length,
                                     candidate_count);
                if (ShowCandidates(context, last_candidates_)) {
                    WriteStructuralEvent("candidate_update", buffer_length,
                                         candidate_count);
                }
                *eaten = TRUE;
            } else {
                last_candidates_.clear();
                candidate_window_.Hide();
            }
            return S_OK;
        }
        if (key == VK_ESCAPE) {
            WriteStructuralEvent("composition_cancel",
                                 static_cast<int>(buffer_.size()),
                                 static_cast<int>(last_candidates_.size()));
            buffer_.clear();
            candidate_.clear();
            last_candidates_.clear();
            candidate_window_.Hide();
            *eaten = TRUE;
            return S_OK;
        }
        if (key >= L'1' && key <= L'9' && !buffer_.empty()) {
            *eaten = TRUE;
            const size_t index = static_cast<size_t>(key - L'1');
            if (index < last_candidates_.size()) {
                WriteStructuralEvent("commit_request",
                                     static_cast<int>(buffer_.size()),
                                     static_cast<int>(last_candidates_.size()));
                if (CommitText(context, last_candidates_[index].text)) {
                    buffer_.clear();
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_window_.Hide();
                }
            }
            return S_OK;
        }
        if ((key == VK_SPACE || key == VK_RETURN) && !buffer_.empty()) {
            *eaten = TRUE;
            ServerResponse response = QueryServer(buffer_, true);
            if (!response.ok) {
                *eaten = TRUE;
                return S_OK;
            }
            std::wstring commit = response.commit_text;
            if (commit.empty()) {
                commit = candidate_;
            }
            if (!commit.empty()) {
                WriteStructuralEvent("commit_request",
                                     static_cast<int>(buffer_.size()),
                                     static_cast<int>(last_candidates_.size()));
                if (CommitText(context, commit)) {
                    buffer_.clear();
                    candidate_.clear();
                    last_candidates_.clear();
                    candidate_window_.Hide();
                }
            }
        }
        return S_OK;
    }

    STDMETHODIMP OnTestKeyUp(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        (void)key;
        *eaten = FALSE;
        return S_OK;
    }

    STDMETHODIMP OnKeyUp(ITfContext*, WPARAM key, LPARAM, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        (void)key;
        *eaten = FALSE;
        return S_OK;
    }

    STDMETHODIMP OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) override {
        if (!eaten) {
            return E_INVALIDARG;
        }
        *eaten = FALSE;
        return S_OK;
    }

private:
    bool ShouldHandleKeyDown(WPARAM key) const {
        if (IsShortcutModifierDown()) {
            return false;
        }
        if ((key >= L'A' && key <= L'Z') || (key >= L'a' && key <= L'z')) {
            return true;
        }
        if (key == VK_SPACE || key == VK_RETURN ||
            (key >= L'1' && key <= L'9') || key == VK_BACK ||
            key == VK_ESCAPE) {
            return !buffer_.empty();
        }
        return false;
    }

    bool CommitText(ITfContext* context, const std::wstring& text) {
        if (!context || client_id_ == TF_CLIENTID_NULL) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        InsertTextEditSession* session = nullptr;
        try {
            session = new (std::nothrow) InsertTextEditSession(context, text);
        } catch (...) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        if (!session) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        HRESULT edit_hr = E_FAIL;
        const HRESULT request_hr =
            context->RequestEditSession(client_id_, session,
                                        TF_ES_SYNC | TF_ES_READWRITE, &edit_hr);
        session->Release();
        if (FAILED(request_hr) || FAILED(edit_hr)) {
            WriteStructuralEvent("commit_text_failed",
                                 static_cast<int>(text.size()));
            return false;
        }
        WriteStructuralEvent("commit_text",
                             static_cast<int>(text.size()));
        return true;
    }

    bool ShowCandidates(ITfContext* context,
                        const std::vector<yune_windows::CandidateWindowCandidate>& candidates) {
        if (candidates.empty()) {
            candidate_window_.Hide();
            return false;
        }

        try {
            RECT anchor = {80, 80, 96, 104};
            UINT dpi = 96;
            ITfContextView* view = nullptr;
            if (context && SUCCEEDED(context->GetActiveView(&view)) && view) {
                RECT screen_ext = {};
                if (SUCCEEDED(view->GetScreenExt(&screen_ext))) {
                    anchor = screen_ext;
                    anchor.right = anchor.left + 24;
                    anchor.bottom = anchor.top + 24;
                }
                HWND owner = nullptr;
                if (SUCCEEDED(view->GetWnd(&owner)) && owner) {
                    dpi = GetDpiForWindow(owner);
                }
                view->Release();
            }

            yune_windows::CandidateWindowState state;
            state.candidates = candidates;
            state.anchor = anchor;
            state.dpi = dpi;
            state.highlighted_index = 0;
            state.page_size = 5;
            if (!candidate_window_.Update(state, true)) {
                WriteStructuralEvent("candidate_window_failed",
                                     static_cast<int>(candidates.size()),
                                     static_cast<int>(candidates.size()));
                return false;
            }
        } catch (...) {
            WriteStructuralEvent("candidate_window_failed",
                                 static_cast<int>(candidates.size()),
                                 static_cast<int>(candidates.size()));
            return false;
        }
        return true;
    }

    std::atomic<long> ref_;
    ITfThreadMgr* thread_mgr_ = nullptr;
    TfClientId client_id_ = TF_CLIENTID_NULL;
    std::wstring buffer_;
    std::wstring candidate_;
    std::vector<yune_windows::CandidateWindowCandidate> last_candidates_;
    yune_windows::NativeCandidateWindow candidate_window_;
};

class ClassFactory final : public IClassFactory {
public:
    ClassFactory() : ref_(1) {
        DllAddRef();
    }

    ~ClassFactory() {
        DllRelease();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_IClassFactory)) {
            *object = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(++ref_);
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = static_cast<ULONG>(--ref_);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** object) override {
        if (!object) {
            return E_INVALIDARG;
        }
        *object = nullptr;
        if (outer) {
            return CLASS_E_NOAGGREGATION;
        }
        TextService* service = new (std::nothrow) TextService();
        if (!service) {
            return E_OUTOFMEMORY;
        }
        const HRESULT hr = service->QueryInterface(iid, object);
        service->Release();
        return hr;
    }

    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) {
            DllAddRef();
        } else {
            DllRelease();
        }
        return S_OK;
    }

private:
    std::atomic<long> ref_;
};

std::wstring GuidString(REFGUID guid) {
    wchar_t buffer[64] = {};
    StringFromGUID2(guid, buffer, ARRAYSIZE(buffer));
    return buffer;
}

HRESULT SetRegString(HKEY root, const std::wstring& path, const wchar_t* name,
                     const std::wstring& value) {
    HKEY key = nullptr;
    DWORD disposition = 0;
    LSTATUS status =
        RegCreateKeyExW(root, path.c_str(), 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_WRITE, nullptr, &key, &disposition);
    if (status != ERROR_SUCCESS) {
        return HRESULT_FROM_WIN32(status);
    }
    status = RegSetValueExW(key, name, 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(value.c_str()),
                            static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    return HRESULT_FROM_WIN32(status);
}

void DeleteRegTree(HKEY root, const std::wstring& path) {
    RegDeleteTreeW(root, path.c_str());
}

HRESULT RegisterComServer() {
    wchar_t module_path[MAX_PATH] = {};
    if (!GetModuleFileNameW(g_instance, module_path, ARRAYSIZE(module_path))) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    const std::wstring clsid_path = L"CLSID\\" + GuidString(kTextServiceClsid);
    HRESULT hr = SetRegString(HKEY_CLASSES_ROOT, clsid_path, nullptr, kTextServiceDesc);
    if (FAILED(hr)) {
        return hr;
    }
    hr = SetRegString(HKEY_CLASSES_ROOT, clsid_path + L"\\InprocServer32", nullptr,
                      module_path);
    if (FAILED(hr)) {
        return hr;
    }
    return SetRegString(HKEY_CLASSES_ROOT, clsid_path + L"\\InprocServer32",
                        L"ThreadingModel", kThreadingModel);
}

void UnregisterComServer() {
    DeleteRegTree(HKEY_CLASSES_ROOT, L"CLSID\\" + GuidString(kTextServiceClsid));
}

HRESULT RegisterProfiles() {
    ITfInputProcessorProfileMgr* profile_mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfileMgr,
                                  reinterpret_cast<void**>(&profile_mgr));
    if (FAILED(hr)) {
        return hr;
    }
    wchar_t module_path[MAX_PATH] = {};
    GetModuleFileNameW(g_instance, module_path, ARRAYSIZE(module_path));
    hr = profile_mgr->RegisterProfile(
        kTextServiceClsid, kTextServiceLangId, kProfileGuid, kTextServiceDesc,
        static_cast<ULONG>(wcslen(kTextServiceDesc)), module_path,
        static_cast<ULONG>(wcslen(module_path)), 0, 0, 0, TRUE, 0);
    profile_mgr->Release();
    return hr;
}

void UnregisterProfiles() {
    ITfInputProcessorProfileMgr* profile_mgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr,
                                   reinterpret_cast<void**>(&profile_mgr)))) {
        profile_mgr->UnregisterProfile(kTextServiceClsid, kTextServiceLangId,
                                       kProfileGuid, 0);
        profile_mgr->Release();
    }
}

HRESULT RegisterCategories() {
    ITfCategoryMgr* category_mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfCategoryMgr,
                                  reinterpret_cast<void**>(&category_mgr));
    if (FAILED(hr)) {
        return hr;
    }
    const GUID categories[] = {
        GUID_TFCAT_TIP_KEYBOARD,
        GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
        GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
        GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
    };
    for (const GUID& category : categories) {
        hr = category_mgr->RegisterCategory(kTextServiceClsid, category,
                                            kTextServiceClsid);
        if (FAILED(hr)) {
            break;
        }
    }
    category_mgr->Release();
    return hr;
}

void UnregisterCategories() {
    ITfCategoryMgr* category_mgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                   reinterpret_cast<void**>(&category_mgr)))) {
        const GUID categories[] = {
            GUID_TFCAT_TIP_KEYBOARD,
            GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
            GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
            GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
        };
        for (const GUID& category : categories) {
            category_mgr->UnregisterCategory(kTextServiceClsid, category,
                                             kTextServiceClsid);
        }
        category_mgr->Release();
    }
}

}  // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void*) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_instance = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

extern "C" HRESULT STDAPICALLTYPE DllGetClassObject(REFCLSID clsid, REFIID iid,
                                                     void** object) {
    if (!object) {
        return E_INVALIDARG;
    }
    *object = nullptr;
    if (!IsEqualCLSID(clsid, kTextServiceClsid)) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    ClassFactory* factory = new (std::nothrow) ClassFactory();
    if (!factory) {
        return E_OUTOFMEMORY;
    }
    const HRESULT hr = factory->QueryInterface(iid, object);
    factory->Release();
    return hr;
}

extern "C" HRESULT STDAPICALLTYPE DllCanUnloadNow() {
    return g_dll_refs.load() == 0 ? S_OK : S_FALSE;
}

extern "C" HRESULT STDAPICALLTYPE DllRegisterServer() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(hr);
    if (hr == RPC_E_CHANGED_MODE) {
        hr = S_OK;
    }
    if (SUCCEEDED(hr)) {
        hr = RegisterComServer();
    }
    if (SUCCEEDED(hr)) {
        hr = RegisterProfiles();
    }
    if (SUCCEEDED(hr)) {
        hr = RegisterCategories();
    }
    if (FAILED(hr)) {
        UnregisterCategories();
        UnregisterProfiles();
        UnregisterComServer();
    }
    if (should_uninit) {
        CoUninitialize();
    }
    return hr;
}

extern "C" HRESULT STDAPICALLTYPE DllUnregisterServer() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(hr);
    if (hr == RPC_E_CHANGED_MODE) {
        hr = S_OK;
    }
    UnregisterCategories();
    UnregisterProfiles();
    UnregisterComServer();
    if (should_uninit) {
        CoUninitialize();
    }
    return S_OK;
}
