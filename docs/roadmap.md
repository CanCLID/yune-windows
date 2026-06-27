# Roadmap

Yune Windows is the Windows product/frontend track for the Yune engine. It is
intentionally separate from Yune engine-performance work.

## Current Snapshot

| Lane | Current state | Next gate |
| --- | --- | --- |
| Product shell | Renamed public baseline with TSF DLL, shared server, native candidate window, diagnostics tooling, installer scripts, and non-elevated contract tests. | Rebuild against the current Yune Windows package and regenerate post-rename live evidence. |
| Yune boundary | Windows consumes packaged Yune through `rime_get_api()` plus the opt-in `rime_get_yune_windows_profile_api()` surface. | Keep default `rime_get_api()` unchanged; send new engine needs to Yune as named proposals with tests. |
| Reference code | Legacy Weasel-derived implementation is reference material only. | Extract no more code without a focused audit and smoke proof. |
| Dogfood release | Public repo starts from clean initial history and omits old private evidence. | Run fresh install/register/Notepad/Chromium/diagnostics/uninstall/cleanup evidence before dogfood. |

## Active Sequence

1. **Public rename baseline** - source, scripts, docs, TSF identity, IPC pipe,
   install root, executable names, and Yune package API names use Yune Windows
   naming.
2. **Non-elevated verification** - naming gate, Yune package smoke, TSF shell
   build, host smoke, IPC smoke, candidate-window smoke, installer safety
   contracts, and machine-state approval-gate tests pass without elevated
   machine changes.
3. **Clean public publish** - initialize `CanCLID/yune-windows` from a clean
   initial commit on `main` only.
4. **Dogfood evidence refresh** - with fresh approval, run the full live
   install/register/profile activation, Notepad, Chromium, diagnostics,
   uninstall, and cleanup sequence under the Yune Windows names.

## Scope Ledger

| In scope | Deferred | Non-goal |
| --- | --- | --- |
| Windows TSF input delivery | Production signing and release distribution | Rebuilding Yune engine internals here |
| Shared server/IPC process model | Rich settings UI until typing evidence is refreshed | Runtime librime fallback |
| Yune package loading | Auto-update until security review | Cloning old Weasel UI architecture |
| Native candidate window | WebView2 candidate window until latency/focus are proven | Widening Yune default ABI |
| Installer, uninstall, diagnostics | Store packaging | Using product evidence to close Yune engine milestones |

## Live Evidence Shape

Dogfood is not ready until fresh post-rename evidence proves:

- clean install target and packaged Yune inputs;
- TSF registration and Yune Windows profile activation;
- `ngohaig` typed into Notepad through Yune;
- candidate display and candidate commit;
- one Chromium-based text-field smoke;
- diagnostics/log export without typed-content leakage;
- uninstall and cleanup validation;
- no install directory, TSF DLL, server process, TSF profile, or machine
  residue left behind.
