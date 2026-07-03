#include <windows.h>

#include <sddl.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "rime_yune_windows_profile_api.h"

#pragma comment(lib, "advapi32.lib")

namespace {

using GetProfileApiFn = RimeYuneWindowsProfileApi* (*)();
constexpr int kMaxReturnedCandidates = 30;
constexpr ULONGLONG kComposeSessionIdleTtlMs = 10ull * 60 * 1000;
constexpr size_t kMaxComposeSessions = 64;

struct Args {
    std::wstring rime_dll;
    std::wstring shared_dir;
    std::wstring user_dir;
    std::wstring pipe_name;
    bool once = false;
};

struct Request {
    std::string op;
    std::string input;
    std::string name;
    std::string value;
    std::string schema;
    std::string session;
    std::string key;
    std::string mask;
    std::string index;
    std::string direction;
    std::string x;
    std::string y;
    std::vector<std::string> unknown_fields;
    bool commit = false;
};

struct YuneState {
    std::string schema_id = "jyut6ping3";
    bool ascii_mode = false;
    bool full_shape = false;
    std::string output_standard = "hong_kong_traditional";
    bool toolbar_position_set = false;
    int toolbar_position_x = 0;
    int toolbar_position_y = 0;
    std::string toolbar_skin = "default";
};

struct SchemaInfo {
    std::string schema_id;
    std::string name;
};

struct Candidate {
    std::string text;
    std::string comment;
};

struct CompositionSnapshot {
    std::string schema_id;
    std::string raw_input;
    std::string preedit;
    int length = 0;
    int cursor_pos = 0;
    int sel_start = 0;
    int sel_end = 0;
    std::vector<Candidate> candidates;
};

struct ComposeSession {
    RimeSessionId session_id = 0;
    ULONGLONG last_used_ms = 0;
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

std::string TrimAsciiWhitespace(std::string value) {
    while (!value.empty() && static_cast<unsigned char>(value.front()) <= 0x20) {
        value.erase(value.begin());
    }
    while (!value.empty() && static_cast<unsigned char>(value.back()) <= 0x20) {
        value.pop_back();
    }
    return value;
}

bool IsJyutpingComment(std::string_view value) {
    bool has_letter = false;
    bool has_tone = false;
    for (const unsigned char ch : value) {
        if (ch >= 'a' && ch <= 'z') {
            has_letter = true;
            continue;
        }
        if (ch >= 'A' && ch <= 'Z') {
            has_letter = true;
            continue;
        }
        if (ch >= '1' && ch <= '6') {
            has_tone = true;
            continue;
        }
        if (ch == '\'' || ch == '-' || ch == ' ') {
            continue;
        }
        return false;
    }
    return has_letter && has_tone;
}

std::vector<std::string> ParseCsvPrefixFields(std::string_view record,
                                              size_t max_fields) {
    std::vector<std::string> fields;
    std::string field;
    bool quoted = false;
    for (size_t i = 0; i < record.size(); ++i) {
        const char ch = record[i];
        if (quoted) {
            if (ch == '"') {
                if (i + 1 < record.size() && record[i + 1] == '"') {
                    field.push_back('"');
                    ++i;
                } else {
                    quoted = false;
                }
            } else {
                field.push_back(ch);
            }
            continue;
        }
        if (ch == '"') {
            quoted = true;
            continue;
        }
        if (ch == ',') {
            fields.push_back(TrimAsciiWhitespace(field));
            field.clear();
            if (fields.size() == max_fields) {
                return fields;
            }
            continue;
        }
        field.push_back(ch);
    }
    fields.push_back(TrimAsciiWhitespace(field));
    return fields;
}

std::string SimplifiedCsvJyutpingComment(std::string_view record) {
    const std::vector<std::string> fields = ParseCsvPrefixFields(record, 3);
    if (fields.size() < 3) {
        return {};
    }
    if (fields[0].empty()) {
        return {};
    }
    for (const unsigned char ch : fields[0]) {
        if (ch < '0' || ch > '9') {
            return {};
        }
    }
    if (!IsJyutpingComment(fields[2])) {
        return {};
    }
    return fields[2];
}

std::string CleanNonCsvComment(std::string_view raw_comment) {
    std::string output;
    output.reserve(raw_comment.size());
    for (const unsigned char ch : raw_comment) {
        if (ch < 0x20 || ch == 0x7f) {
            continue;
        }
        output.push_back(static_cast<char>(ch));
    }
    return TrimAsciiWhitespace(output);
}

std::string SimplifyCandidateComment(std::string_view raw_comment) {
    std::string record;
    for (const unsigned char ch : raw_comment) {
        if (ch == '\f' || ch == '\r' || ch == '\n') {
            const std::string simplified =
                SimplifiedCsvJyutpingComment(TrimAsciiWhitespace(record));
            if (!simplified.empty()) {
                return simplified;
            }
            record.clear();
            continue;
        }
        record.push_back(static_cast<char>(ch));
    }

    const std::string simplified =
        SimplifiedCsvJyutpingComment(TrimAsciiWhitespace(record));
    if (!simplified.empty()) {
        return simplified;
    }
    return CleanNonCsvComment(raw_comment);
}

Candidate CandidateFromRimeCandidate(const RimeCandidate& candidate) {
    return Candidate{
        CStringOrEmpty(candidate.text),
        SimplifyCandidateComment(CStringOrEmpty(candidate.comment)),
    };
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

Bool ToRimeBool(bool value) {
    return value ? True : False;
}

bool IsKnownOutputStandard(std::string_view value) {
    return value == "opencc_traditional" ||
           value == "hong_kong_traditional" ||
           value == "taiwan_traditional" ||
           value == "mainland_simplified";
}

bool ParseProtocolBool(std::string_view value) {
    if (value == "1" || value == "true" || value == "True") {
        return true;
    }
    if (value == "0" || value == "false" || value == "False") {
        return false;
    }
    throw std::runtime_error("expected boolean protocol value");
}

int ParseProtocolInt(std::string_view value, const char* field_name) {
    Require(!value.empty(), field_name);
    size_t parsed = 0;
    int base = 10;
    if (value.size() > 2 && value[0] == '0' &&
        (value[1] == 'x' || value[1] == 'X')) {
        base = 16;
    }
    const long parsed_value = std::stol(std::string(value), &parsed, base);
    Require(parsed == value.size(), field_name);
    return static_cast<int>(parsed_value);
}

int ParseNonNegativeProtocolInt(std::string_view value, const char* field_name) {
    const int parsed = ParseProtocolInt(value, field_name);
    Require(parsed >= 0, field_name);
    return parsed;
}

int ParseProtocolKeyCode(std::string_view value) {
    Require(!value.empty(), "missing key");
    if (value.size() == 1) {
        return static_cast<unsigned char>(value[0]);
    }
    return ParseProtocolInt(value, "invalid key");
}

bool ParsePageBackward(std::string_view value) {
    if (value == "prev" || value == "previous" || value == "back" ||
        value == "backward" || value == "up") {
        return true;
    }
    if (value == "next" || value == "forward" || value == "down") {
        return false;
    }
    throw std::runtime_error("invalid page direction");
}

std::filesystem::path StateFilePathForArgs(const Args& args) {
    const std::filesystem::path shared_parent =
        std::filesystem::path(args.shared_dir).parent_path();
    const std::filesystem::path user_parent =
        std::filesystem::path(args.user_dir).parent_path();
    std::filesystem::path install_root;
    if (!shared_parent.empty() && shared_parent == user_parent) {
        install_root = shared_parent;
    } else if (!user_parent.empty()) {
        install_root = user_parent;
    } else {
        install_root = std::filesystem::current_path();
    }
    // Persisted under state\ime-state.json; the shared server is the sole writer.
    return install_root / L"state" / L"ime-state.json";
}

bool ExtractJsonString(const std::string& json, std::string_view key,
                       std::string* value) {
    const std::string needle = "\"" + std::string(key) + "\"";
    const size_t key_pos = json.find(needle);
    if (key_pos == std::string::npos) {
        return false;
    }
    const size_t colon_pos = json.find(':', key_pos + needle.size());
    if (colon_pos == std::string::npos) {
        return false;
    }
    const size_t quote_pos = json.find('"', colon_pos + 1);
    if (quote_pos == std::string::npos) {
        return false;
    }
    std::string output;
    for (size_t i = quote_pos + 1; i < json.size(); ++i) {
        const char ch = json[i];
        if (ch == '"') {
            *value = output;
            return true;
        }
        if (ch == '\\' && i + 1 < json.size()) {
            ++i;
            output.push_back(json[i]);
            continue;
        }
        output.push_back(ch);
    }
    return false;
}

bool ExtractJsonBool(const std::string& json, std::string_view key, bool* value) {
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
    if (json.compare(value_pos, 4, "true") == 0) {
        *value = true;
        return true;
    }
    if (json.compare(value_pos, 5, "false") == 0) {
        *value = false;
        return true;
    }
    return false;
}

bool ExtractJsonInt(const std::string& json, std::string_view key, int* value) {
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
    if (end_pos < json.size() &&
        (json[end_pos] == '-' || json[end_pos] == '+')) {
        ++end_pos;
    }
    while (end_pos < json.size() && json[end_pos] >= '0' &&
           json[end_pos] <= '9') {
        ++end_pos;
    }
    if (end_pos == value_pos) {
        return false;
    }
    try {
        size_t parsed = 0;
        const int parsed_value =
            std::stoi(std::string(json.substr(value_pos, end_pos - value_pos)),
                      &parsed, 10);
        if (parsed != end_pos - value_pos) {
            return false;
        }
        *value = parsed_value;
        return true;
    } catch (...) {
        return false;
    }
}

bool IsSafeSkinName(std::string_view value) {
    if (value.empty() || value.size() > 64) {
        return false;
    }
    for (const unsigned char ch : value) {
        if ((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') ||
            (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '-') {
            continue;
        }
        return false;
    }
    return true;
}

Request ParseRequest(const std::string& payload) {
    Request request;
    std::istringstream in(payload);
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line == ".") {
            break;
        }
        if (line.rfind("op=", 0) == 0) {
            request.op = line.substr(3);
        } else if (line.rfind("input=", 0) == 0) {
            request.input = line.substr(6);
        } else if (line.rfind("name=", 0) == 0) {
            request.name = line.substr(5);
        } else if (line.rfind("value=", 0) == 0) {
            request.value = line.substr(6);
        } else if (line.rfind("schema=", 0) == 0) {
            request.schema = line.substr(7);
        } else if (line.rfind("session=", 0) == 0) {
            request.session = line.substr(8);
        } else if (line.rfind("key=", 0) == 0) {
            request.key = line.substr(4);
        } else if (line.rfind("mask=", 0) == 0) {
            request.mask = line.substr(5);
        } else if (line.rfind("index=", 0) == 0) {
            request.index = line.substr(6);
        } else if (line.rfind("direction=", 0) == 0) {
            request.direction = line.substr(10);
        } else if (line.rfind("x=", 0) == 0) {
            request.x = line.substr(2);
        } else if (line.rfind("y=", 0) == 0) {
            request.y = line.substr(2);
        } else if (line == "commit=1") {
            request.commit = true;
        } else if (line == "commit=0") {
            request.commit = false;
        } else if (!line.empty()) {
            request.unknown_fields.push_back(line);
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
        state_file_ = StateFilePathForArgs(args);

        RIME_STRUCT_INIT(RimeTraits, traits_);
        traits_.shared_data_dir = shared_dir_.c_str();
        traits_.user_data_dir = user_dir_.c_str();
        traits_.distribution_name = "Yune Windows";
        traits_.distribution_code_name = "yune-windows";
        traits_.distribution_version = "0.1.0-dev";
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
                    api_->free_status && api_->get_commit &&
                    api_->free_commit && api_->commit_composition &&
                    api_->clear_composition && api_->get_context &&
                    api_->get_schema_list && api_->free_schema_list &&
                    api_->get_current_schema &&
                    api_->free_context && api_->candidate_list_begin &&
                    api_->candidate_list_next && api_->candidate_list_end &&
                    api_->get_input && api_->select_candidate_on_current_page &&
                    api_->candidate_list_from_index && api_->change_page &&
                    api_->destroy_session &&
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
        LoadState();
        WarmDictionary();
    }

    // Rime lazy-loads the schema dictionary on the first lookup (~200ms+), which
    // made the first real keystroke after a server (re)start slow enough to trip
    // the client's short key-path timeout -- the "takes a few seconds to start
    // typing Chinese after toggling" symptom. Do a throwaway lookup now so the
    // dictionary is resident before the user types. Best-effort; never fails
    // startup.
    void WarmDictionary() {
        try {
            const RimeSessionId session = api_->create_session();
            if (session == 0) {
                return;
            }
            ApplyState(session);
            for (const char ch : std::string("ngo")) {
                if (api_->process_key(
                        session, static_cast<int>(static_cast<unsigned char>(ch)),
                        0) != True) {
                    break;
                }
            }
            RimeContext context = {};
            RIME_STRUCT_INIT(RimeContext, context);
            if (api_->get_context(session, &context) == True) {
                api_->free_context(&context);
            }
            (void)api_->destroy_session(session);
        } catch (...) {
        }
    }

    ~YuneRuntime() {
        if (api_ && initialized_) {
            DestroyAllComposeSessions();
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
        try {
            if (!request.unknown_fields.empty()) {
                throw std::runtime_error("unsupported request field");
            }
            if (!request.op.empty()) {
                return ProcessOperation(request);
            }
            return ProcessInput(request);
        } catch (const std::exception& error) {
            return ErrorResponseJson(error.what());
        }
    }

private:
    void LoadState() {
        state_ = YuneState{};
        if (!std::filesystem::is_regular_file(state_file_)) {
            return;
        }

        std::ifstream in(state_file_, std::ios::binary);
        if (!in) {
            return;
        }
        std::ostringstream buffer;
        buffer << in.rdbuf();
        const std::string json = buffer.str();

        std::string text_value;
        bool bool_value = false;
        if (ExtractJsonString(json, "schema_id", &text_value) && !text_value.empty()) {
            state_.schema_id = text_value;
        }
        if (ExtractJsonBool(json, "ascii_mode", &bool_value)) {
            state_.ascii_mode = bool_value;
        }
        if (ExtractJsonBool(json, "full_shape", &bool_value)) {
            state_.full_shape = bool_value;
        }
        if (ExtractJsonString(json, "output_standard", &text_value) &&
            IsKnownOutputStandard(text_value)) {
            state_.output_standard = text_value;
        }
        if (ExtractJsonBool(json, "position_set", &bool_value)) {
            state_.toolbar_position_set = bool_value;
        }
        int int_value = 0;
        if (ExtractJsonInt(json, "x", &int_value)) {
            state_.toolbar_position_x = int_value;
        }
        if (ExtractJsonInt(json, "y", &int_value)) {
            state_.toolbar_position_y = int_value;
        }
        if (ExtractJsonString(json, "skin", &text_value) &&
            IsSafeSkinName(text_value)) {
            state_.toolbar_skin = text_value;
        }
    }

    void PersistState() const {
        std::filesystem::create_directories(state_file_.parent_path());
        std::ofstream out(state_file_, std::ios::binary | std::ios::trunc);
        Require(static_cast<bool>(out), "failed to open IME state file");
        out << "{\n"
            << "  \"schema_id\": \"" << JsonEscape(state_.schema_id) << "\",\n"
            << "  \"ascii_mode\": " << (state_.ascii_mode ? "true" : "false")
            << ",\n"
            << "  \"full_shape\": " << (state_.full_shape ? "true" : "false")
            << ",\n"
            << "  \"output_standard\": \"" << JsonEscape(state_.output_standard)
            << "\",\n"
            << "  \"toolbar\": {\n"
            << "    \"position_set\": "
            << (state_.toolbar_position_set ? "true" : "false") << ",\n"
            << "    \"x\": " << state_.toolbar_position_x << ",\n"
            << "    \"y\": " << state_.toolbar_position_y << ",\n"
            << "    \"skin\": \"" << JsonEscape(state_.toolbar_skin) << "\"\n"
            << "  }\n"
            << "}\n";
        Require(static_cast<bool>(out), "failed to write IME state file");
    }

    std::string StateJson() const {
        std::ostringstream out;
        out << "{\"schema_id\":\"" << JsonEscape(state_.schema_id)
            << "\",\"ascii_mode\":" << (state_.ascii_mode ? "true" : "false")
            << ",\"full_shape\":" << (state_.full_shape ? "true" : "false")
            << ",\"output_standard\":\"" << JsonEscape(state_.output_standard)
            << "\",\"toolbar\":{\"position_set\":"
            << (state_.toolbar_position_set ? "true" : "false")
            << ",\"x\":" << state_.toolbar_position_x
            << ",\"y\":" << state_.toolbar_position_y
            << ",\"skin\":\"" << JsonEscape(state_.toolbar_skin) << "\"}}";
        return out.str();
    }

    std::string StateResponseJson() const {
        std::ostringstream out;
        out << "{\"ready\":true,\"state\":" << StateJson() << "}\n";
        return out.str();
    }

    std::string ErrorResponseJson(std::string_view error) const {
        std::ostringstream out;
        out << "{\"ready\":false,\"error\":\"" << JsonEscape(error)
            << "\",\"state\":" << StateJson() << "}\n";
        return out.str();
    }

    std::vector<SchemaInfo> ListSchemas() {
        RimeSchemaList schema_list = {};
        bool schema_list_active = false;
        try {
            Require(api_->get_schema_list(&schema_list) == True,
                    "failed to get schema list");
            schema_list_active = true;
            std::vector<SchemaInfo> schemas;
            for (size_t i = 0; i < schema_list.size; ++i) {
                schemas.push_back(SchemaInfo{
                    CStringOrEmpty(schema_list.list[i].schema_id),
                    CStringOrEmpty(schema_list.list[i].name),
                });
            }
            api_->free_schema_list(&schema_list);
            schema_list_active = false;
            return schemas;
        } catch (...) {
            if (schema_list_active) {
                api_->free_schema_list(&schema_list);
            }
            throw;
        }
    }

    bool SchemaExists(std::string_view schema_id) {
        const std::vector<SchemaInfo> schemas = ListSchemas();
        for (const SchemaInfo& schema : schemas) {
            if (schema.schema_id == schema_id) {
                return true;
            }
        }
        return false;
    }

    std::string ListSchemasResponseJson() {
        const std::vector<SchemaInfo> schemas = ListSchemas();
        std::ostringstream out;
        out << "{\"ready\":true,\"state\":" << StateJson() << ",\"schemas\":[";
        for (size_t i = 0; i < schemas.size(); ++i) {
            out << "{\"schema_id\":\"" << JsonEscape(schemas[i].schema_id)
                << "\",\"name\":\"" << JsonEscape(schemas[i].name) << "\"}";
            if (i + 1 < schemas.size()) {
                out << ",";
            }
        }
        out << "]}\n";
        return out.str();
    }

    void ApplyOutputStandard(RimeSessionId session) const {
        const bool use_luna_group = state_.schema_id == "luna_pinyin";
        const char* hk_option = use_luna_group ? "zh_hant_hk" : "variants_hk";
        const char* tw_option = use_luna_group ? "zh_hant_tw" : "trad_tw";
        const char* simplified_option =
            use_luna_group ? "zh_hans" : "simplification";

        api_->set_option(session, hk_option,
                         ToRimeBool(state_.output_standard ==
                                    "hong_kong_traditional"));
        api_->set_option(session, tw_option,
                         ToRimeBool(state_.output_standard ==
                                    "taiwan_traditional"));
        api_->set_option(session, simplified_option,
                         ToRimeBool(state_.output_standard ==
                                    "mainland_simplified"));
    }

    void ApplyState(RimeSessionId session) const {
        Require(api_->select_schema(session, state_.schema_id.c_str()) == True,
                "failed to select configured schema");
        api_->set_option(session, "ascii_mode", ToRimeBool(state_.ascii_mode));
        Require(api_->get_option(session, "ascii_mode") ==
                    ToRimeBool(state_.ascii_mode),
                "failed to apply Yune ascii_mode");
        api_->set_option(session, "full_shape", ToRimeBool(state_.full_shape));
        api_->set_option(session, "soft_cursor", True);
        api_->set_option(session, "traditionalization", False);
        ApplyOutputStandard(session);
        api_->set_option(session, "disable_learning", True);
    }

    void ApplyStateToComposeSessions() {
        for (const auto& entry : compose_sessions_) {
            ApplyState(entry.second.session_id);
        }
    }

    void DestroyAllComposeSessions() {
        for (const auto& entry : compose_sessions_) {
            if (entry.second.session_id != 0) {
                api_->destroy_session(entry.second.session_id);
            }
        }
        compose_sessions_.clear();
    }

    void GarbageCollectComposeSessions() {
        const ULONGLONG now = GetTickCount64();
        for (auto it = compose_sessions_.begin(); it != compose_sessions_.end();) {
            if (now - it->second.last_used_ms >= kComposeSessionIdleTtlMs) {
                api_->destroy_session(it->second.session_id);
                it = compose_sessions_.erase(it);
            } else {
                ++it;
            }
        }
    }

    void EnforceComposeSessionCap() {
        while (compose_sessions_.size() >= kMaxComposeSessions) {
            auto oldest = compose_sessions_.begin();
            for (auto it = compose_sessions_.begin(); it != compose_sessions_.end(); ++it) {
                if (it->second.last_used_ms < oldest->second.last_used_ms) {
                    oldest = it;
                }
            }
            api_->destroy_session(oldest->second.session_id);
            compose_sessions_.erase(oldest);
        }
    }

    RimeSessionId RequireComposeSession(std::string_view token) {
        Require(!token.empty(), "missing compose session");
        GarbageCollectComposeSessions();
        const auto it = compose_sessions_.find(std::string(token));
        Require(it != compose_sessions_.end(), "unknown compose session");
        it->second.last_used_ms = GetTickCount64();
        return it->second.session_id;
    }

    std::string NewComposeToken() {
        std::ostringstream token;
        token << "session-" << next_compose_session_token_++;
        return token.str();
    }

    std::vector<std::string> DrainCommits(RimeSessionId session) {
        std::vector<std::string> commits;
        while (true) {
            RimeCommit commit = {};
            RIME_STRUCT_INIT(RimeCommit, commit);
            if (api_->get_commit(session, &commit) != True) {
                break;
            }
            commits.push_back(CStringOrEmpty(commit.text));
            api_->free_commit(&commit);
        }
        return commits;
    }

    std::string JoinedCommits(const std::vector<std::string>& commits) const {
        std::string joined;
        for (const std::string& commit : commits) {
            joined += commit;
        }
        return joined;
    }

    std::vector<Candidate> CaptureCandidates(RimeSessionId session) {
        std::vector<Candidate> candidates;
        RimeCandidateListIterator iterator = {};
        bool iterator_active = false;
        try {
            if (api_->candidate_list_from_index(session, &iterator, 0) == True) {
                iterator_active = true;
                while (static_cast<int>(candidates.size()) < kMaxReturnedCandidates &&
                       api_->candidate_list_next(&iterator) == True) {
                    candidates.push_back(
                        CandidateFromRimeCandidate(iterator.candidate));
                }
                api_->candidate_list_end(&iterator);
                iterator_active = false;
            }
            return candidates;
        } catch (...) {
            if (iterator_active) {
                api_->candidate_list_end(&iterator);
            }
            throw;
        }
    }

    CompositionSnapshot CaptureCompositionSnapshot(RimeSessionId session) {
        CompositionSnapshot snapshot;
        snapshot.schema_id = state_.schema_id;
        snapshot.raw_input = CStringOrEmpty(api_->get_input(session));

        RimeStatus status = {};
        bool status_active = false;
        RimeContext context = {};
        bool context_active = false;
        try {
            RIME_STRUCT_INIT(RimeStatus, status);
            if (api_->get_status(session, &status) == True) {
                status_active = true;
                snapshot.schema_id = CStringOrEmpty(status.schema_id);
                api_->free_status(&status);
                status_active = false;
            }

            RIME_STRUCT_INIT(RimeContext, context);
            if (api_->get_context(session, &context) == True) {
                context_active = true;
                snapshot.length = context.composition.length;
                snapshot.cursor_pos = context.composition.cursor_pos;
                snapshot.sel_start = context.composition.sel_start;
                snapshot.sel_end = context.composition.sel_end;
                snapshot.preedit = CStringOrEmpty(context.composition.preedit);
                snapshot.candidates = CaptureCandidates(session);
                if (snapshot.candidates.empty() && context.menu.candidates != nullptr) {
                    for (int i = 0; i < context.menu.num_candidates &&
                                    static_cast<int>(snapshot.candidates.size()) <
                                        kMaxReturnedCandidates;
                         ++i) {
                        snapshot.candidates.push_back(CandidateFromRimeCandidate(
                            context.menu.candidates[i]));
                    }
                }
                api_->free_context(&context);
                context_active = false;
            }
            return snapshot;
        } catch (...) {
            if (context_active) {
                api_->free_context(&context);
            }
            if (status_active) {
                api_->free_status(&status);
            }
            throw;
        }
    }

    void WriteCandidatesJson(std::ostringstream& out,
                             const std::vector<Candidate>& candidates) const {
        for (size_t i = 0; i < candidates.size(); ++i) {
            out << "{\"text\":\"" << JsonEscape(candidates[i].text)
                << "\",\"comment\":\"" << JsonEscape(candidates[i].comment)
                << "\"}";
            if (i + 1 < candidates.size()) {
                out << ",";
            }
        }
    }

    void WriteCommitsJson(std::ostringstream& out,
                          const std::vector<std::string>& commits) const {
        for (size_t i = 0; i < commits.size(); ++i) {
            out << "\"" << JsonEscape(commits[i]) << "\"";
            if (i + 1 < commits.size()) {
                out << ",";
            }
        }
    }

    std::string ComposeResponseJson(std::string_view token,
                                    RimeSessionId session,
                                    const std::vector<std::string>& commits,
                                    int handled = -1) {
        const CompositionSnapshot snapshot = CaptureCompositionSnapshot(session);
        const std::string commit_text = JoinedCommits(commits);
        std::ostringstream out;
        out << "{\"ready\":true,\"session\":\"" << JsonEscape(token)
            << "\",\"schema_id\":\"" << JsonEscape(snapshot.schema_id)
            << "\",\"state\":" << StateJson()
            << ",\"raw_input\":\"" << JsonEscape(snapshot.raw_input)
            << "\",\"composition\":{\"length\":" << snapshot.length
            << ",\"cursor_pos\":" << snapshot.cursor_pos
            << ",\"sel_start\":" << snapshot.sel_start
            << ",\"sel_end\":" << snapshot.sel_end
            << ",\"preedit\":\"" << JsonEscape(snapshot.preedit) << "\"}"
            << ",\"candidate_count\":" << snapshot.candidates.size()
            << ",\"commit_text\":\"" << JsonEscape(commit_text)
            << "\",\"commits\":[";
        WriteCommitsJson(out, commits);
        out << "],\"candidates\":[";
        WriteCandidatesJson(out, snapshot.candidates);
        out << "]";
        if (handled >= 0) {
            out << ",\"handled\":" << (handled ? "true" : "false");
        }
        out << "}\n";
        return out.str();
    }

    std::string ComposeEndedResponseJson(std::string_view token) const {
        std::ostringstream out;
        out << "{\"ready\":true,\"session\":\"" << JsonEscape(token)
            << "\",\"ended\":true,\"state\":" << StateJson() << "}\n";
        return out.str();
    }

    std::string BeginComposeSession() {
        GarbageCollectComposeSessions();
        EnforceComposeSessionCap();
        const RimeSessionId session = api_->create_session();
        Require(session != 0, "failed to create compose session");
        bool session_owned = true;
        try {
            ApplyState(session);
            const std::string token = NewComposeToken();
            compose_sessions_[token] =
                ComposeSession{session, GetTickCount64()};
            session_owned = false;
            return ComposeResponseJson(token, session, {});
        } catch (...) {
            if (session_owned) {
                api_->destroy_session(session);
            }
            throw;
        }
    }

    std::string ProcessComposeOperation(const Request& request) {
        if (request.op == "compose-begin") {
            return BeginComposeSession();
        }
        if (request.op == "compose-end") {
            Require(!request.session.empty(), "missing compose session");
            GarbageCollectComposeSessions();
            const auto it = compose_sessions_.find(request.session);
            Require(it != compose_sessions_.end(), "unknown compose session");
            api_->destroy_session(it->second.session_id);
            compose_sessions_.erase(it);
            return ComposeEndedResponseJson(request.session);
        }

        const RimeSessionId session = RequireComposeSession(request.session);
        if (request.op == "compose-key") {
            const int keycode = ParseProtocolKeyCode(request.key);
            const int mask =
                request.mask.empty() ? 0 : ParseProtocolInt(request.mask, "invalid mask");
            const Bool handled = api_->process_key(session, keycode, mask);
            std::vector<std::string> commits = DrainCommits(session);
            return ComposeResponseJson(request.session, session, commits,
                                       handled == True ? 1 : 0);
        }
        if (request.op == "compose-select") {
            const int index =
                ParseNonNegativeProtocolInt(request.index, "invalid candidate index");
            Require(api_->select_candidate_on_current_page(
                        session, static_cast<size_t>(index)) == True,
                    "failed to select candidate");
            std::vector<std::string> commits = DrainCommits(session);
            return ComposeResponseJson(request.session, session, commits);
        }
        if (request.op == "compose-back") {
            constexpr int kBackspaceKey = 0xff08;
            const Bool handled = api_->process_key(session, kBackspaceKey, 0);
            std::vector<std::string> commits = DrainCommits(session);
            return ComposeResponseJson(request.session, session, commits,
                                       handled == True ? 1 : 0);
        }
        if (request.op == "compose-page") {
            const bool backward = ParsePageBackward(request.direction);
            const Bool handled = api_->change_page(session, ToRimeBool(backward));
            std::vector<std::string> commits = DrainCommits(session);
            return ComposeResponseJson(request.session, session, commits,
                                       handled == True ? 1 : 0);
        }
        if (request.op == "compose-commit") {
            Require(api_->commit_composition(session) == True,
                    "failed to commit composition");
            std::vector<std::string> commits = DrainCommits(session);
            return ComposeResponseJson(request.session, session, commits);
        }
        if (request.op == "compose-commit-raw") {
            const std::string raw_input = CStringOrEmpty(api_->get_input(session));
            api_->clear_composition(session);
            std::vector<std::string> commits;
            if (!raw_input.empty()) {
                commits.push_back(raw_input);
            }
            return ComposeResponseJson(request.session, session, commits);
        }
        if (request.op == "compose-cancel") {
            api_->clear_composition(session);
            return ComposeResponseJson(request.session, session, {});
        }
        throw std::runtime_error("unknown op verb");
    }

    std::string ProcessOperation(const Request& request) {
        if (request.op.rfind("compose-", 0) == 0) {
            return ProcessComposeOperation(request);
        }
        if (request.op == "get-state") {
            return StateResponseJson();
        }
        if (request.op == "list-schemas") {
            return ListSchemasResponseJson();
        }
        if (request.op == "set-option") {
            if (request.name == "ascii_mode") {
                state_.ascii_mode = ParseProtocolBool(request.value);
            } else if (request.name == "full_shape") {
                state_.full_shape = ParseProtocolBool(request.value);
            } else if (request.name == "output_standard") {
                Require(IsKnownOutputStandard(request.value),
                        "unknown output standard");
                state_.output_standard = request.value;
            } else {
                throw std::runtime_error("unknown option name");
            }
            ApplyStateToComposeSessions();
            PersistState();
            return StateResponseJson();
        }
        if (request.op == "select-schema") {
            Require(!request.schema.empty(), "missing schema id");
            Require(SchemaExists(request.schema), "unknown schema id");
            state_.schema_id = request.schema;
            ApplyStateToComposeSessions();
            PersistState();
            return StateResponseJson();
        }
        if (request.op == "set-toolbar-position") {
            state_.toolbar_position_x =
                ParseProtocolInt(request.x, "invalid toolbar x");
            state_.toolbar_position_y =
                ParseProtocolInt(request.y, "invalid toolbar y");
            state_.toolbar_position_set = true;
            PersistState();
            return StateResponseJson();
        }
        if (request.op == "set-skin") {
            Require(IsSafeSkinName(request.name), "invalid skin name");
            state_.toolbar_skin = request.name;
            PersistState();
            return StateResponseJson();
        }
        throw std::runtime_error("unknown op verb");
    }

    std::string ProcessInput(const Request& request) {
        const RimeSessionId session = api_->create_session();
        Require(session != 0, "failed to create session");
        bool session_active = true;
        RimeStatus status = {};
        bool status_active = false;
        RimeContext context = {};
        bool context_active = false;
        try {
            ApplyState(session);
            bool all_keys_consumed = true;
            for (const unsigned char ch : request.input) {
                if (api_->process_key(session, static_cast<int>(ch), 0) != True) {
                    all_keys_consumed = false;
                    break;
                }
            }

            std::string commit_text;
            if (all_keys_consumed) {
                RimeCommit commit = {};
                RIME_STRUCT_INIT(RimeCommit, commit);
                if (api_->get_commit(session, &commit) == True) {
                    commit_text = CStringOrEmpty(commit.text);
                    api_->free_commit(&commit);
                }
            }

            RIME_STRUCT_INIT(RimeStatus, status);
            std::string schema_id = state_.schema_id;
            if (api_->get_status(session, &status) == True) {
                status_active = true;
                schema_id = CStringOrEmpty(status.schema_id);
                api_->free_status(&status);
                status_active = false;
            }

            std::vector<Candidate> candidates;
            if (all_keys_consumed) {
                RIME_STRUCT_INIT(RimeContext, context);
                if (api_->get_context(session, &context) == True) {
                    context_active = true;
                    RimeCandidateListIterator iterator = {};
                    if (api_->candidate_list_begin(session, &iterator) == True) {
                        while (static_cast<int>(candidates.size()) <
                                   kMaxReturnedCandidates &&
                               api_->candidate_list_next(&iterator) == True) {
                            candidates.push_back(
                                CandidateFromRimeCandidate(iterator.candidate));
                        }
                        api_->candidate_list_end(&iterator);
                    }
                    if (candidates.empty()) {
                        for (int i = 0; i < context.menu.num_candidates; ++i) {
                            candidates.push_back(CandidateFromRimeCandidate(
                                context.menu.candidates[i]));
                        }
                    }
                    api_->free_context(&context);
                    context_active = false;
                }
            }
            Require(api_->destroy_session(session) == True,
                    "failed to destroy session");
            session_active = false;

            if (commit_text.empty() && request.commit && !candidates.empty()) {
                commit_text = candidates[0].text;
            }
            std::ostringstream out;
            out << "{\"ready\":true,\"schema_id\":\"" << JsonEscape(schema_id)
                << "\",\"state\":" << StateJson()
                << ",\"candidate_count\":" << candidates.size()
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

    HMODULE library_ = nullptr;
    RimeYuneWindowsProfileApi* profile_api_ = nullptr;
    RimeApi* api_ = nullptr;
    RimeTraits traits_ = {};
    std::string shared_dir_;
    std::string user_dir_;
    std::string prebuilt_dir_;
    std::string staging_dir_;
    std::filesystem::path state_file_;
    YuneState state_;
    std::map<std::string, ComposeSession> compose_sessions_;
    unsigned long long next_compose_session_token_ = 1;
    bool initialized_ = false;
};

// After a per-request failure the serve loop pauses briefly before re-accepting,
// so a persistently failing path cannot spin the CPU at 100%.
constexpr DWORD kServeRequestErrorBackoffMs = 50;

// Grant the IME pipe to the current user's own processes at any integrity level
// (including sandboxed AppContainer hosts such as Chrome renderers), and to no
// other user. The current user's SID covers normal same-user apps at any IL; AC
// (all application packages) covers AppContainer/UWP tokens whose user SID is
// restricted; the Low mandatory label lets lower-integrity clients past the
// default No-Write-Up policy. Without an explicit descriptor the pipe uses the
// default, which admits only the server creator's own token, so sandboxed or
// differently-scoped host processes get ERROR_ACCESS_DENIED and typing produces
// no output. Scoping to the current user's SID (rather than the broad IU =
// interactive-users alias) keeps other machine users -- interactive or not --
// off this user's IME pipe. If the SID cannot be resolved we fall back to the
// interactive-users grant so the server still admits sandboxed hosts.
constexpr const wchar_t* kPipeSecurityFallbackSddl =
    L"D:(A;;GRGW;;;IU)(A;;GRGW;;;AC)S:(ML;;NW;;;LW)";

std::wstring CurrentUserSidString() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        return {};
    }
    std::wstring result;
    DWORD needed = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &needed);
    if (needed > 0) {
        std::vector<unsigned char> buffer(needed);
        if (GetTokenInformation(token, TokenUser, buffer.data(), needed,
                                &needed)) {
            const auto* user =
                reinterpret_cast<const TOKEN_USER*>(buffer.data());
            LPWSTR sid_string = nullptr;
            if (ConvertSidToStringSidW(user->User.Sid, &sid_string)) {
                result = sid_string;
                LocalFree(sid_string);
            }
        }
    }
    CloseHandle(token);
    return result;
}

std::wstring PipeSecuritySddl() {
    const std::wstring user_sid = CurrentUserSidString();
    if (user_sid.empty()) {
        return kPipeSecurityFallbackSddl;
    }
    return L"D:(A;;GRGW;;;" + user_sid + L")(A;;GRGW;;;AC)S:(ML;;NW;;;LW)";
}

bool BuildPipeSecurityAttributes(SECURITY_ATTRIBUTES& sa,
                                 PSECURITY_DESCRIPTOR& sd) {
    sd = nullptr;
    const std::wstring sddl = PipeSecuritySddl();
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.c_str(), SDDL_REVISION_1, &sd, nullptr)) {
        return false;
    }
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = sd;
    sa.bInheritHandle = FALSE;
    return true;
}

void ServeOnce(const Args& args, YuneRuntime& runtime) {
    SECURITY_ATTRIBUTES sa = {};
    PSECURITY_DESCRIPTOR sd = nullptr;
    LPSECURITY_ATTRIBUTES psa =
        BuildPipeSecurityAttributes(sa, sd) ? &sa : nullptr;
    HANDLE pipe = CreateNamedPipeW(
        args.pipe_name.c_str(), PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT, 1, 64 * 1024,
        64 * 1024, 0, psa);
    if (pipe == INVALID_HANDLE_VALUE && psa != nullptr) {
        // The hardened descriptor was rejected; fall back to the default so the
        // server still runs (it just won't admit sandboxed hosts).
        pipe = CreateNamedPipeW(
            args.pipe_name.c_str(), PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT, 1, 64 * 1024,
            64 * 1024, 0, nullptr);
    }
    if (sd != nullptr) {
        LocalFree(sd);
    }
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
        if (args.once) {
            // One-shot mode (dev REPL / contracts): a failure should still surface
            // as a non-zero exit, so let it propagate to the outer handler.
            ServeOnce(args, runtime);
        } else {
            // Shared, long-lived server: a single bad request must never take it
            // down, because every app's IME depends on this one process. The most
            // common trigger is a client that hit its own query timeout and closed
            // the pipe mid-response (F2), which fails the server's WriteFile/flush.
            // Catch per-request failures, log, and keep serving; only a fatal
            // runtime init/deploy failure (the YuneRuntime ctor above) exits.
            for (;;) {
                try {
                    ServeOnce(args, runtime);
                } catch (const std::exception& error) {
                    std::cerr << "YuneWindowsServer request error (continuing): "
                              << error.what() << "\n";
                    Sleep(kServeRequestErrorBackoffMs);
                } catch (...) {
                    std::cerr << "YuneWindowsServer request error (continuing): "
                                 "unknown exception\n";
                    Sleep(kServeRequestErrorBackoffMs);
                }
            }
        }
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
