#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <msctf.h>

#include <iostream>
#include <string>

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

bool SameGuid(REFGUID left, REFGUID right) {
    return IsEqualGUID(left, right) == TRUE;
}

void PrintState(ITfInputProcessorProfileMgr* profile_mgr) {
    bool registered = false;
    bool active = false;

    IEnumTfInputProcessorProfiles* profiles = nullptr;
    if (SUCCEEDED(profile_mgr->EnumProfiles(kTextServiceLangId, &profiles))) {
        TF_INPUTPROCESSORPROFILE profile = {};
        ULONG fetched = 0;
        while (profiles->Next(1, &profile, &fetched) == S_OK && fetched == 1) {
            if (profile.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR &&
                SameGuid(profile.clsid, kTextServiceClsid) &&
                SameGuid(profile.guidProfile, kProfileGuid)) {
                registered = true;
                break;
            }
        }
        profiles->Release();
    }

    TF_INPUTPROCESSORPROFILE active_profile = {};
    if (SUCCEEDED(profile_mgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,
                                                &active_profile))) {
        active = active_profile.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR &&
                 SameGuid(active_profile.clsid, kTextServiceClsid) &&
                 SameGuid(active_profile.guidProfile, kProfileGuid);
    }

    std::cout << "{\"registered\":" << (registered ? "true" : "false")
              << ",\"active\":" << (active ? "true" : "false")
              << ",\"langid\":" << kTextServiceLangId
              << ",\"profile_guid\":\"{3AE69B8D-19B4-4267-8F21-E239666D6632}\""
              << ",\"clsid\":\"{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}\"}\n";
}

int Run(int argc, wchar_t** argv) {
    const bool activate = argc >= 2 && std::wstring(argv[1]) == L"--activate";
    const bool deactivate = argc >= 2 && std::wstring(argv[1]) == L"--deactivate";
    const bool state = argc == 1 || (argc >= 2 && std::wstring(argv[1]) == L"--state");
    if (!activate && !deactivate && !state) {
        std::cerr << "usage: YuneWindowsProfileTool.exe [--state|--activate|--deactivate]\n";
        return 2;
    }

    ITfInputProcessorProfileMgr* profile_mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfileMgr,
                                  reinterpret_cast<void**>(&profile_mgr));
    if (FAILED(hr)) {
        std::cerr << "failed to create input profile manager: 0x" << std::hex
                  << hr << "\n";
        return 1;
    }

    if (activate) {
        hr = profile_mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,
                                          kTextServiceLangId, kTextServiceClsid,
                                          kProfileGuid, nullptr,
                                          TF_IPPMF_FORSESSION);
        if (FAILED(hr)) {
            profile_mgr->Release();
            std::cerr << "failed to activate YuneWindows profile: 0x" << std::hex
                      << hr << "\n";
            return 1;
        }
    }
    if (deactivate) {
        hr = profile_mgr->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,
                                            kTextServiceLangId, kTextServiceClsid,
                                            kProfileGuid, nullptr,
                                            TF_IPPMF_FORSESSION);
        if (FAILED(hr)) {
            profile_mgr->Release();
            std::cerr << "failed to deactivate YuneWindows profile: 0x" << std::hex
                      << hr << "\n";
            return 1;
        }
    }

    PrintState(profile_mgr);
    profile_mgr->Release();
    return 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool should_uninit = SUCCEEDED(hr);
    if (hr == RPC_E_CHANGED_MODE) {
        hr = S_OK;
    }
    if (FAILED(hr)) {
        std::cerr << "failed to initialize COM: 0x" << std::hex << hr << "\n";
        return 1;
    }
    const int result = Run(argc, argv);
    if (should_uninit) {
        CoUninitialize();
    }
    return result;
}
