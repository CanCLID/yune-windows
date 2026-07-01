#include <windows.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "rime_yune_windows_profile_api.h"

namespace {

using GetProfileApiFn = RimeYuneWindowsProfileApi* (*)();
constexpr int kMaxReturnedCandidates = 30;

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
    std::vector<std::string> unknown_fields;
    bool commit = false;
};

struct YuneState {
    std::string schema_id = "jyut6ping3";
    bool ascii_mode = false;
    bool full_shape = false;
    std::string output_standard = "hong_kong_traditional";
};

struct SchemaInfo {
    std::string schema_id;
    std::string name;
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
                    api_->free_commit && api_->get_context &&
                    api_->get_schema_list && api_->free_schema_list &&
                    api_->get_current_schema &&
                    api_->free_context && api_->candidate_list_begin &&
                    api_->candidate_list_next && api_->candidate_list_end &&
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
            << "\"\n"
            << "}\n";
        Require(static_cast<bool>(out), "failed to write IME state file");
    }

    std::string StateJson() const {
        std::ostringstream out;
        out << "{\"schema_id\":\"" << JsonEscape(state_.schema_id)
            << "\",\"ascii_mode\":" << (state_.ascii_mode ? "true" : "false")
            << ",\"full_shape\":" << (state_.full_shape ? "true" : "false")
            << ",\"output_standard\":\"" << JsonEscape(state_.output_standard)
            << "\"}";
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

    std::string ProcessOperation(const Request& request) {
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
            PersistState();
            return StateResponseJson();
        }
        if (request.op == "select-schema") {
            Require(!request.schema.empty(), "missing schema id");
            Require(SchemaExists(request.schema), "unknown schema id");
            state_.schema_id = request.schema;
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
