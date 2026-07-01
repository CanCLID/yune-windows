#include <windows.h>

#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "rime_yune_windows_profile_api.h"

namespace {

using GetApiFn = RimeApi* (*)();
using GetProfileApiFn = RimeYuneWindowsProfileApi* (*)();

struct Args {
    std::wstring rime_dll;
    std::wstring shared_dir;
    std::wstring user_dir;
    std::wstring output;
    std::string schema = "jyut6ping3";
    std::string input = "ngohaig";
    bool sensitive = false;
};

struct Lifecycle {
    bool load = false;
    bool setup = false;
    bool deployer_initialize = false;
    bool initialize = false;
    bool start_maintenance = false;
    bool join_maintenance = false;
    bool deploy = false;
    bool create_session = false;
    bool select_schema = false;
    bool process_keys = false;
    bool get_status = false;
    bool get_context = false;
    bool destroy_session = false;
    bool finalize = false;
};

struct DeployDiagnostics {
    bool default_config = false;
    bool schema = false;
    bool workspace_update_schema = false;
    bool full_deploy = false;
    bool artifact_fallback = false;
};

struct CandidateRow {
    int index = 0;
    std::string text;
    std::string comment;
};

struct RuntimeObservation {
    bool raw_input_available = false;
    std::string raw_input;
    bool status_available = false;
    std::string schema_id;
    std::string schema_name;
    bool is_composing = false;
    bool ascii_mode = false;
    bool context_available = false;
    int composition_length = 0;
    int composition_cursor_pos = 0;
    std::string preedit;
    int candidate_count = 0;
    int page_size = 0;
    int highlighted_candidate_index = 0;
    std::vector<CandidateRow> candidates;
};

std::wstring RequireValue(int argc, wchar_t** argv, int& index) {
    if (index + 1 >= argc) {
        throw std::runtime_error("missing value for argument");
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
        throw std::runtime_error("failed to convert path to UTF-8");
    }
    std::string output(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        output.data(), size, nullptr, nullptr);
    return output;
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
        } else if (key == L"--output") {
            args.output = RequireValue(argc, argv, i);
        } else if (key == L"--schema") {
            args.schema = Narrow(RequireValue(argc, argv, i));
        } else if (key == L"--input") {
            args.input = Narrow(RequireValue(argc, argv, i));
        } else if (key == L"--sensitive") {
            args.sensitive = true;
        } else {
            throw std::runtime_error("unknown argument");
        }
    }
    if (args.rime_dll.empty() || args.shared_dir.empty() ||
        args.user_dir.empty() || args.output.empty()) {
        throw std::runtime_error(
            "required arguments: --rime-dll --shared-dir --user-dir --output");
    }
    return args;
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
            case '\b':
                out << "\\b";
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
                    out << "\\u" << std::hex << std::setw(4)
                        << std::setfill('0') << static_cast<int>(ch)
                        << std::dec << std::setfill(' ');
                } else {
                    out << static_cast<char>(ch);
                }
        }
    }
    return out.str();
}

const char* BoolJson(bool value) {
    return value ? "true" : "false";
}

void WriteLifecycleJson(std::ofstream& out, const Lifecycle& lifecycle,
                        const std::string& indent) {
    out << indent << "\"load\": " << BoolJson(lifecycle.load) << ",\n";
    out << indent << "\"setup\": " << BoolJson(lifecycle.setup) << ",\n";
    out << indent << "\"deployer_initialize\": "
        << BoolJson(lifecycle.deployer_initialize) << ",\n";
    out << indent << "\"initialize\": " << BoolJson(lifecycle.initialize)
        << ",\n";
    out << indent << "\"start_maintenance\": "
        << BoolJson(lifecycle.start_maintenance) << ",\n";
    out << indent << "\"join_maintenance\": "
        << BoolJson(lifecycle.join_maintenance) << ",\n";
    out << indent << "\"deploy\": " << BoolJson(lifecycle.deploy) << ",\n";
    out << indent << "\"create_session\": "
        << BoolJson(lifecycle.create_session) << ",\n";
    out << indent << "\"select_schema\": "
        << BoolJson(lifecycle.select_schema) << ",\n";
    out << indent << "\"process_keys\": " << BoolJson(lifecycle.process_keys)
        << ",\n";
    out << indent << "\"get_status\": " << BoolJson(lifecycle.get_status)
        << ",\n";
    out << indent << "\"get_context\": " << BoolJson(lifecycle.get_context)
        << ",\n";
    out << indent << "\"destroy_session\": "
        << BoolJson(lifecycle.destroy_session) << ",\n";
    out << indent << "\"finalize\": " << BoolJson(lifecycle.finalize)
        << "\n";
}

void WriteDeployDiagnosticsJson(std::ofstream& out,
                                const DeployDiagnostics& diagnostics,
                                const std::string& indent) {
    out << indent << "\"default_config\": "
        << BoolJson(diagnostics.default_config) << ",\n";
    out << indent << "\"schema\": " << BoolJson(diagnostics.schema) << ",\n";
    out << indent << "\"workspace_update_schema\": "
        << BoolJson(diagnostics.workspace_update_schema) << ",\n";
    out << indent << "\"full_deploy\": " << BoolJson(diagnostics.full_deploy)
        << ",\n";
    out << indent << "\"artifact_fallback\": "
        << BoolJson(diagnostics.artifact_fallback)
        << "\n";
}

void WriteRuntimeObservationJson(std::ofstream& out,
                                 const RuntimeObservation& observation,
                                 const std::string& indent) {
    out << indent << "\"raw_input_available\": "
        << BoolJson(observation.raw_input_available) << ",\n";
    out << indent << "\"raw_input\": \"" << JsonEscape(observation.raw_input)
        << "\",\n";
    out << indent << "\"status_available\": "
        << BoolJson(observation.status_available) << ",\n";
    out << indent << "\"schema_id\": \""
        << JsonEscape(observation.schema_id) << "\",\n";
    out << indent << "\"schema_name\": \""
        << JsonEscape(observation.schema_name) << "\",\n";
    out << indent << "\"is_composing\": "
        << BoolJson(observation.is_composing) << ",\n";
    out << indent << "\"ascii_mode\": " << BoolJson(observation.ascii_mode)
        << ",\n";
    out << indent << "\"context_available\": "
        << BoolJson(observation.context_available) << ",\n";
    out << indent << "\"composition_length\": "
        << observation.composition_length << ",\n";
    out << indent << "\"composition_cursor_pos\": "
        << observation.composition_cursor_pos << ",\n";
    out << indent << "\"preedit\": \"" << JsonEscape(observation.preedit)
        << "\",\n";
    out << indent << "\"candidate_count\": "
        << observation.candidate_count << ",\n";
    out << indent << "\"page_size\": " << observation.page_size << ",\n";
    out << indent << "\"highlighted_candidate_index\": "
        << observation.highlighted_candidate_index << ",\n";
    out << indent << "\"candidates\": [\n";
    for (size_t i = 0; i < observation.candidates.size(); ++i) {
        const auto& candidate = observation.candidates[i];
        out << indent << "  {\"index\": " << candidate.index
            << ", \"text\": \"" << JsonEscape(candidate.text)
            << "\", \"comment\": \"" << JsonEscape(candidate.comment)
            << "\"}";
        if (i + 1 < observation.candidates.size()) {
            out << ",";
        }
        out << "\n";
    }
    out << indent << "]\n";
}

std::string CStringOrEmpty(const char* value) {
    return value == nullptr ? std::string{} : std::string(value);
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

void WriteResult(const Args& args, const Lifecycle& lifecycle,
                 const DeployDiagnostics& deploy_diagnostics,
                 int default_api_size, int profile_api_size,
                 const std::string& schema_id, bool is_composing,
                 bool ascii_mode, int page_size, int highlighted,
                 const std::vector<CandidateRow>& candidates,
                 bool yune_disable_learning_option) {
    std::filesystem::create_directories(std::filesystem::path(args.output).parent_path());
    std::ofstream out(args.output, std::ios::binary);
    Require(out.good(), "failed to open output JSON");
    const unsigned char utf8_bom[] = {0xEF, 0xBB, 0xBF};
    out.write(reinterpret_cast<const char*>(utf8_bom), sizeof(utf8_bom));

    out << "{\n";
    out << "  \"input\": \"" << JsonEscape(args.input) << "\",\n";
    out << "  \"schema\": \"" << JsonEscape(args.schema) << "\",\n";
    out << "  \"exports\": {\n";
    out << "    \"rime_get_api\": true,\n";
    out << "    \"rime_get_yune_windows_profile_api\": true,\n";
    out << "    \"default_api_data_size\": " << default_api_size << ",\n";
    out << "    \"profile_api_data_size\": " << profile_api_size << "\n";
    out << "  },\n";
    out << "  \"lifecycle\": {\n";
    WriteLifecycleJson(out, lifecycle, "    ");
    out << "  },\n";
    out << "  \"deploy_diagnostics\": {\n";
    WriteDeployDiagnosticsJson(out, deploy_diagnostics, "    ");
    out << "  },\n";
    out << "  \"status\": {\n";
    out << "    \"schema_id\": \"" << JsonEscape(schema_id) << "\",\n";
    out << "    \"is_composing\": " << BoolJson(is_composing) << ",\n";
    out << "    \"ascii_mode\": " << BoolJson(ascii_mode) << "\n";
    out << "  },\n";
    out << "  \"context\": {\n";
    out << "    \"candidate_count\": " << candidates.size() << ",\n";
    out << "    \"page_size\": " << page_size << ",\n";
    out << "    \"highlighted_candidate_index\": " << highlighted << ",\n";
    out << "    \"candidates\": [\n";
    for (size_t i = 0; i < candidates.size(); ++i) {
        const auto& candidate = candidates[i];
        out << "      {\"index\": " << candidate.index << ", \"text\": \""
            << JsonEscape(candidate.text) << "\", \"comment\": \""
            << JsonEscape(candidate.comment) << "\"}";
        if (i + 1 < candidates.size()) {
            out << ",";
        }
        out << "\n";
    }
    out << "    ]\n";
    out << "  },\n";
    out << "  \"sensitive_context\": {\n";
    out << "    \"enabled\": " << BoolJson(args.sensitive) << ",\n";
    out << "    \"typed_content_logs\": false,\n";
    out << "    \"ai_staging\": false,\n";
    out << "    \"learning\": false,\n";
    out << "    \"yune_disable_learning_option\": "
        << BoolJson(yune_disable_learning_option) << "\n";
    out << "  }\n";
    out << "}\n";
}

void WriteFailureResult(const Args& args, const Lifecycle& lifecycle,
                        const DeployDiagnostics& deploy_diagnostics,
                        const RuntimeObservation& observation,
                        const std::string& failure_stage,
                        const std::string& error) {
    std::filesystem::create_directories(std::filesystem::path(args.output).parent_path());
    std::ofstream out(args.output, std::ios::binary);
    Require(out.good(), "failed to open failure output JSON");
    const unsigned char utf8_bom[] = {0xEF, 0xBB, 0xBF};
    out.write(reinterpret_cast<const char*>(utf8_bom), sizeof(utf8_bom));

    out << "{\n";
    out << "  \"result\": \"failed\",\n";
    out << "  \"failure_stage\": \"" << JsonEscape(failure_stage) << "\",\n";
    out << "  \"error\": \"" << JsonEscape(error) << "\",\n";
    out << "  \"input\": \"" << JsonEscape(args.input) << "\",\n";
    out << "  \"schema\": \"" << JsonEscape(args.schema) << "\",\n";
    out << "  \"lifecycle\": {\n";
    WriteLifecycleJson(out, lifecycle, "    ");
    out << "  },\n";
    out << "  \"deploy_diagnostics\": {\n";
    WriteDeployDiagnosticsJson(out, deploy_diagnostics, "    ");
    out << "  },\n";
    out << "  \"observed_state\": {\n";
    WriteRuntimeObservationJson(out, observation, "    ");
    out << "  }\n";
    out << "}\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    Args args;
    bool args_ready = false;
    HMODULE library = nullptr;
    RimeApi* api = nullptr;
    RimeSessionId session_id = 0;
    Lifecycle lifecycle;
    DeployDiagnostics deploy_diagnostics;
    RuntimeObservation observation;
    bool initialized = false;
    std::string failure_stage = "parse-args";

    try {
        args = ParseArgs(argc, argv);
        args_ready = true;
        failure_stage = "create-user-dir";
        std::filesystem::create_directories(args.user_dir);
        std::filesystem::create_directories(std::filesystem::path(args.user_dir) / L"build");

        failure_stage = "load-rime";
        library = LoadLibraryW(args.rime_dll.c_str());
        Require(library != nullptr, "failed to load packaged rime.dll");
        lifecycle.load = true;

        failure_stage = "resolve-api";
        auto get_api =
            reinterpret_cast<GetApiFn>(GetProcAddress(library, "rime_get_api"));
        auto get_profile_api = reinterpret_cast<GetProfileApiFn>(
            GetProcAddress(library, "rime_get_yune_windows_profile_api"));
        Require(get_api != nullptr, "missing rime_get_api");
        Require(get_profile_api != nullptr,
                "missing rime_get_yune_windows_profile_api");

        RimeApi* default_api = get_api();
        RimeYuneWindowsProfileApi* profile_api = get_profile_api();
        Require(default_api != nullptr, "rime_get_api returned null");
        Require(profile_api != nullptr,
                "rime_get_yune_windows_profile_api returned null");
        Require(profile_api->config_list_append_string != nullptr,
                "profile API missing config_list_append_string");
        Require(profile_api->upstream.data_size > default_api->data_size,
                "profile API must be larger than the default API");
        api = &profile_api->upstream;

        const std::string shared_dir = Narrow(args.shared_dir);
        const std::string user_dir = Narrow(args.user_dir);
        const std::string prebuilt_dir =
            Narrow((std::filesystem::path(args.shared_dir) / L"build").wstring());
        const std::string staging_dir =
            Narrow((std::filesystem::path(args.user_dir) / L"build").wstring());

        RimeTraits traits = {};
        RIME_STRUCT_INIT(RimeTraits, traits);
        traits.shared_data_dir = shared_dir.c_str();
        traits.user_data_dir = user_dir.c_str();
        traits.distribution_name = "Yune Windows";
        traits.distribution_code_name = "yune-windows";
        traits.distribution_version = "0.1.0-dev";
        traits.app_name = "rime.yune-windows.host-smoke";
        traits.min_log_level = 2;
        traits.log_dir = "";
        traits.prebuilt_data_dir = prebuilt_dir.c_str();
        traits.staging_dir = staging_dir.c_str();

        failure_stage = "validate-api";
        Require(api->setup != nullptr, "API missing setup");
        Require(api->deployer_initialize != nullptr,
                "API missing deployer_initialize");
        Require(api->initialize != nullptr, "API missing initialize");
        Require(api->start_maintenance != nullptr,
                "API missing start_maintenance");
        Require(api->join_maintenance_thread != nullptr,
                "API missing join_maintenance_thread");
        Require(api->deploy != nullptr, "API missing deploy");
        Require(api->deploy_schema != nullptr, "API missing deploy_schema");
        Require(api->deploy_config_file != nullptr,
                "API missing deploy_config_file");
        Require(api->run_task != nullptr, "API missing run_task");
        Require(api->create_session != nullptr, "API missing create_session");
        Require(api->select_schema != nullptr, "API missing select_schema");
        Require(api->process_key != nullptr, "API missing process_key");
        Require(api->set_option != nullptr, "API missing set_option");
        Require(api->get_option != nullptr, "API missing get_option");
        Require(api->get_status != nullptr, "API missing get_status");
        Require(api->free_status != nullptr, "API missing free_status");
        Require(api->get_context != nullptr, "API missing get_context");
        Require(api->free_context != nullptr, "API missing free_context");
        Require(api->destroy_session != nullptr, "API missing destroy_session");
        Require(api->finalize != nullptr, "API missing finalize");

        failure_stage = "setup";
        api->setup(&traits);
        lifecycle.setup = true;
        failure_stage = "deployer-initialize";
        api->deployer_initialize(&traits);
        lifecycle.deployer_initialize = true;
        failure_stage = "initialize";
        api->initialize(&traits);
        lifecycle.initialize = true;
        initialized = true;
        failure_stage = "start-maintenance";
        lifecycle.start_maintenance = api->start_maintenance(True) == True;
        failure_stage = "join-maintenance";
        api->join_maintenance_thread();
        lifecycle.join_maintenance = true;
        failure_stage = "deploy-default-config";
        Require(api->deploy_config_file("default.yaml", "config_version") == True,
                "Yune default config deploy failed");
        deploy_diagnostics.default_config = true;
        failure_stage = "deploy-schema";
        const std::string schema_file = args.schema + ".schema.yaml";
        Require(api->deploy_schema(schema_file.c_str()) == True,
                "Yune schema deploy failed");
        deploy_diagnostics.schema = true;
        failure_stage = "workspace-update-schema";
        const std::string workspace_update_task =
            "workspace_update:" + args.schema;
        if (api->run_task(workspace_update_task.c_str()) == True) {
            deploy_diagnostics.workspace_update_schema = true;
        } else {
            deploy_diagnostics.artifact_fallback =
                SelectedSchemaArtifactsExist(args.user_dir, args.schema);
            Require(deploy_diagnostics.artifact_fallback,
                    "Yune schema workspace update failed and selected schema artifacts are missing");
        }
        failure_stage = "deploy";
        if (api->deploy() == True) {
            deploy_diagnostics.full_deploy = true;
        } else {
            deploy_diagnostics.artifact_fallback =
                SelectedSchemaArtifactsExist(args.user_dir, args.schema);
            Require(deploy_diagnostics.artifact_fallback,
                    "Yune deploy failed and selected schema artifacts are missing");
        }
        lifecycle.deploy = true;

        failure_stage = "create-session";
        session_id = api->create_session();
        Require(session_id != 0, "failed to create Yune session");
        lifecycle.create_session = true;

        failure_stage = "select-schema";
        Require(api->select_schema(session_id, args.schema.c_str()) == True,
                "failed to select jyut6ping3");
        lifecycle.select_schema = true;

        failure_stage = "set-composition-options";
        api->set_option(session_id, "ascii_mode", False);
        Require(api->get_option(session_id, "ascii_mode") == False,
                "failed to disable Yune ascii_mode");

        bool yune_disable_learning_option = false;
        if (args.sensitive) {
            failure_stage = "set-sensitive-options";
            api->set_option(session_id, "disable_learning", True);
            yune_disable_learning_option =
                api->get_option(session_id, "disable_learning") == True;
            Require(yune_disable_learning_option,
                    "failed to enable Yune disable_learning option");
        }

        failure_stage = "process-keys";
        for (const unsigned char ch : args.input) {
            Require(api->process_key(session_id, static_cast<int>(ch), 0) == True,
                    "Yune rejected smoke key");
        }
        lifecycle.process_keys = true;
        if (api->get_input != nullptr) {
            observation.raw_input =
                CStringOrEmpty(api->get_input(session_id));
            observation.raw_input_available = true;
        }

        failure_stage = "get-status";
        RimeStatus status = {};
        RIME_STRUCT_INIT(RimeStatus, status);
        Require(api->get_status(session_id, &status) == True,
                "failed to read status");
        lifecycle.get_status = true;
        const std::string schema_id = CStringOrEmpty(status.schema_id);
        const bool is_composing = status.is_composing != False;
        const bool ascii_mode = status.is_ascii_mode != False;
        observation.status_available = true;
        observation.schema_id = schema_id;
        observation.schema_name = CStringOrEmpty(status.schema_name);
        observation.is_composing = is_composing;
        observation.ascii_mode = ascii_mode;
        Require(api->free_status(&status) == True, "failed to free status");

        failure_stage = "get-context";
        RimeContext context = {};
        RIME_STRUCT_INIT(RimeContext, context);
        Require(api->get_context(session_id, &context) == True,
                "failed to read context");
        lifecycle.get_context = true;
        observation.context_available = true;
        observation.composition_length = context.composition.length;
        observation.composition_cursor_pos = context.composition.cursor_pos;
        observation.preedit = CStringOrEmpty(context.composition.preedit);
        observation.candidate_count = context.menu.num_candidates;
        observation.page_size = context.menu.page_size;
        observation.highlighted_candidate_index =
            context.menu.highlighted_candidate_index;

        std::vector<CandidateRow> candidates;
        for (int i = 0; i < context.menu.num_candidates; ++i) {
            const RimeCandidate& candidate = context.menu.candidates[i];
            candidates.push_back(CandidateRow{
                i,
                CStringOrEmpty(candidate.text),
                CStringOrEmpty(candidate.comment),
            });
        }
        observation.candidates = candidates;
        const int page_size = context.menu.page_size;
        const int highlighted = context.menu.highlighted_candidate_index;
        Require(api->free_context(&context) == True, "failed to free context");
        Require(!candidates.empty(), "expected candidate data for ngohaig");

        failure_stage = "destroy-session";
        Require(api->destroy_session(session_id) == True,
                "failed to destroy session");
        session_id = 0;
        lifecycle.destroy_session = true;

        if (api->cleanup_all_sessions != nullptr) {
            api->cleanup_all_sessions();
        }
        api->finalize();
        initialized = false;
        lifecycle.finalize = true;

        failure_stage = "write-result";
        WriteResult(args, lifecycle, deploy_diagnostics, default_api->data_size,
                    profile_api->upstream.data_size, schema_id, is_composing,
                    ascii_mode, page_size, highlighted, candidates,
                    yune_disable_learning_option);
        FreeLibrary(library);
        return 0;
    } catch (const std::exception& error) {
        if (api != nullptr && session_id != 0 && api->destroy_session != nullptr) {
            api->destroy_session(session_id);
        }
        if (api != nullptr && initialized && api->finalize != nullptr) {
            api->finalize();
        }
        if (library != nullptr) {
            FreeLibrary(library);
        }
        if (args_ready && !args.output.empty()) {
            try {
                WriteFailureResult(args, lifecycle, deploy_diagnostics,
                                   observation,
                                   failure_stage, error.what());
            } catch (...) {
            }
        }
        std::cerr << "yune_host_smoke failed: " << error.what() << "\n";
        return 1;
    }
}
