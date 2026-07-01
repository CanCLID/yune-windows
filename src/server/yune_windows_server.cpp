#include <windows.h>

#include <filesystem>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "rime_yune_windows_profile_api.h"

namespace {

using GetProfileApiFn = RimeYuneWindowsProfileApi* (*)();

struct Args {
    std::wstring rime_dll;
    std::wstring shared_dir;
    std::wstring user_dir;
    std::wstring pipe_name;
    bool once = false;
};

struct Request {
    std::string input;
    bool commit = false;
};

struct Candidate {
    std::string text;
    std::string comment;
};

struct DeployDiagnostics {
    bool default_config = false;
    bool schema = false;
    bool workspace_update_schema = false;
    bool full_deploy = false;
    bool artifact_fallback = false;
};

std::wstring RequireValue(int argc, wchar_t** argv, int& index) {
    if (index + 1 >= argc) {
        throw std::runtime_error("missing argument value");
    }
    ++index;
    return argv[index];
}

std::string Narrow(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr,
                                         0, nullptr, nullptr);
    if (size <= 0) {
        throw std::runtime_error("failed to convert string to UTF-8");
    }
    std::string output(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        output.data(), size, nullptr, nullptr);
    return output;
}

std::wstring ServerInstanceMutexName(const std::wstring& pipe_name) {
    std::wstring suffix;
    suffix.reserve(pipe_name.size());
    for (wchar_t ch : pipe_name) {
        if ((ch >= L'0' && ch <= L'9') || (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'a' && ch <= L'z') || ch == L'_' || ch == L'-') {
            suffix.push_back(ch);
        } else {
            suffix.push_back(L'_');
        }
    }
    return L"Local\\YuneWindowsServerSingleInstance_" + suffix;
}

Args ParseArgs(int argc, wchar_t** argv) {
    Args args;
    for (int i = 1; i < argc; ++i) {
        const std::wstring key = argv[i];
        if (key == L"--rime-dll") {
            args.rime_dll = RequireValue(argc, argv, i);
        } else if (key == L"--shared-dir") {
            args.shared_dir = RequireValue(argc, argv, i);
        } else if (key == L"--user-dir") {
            args.user_dir = RequireValue(argc, argv, i);
        } else if (key == L"--pipe") {
            args.pipe_name = RequireValue(argc, argv, i);
        } else if (key == L"--once") {
            args.once = true;
        } else {
            throw std::runtime_error("unknown argument");
        }
    }
    if (args.rime_dll.empty() || args.shared_dir.empty() || args.user_dir.empty() ||
        args.pipe_name.empty()) {
        throw std::runtime_error(
            "required arguments: --rime-dll --shared-dir --user-dir --pipe");
    }
    return args;
}

void Require(bool condition, const char* message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

std::wstring WidenAscii(std::string_view value) {
    return std::wstring(value.begin(), value.end());
}

bool SelectedSchemaArtifactsExist(const std::wstring& user_dir,
                                  const std::string& schema) {
    const std::filesystem::path build_dir =
        std::filesystem::path(user_dir) / L"build";
    const std::wstring stem = WidenAscii(schema);
    return std::filesystem::is_regular_file(build_dir / (stem + L".schema.yaml")) &&
           std::filesystem::is_regular_file(build_dir / (stem + L".table.bin")) &&
           std::filesystem::is_regular_file(build_dir / (stem + L".prism.bin")) &&
           std::filesystem::is_regular_file(build_dir / (stem + L".reverse.bin"));
}

std::string CStringOrEmpty(const char* value) {
    return value == nullptr ? std::string{} : std::string(value);
}

std::string JsonEscape(std::string_view value) {
    std::ostringstream out;
    for (const unsigned char ch : value) {
        switch (ch) {
            case '"':
                out << "\\\"";
                break;
            case '\\':
                out << "\\\\";
                break;
            case '\f':
                out << "\\f";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\r':
                out << "\\r";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                if (ch < 0x20) {
                    out << "\\u00";
                    const char* hex = "0123456789abcdef";
                    out << hex[(ch >> 4) & 0x0f] << hex[ch & 0x0f];
                } else {
                    out << static_cast<char>(ch);
                }
        }
    }
    return out.str();
}

Request ParseRequest(const std::string& payload) {
    Request request;
    std::istringstream in(payload);
    std::string line;
    while (std::getline(in, line)) {
        if (line == ".") {
            break;
        }
        if (line.rfind("input=", 0) == 0) {
            request.input = line.substr(6);
        } else if (line == "commit=1") {
            request.commit = true;
        }
    }
    return request;
}

class YuneRuntime {
public:
    explicit YuneRuntime(const Args& args) {
        std::filesystem::create_directories(args.user_dir);
        std::filesystem::create_directories(std::filesystem::path(args.user_dir) / L"build");

        library_ = LoadLibraryW(args.rime_dll.c_str());
        Require(library_ != nullptr, "failed to load rime.dll");
        auto get_profile_api = reinterpret_cast<GetProfileApiFn>(
            GetProcAddress(library_, "rime_get_yune_windows_profile_api"));
        Require(get_profile_api != nullptr, "missing rime_get_yune_windows_profile_api");
        profile_api_ = get_profile_api();
        Require(profile_api_ != nullptr, "profile API accessor returned null");
        api_ = &profile_api_->upstream;

        shared_dir_ = Narrow(args.shared_dir);
        user_dir_ = Narrow(args.user_dir);
        prebuilt_dir_ =
            Narrow((std::filesystem::path(args.shared_dir) / L"build").wstring());
        staging_dir_ =
            Narrow((std::filesystem::path(args.user_dir) / L"build").wstring());

        RIME_STRUCT_INIT(RimeTraits, traits_);
        traits_.shared_data_dir = shared_dir_.c_str();
        traits_.user_data_dir = user_dir_.c_str();
        traits_.distribution_name = "Yune Windows";
        traits_.distribution_code_name = "yune-windows";
        traits_.distribution_version = "p2-win01";
        traits_.app_name = "rime.yune-windows.server";
        traits_.min_log_level = 2;
        traits_.log_dir = "";
        traits_.prebuilt_data_dir = prebuilt_dir_.c_str();
        traits_.staging_dir = staging_dir_.c_str();

        Require(api_->setup && api_->deployer_initialize &&
                    api_->initialize && api_->start_maintenance &&
                    api_->join_maintenance_thread && api_->deploy &&
                    api_->deploy_config_file && api_->deploy_schema &&
                    api_->run_task && api_->create_session &&
                    api_->select_schema && api_->set_option &&
                    api_->get_option && api_->process_key && api_->get_status &&
                    api_->free_status && api_->get_context &&
                    api_->free_context && api_->destroy_session &&
                    api_->finalize,
                "profile API table is missing required slots");
        api_->setup(&traits_);
        api_->deployer_initialize(&traits_);
        api_->initialize(&traits_);
        initialized_ = true;
        DeployDiagnostics deploy_diagnostics;
        (void)api_->start_maintenance(True);
        api_->join_maintenance_thread();
        Require(api_->deploy_config_file("default.yaml", "config_version") == True,
                "Yune default config deploy failed");
        deploy_diagnostics.default_config = true;
        Require(api_->deploy_schema("jyut6ping3.schema.yaml") == True,
                "Yune schema deploy failed");
        deploy_diagnostics.schema = true;
        if (api_->run_task("workspace_update:jyut6ping3") == True) {
            deploy_diagnostics.workspace_update_schema = true;
        } else {
            deploy_diagnostics.artifact_fallback =
                SelectedSchemaArtifactsExist(args.user_dir, "jyut6ping3");
            Require(deploy_diagnostics.artifact_fallback,
                    "Yune schema workspace update failed and selected schema artifacts are missing");
        }
        if (api_->deploy() == True) {
            deploy_diagnostics.full_deploy = true;
        } else {
            deploy_diagnostics.artifact_fallback =
                SelectedSchemaArtifactsExist(args.user_dir, "jyut6ping3");
            Require(deploy_diagnostics.artifact_fallback,
                    "Yune deploy failed and selected schema artifacts are missing");
        }
        (void)deploy_diagnostics;
    }

    ~YuneRuntime() {
        if (api_ && initialized_) {
            if (api_->cleanup_all_sessions) {
                api_->cleanup_all_sessions();
            }
            api_->finalize();
        }
        if (library_) {
            FreeLibrary(library_);
        }
    }

    std::string Process(const Request& request) {
        const RimeSessionId session = api_->create_session();
        Require(session != 0, "failed to create session");
        bool session_active = true;
        RimeStatus status = {};
        bool status_active = false;
        RimeContext context = {};
        bool context_active = false;
        try {
            Require(api_->select_schema(session, "jyut6ping3") == True,
                    "failed to select jyut6ping3");
            api_->set_option(session, "ascii_mode", False);
            Require(api_->get_option(session, "ascii_mode") == False,
                    "failed to disable Yune ascii_mode");
            api_->set_option(session, "disable_learning", True);
            for (const unsigned char ch : request.input) {
                Require(api_->process_key(session, static_cast<int>(ch), 0) == True,
                        "failed to process key");
            }

            RIME_STRUCT_INIT(RimeStatus, status);
            Require(api_->get_status(session, &status) == True,
                    "failed to get status");
            status_active = true;
            const std::string schema_id = CStringOrEmpty(status.schema_id);
            api_->free_status(&status);
            status_active = false;

            RIME_STRUCT_INIT(RimeContext, context);
            Require(api_->get_context(session, &context) == True,
                    "failed to get context");
            context_active = true;
            std::vector<Candidate> candidates;
            for (int i = 0; i < context.menu.num_candidates; ++i) {
                candidates.push_back(Candidate{
                    CStringOrEmpty(context.menu.candidates[i].text),
                    CStringOrEmpty(context.menu.candidates[i].comment),
                });
            }
            api_->free_context(&context);
            context_active = false;
            Require(api_->destroy_session(session) == True,
                    "failed to destroy session");
            session_active = false;

            const std::string commit_text =
                request.commit && !candidates.empty() ? candidates[0].text : "";
            std::ostringstream out;
            out << "{\"ready\":true,\"schema_id\":\"" << JsonEscape(schema_id)
                << "\",\"candidate_count\":" << candidates.size()
                << ",\"commit_text\":\"" << JsonEscape(commit_text)
                << "\",\"candidates\":[";
            for (size_t i = 0; i < candidates.size(); ++i) {
                out << "{\"text\":\"" << JsonEscape(candidates[i].text)
                    << "\",\"comment\":\"" << JsonEscape(candidates[i].comment)
                    << "\"}";
                if (i + 1 < candidates.size()) {
                    out << ",";
                }
            }
            out << "]}\n";
            return out.str();
        } catch (...) {
            if (context_active) {
                api_->free_context(&context);
            }
            if (status_active) {
                api_->free_status(&status);
            }
            if (session_active) {
                api_->destroy_session(session);
            }
            throw;
        }
    }

private:
    HMODULE library_ = nullptr;
    RimeYuneWindowsProfileApi* profile_api_ = nullptr;
    RimeApi* api_ = nullptr;
    RimeTraits traits_ = {};
    std::string shared_dir_;
    std::string user_dir_;
    std::string prebuilt_dir_;
    std::string staging_dir_;
    bool initialized_ = false;
};

void ServeOnce(const Args& args, YuneRuntime& runtime) {
    HANDLE pipe = CreateNamedPipeW(
        args.pipe_name.c_str(), PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT, 1, 64 * 1024,
        64 * 1024, 0, nullptr);
    Require(pipe != INVALID_HANDLE_VALUE, "failed to create named pipe");

    const BOOL connected =
        ConnectNamedPipe(pipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!connected) {
        CloseHandle(pipe);
        throw std::runtime_error("named pipe client did not connect");
    }

    try {
        char buffer[8192] = {};
        DWORD bytes_read = 0;
        Require(ReadFile(pipe, buffer, sizeof(buffer) - 1, &bytes_read, nullptr) == TRUE,
                "failed to read pipe request");
        const Request request = ParseRequest(std::string(buffer, bytes_read));
        const std::string response = runtime.Process(request);
        DWORD bytes_written = 0;
        Require(WriteFile(pipe, response.data(), static_cast<DWORD>(response.size()),
                          &bytes_written, nullptr) == TRUE,
                "failed to write pipe response");
        Require(bytes_written == response.size(), "incomplete pipe response write");
        Require(FlushFileBuffers(pipe) == TRUE, "failed to flush pipe response");
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        pipe = INVALID_HANDLE_VALUE;
    } catch (...) {
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        pipe = INVALID_HANDLE_VALUE;
        throw;
    }
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    HANDLE single_instance = nullptr;
    try {
        const Args args = ParseArgs(argc, argv);
        const std::wstring mutex_name = ServerInstanceMutexName(args.pipe_name);
        single_instance = CreateMutexW(nullptr, TRUE, mutex_name.c_str());
        if (!single_instance) {
            throw std::runtime_error("failed to create server single-instance mutex");
        }
        const DWORD mutex_error = GetLastError();
        if (mutex_error == ERROR_ALREADY_EXISTS) {
            CloseHandle(single_instance);
            single_instance = nullptr;
            return 0;
        }
        YuneRuntime runtime(args);
        do {
            ServeOnce(args, runtime);
        } while (!args.once);
        CloseHandle(single_instance);
        single_instance = nullptr;
        return 0;
    } catch (const std::exception& error) {
        if (single_instance) {
            CloseHandle(single_instance);
        }
        std::cerr << "YuneWindowsServer failed: " << error.what() << "\n";
        return 1;
    }
}
