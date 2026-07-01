# Roadmap

Yune Windows is the Windows product/frontend track for the Yune engine. It is
intentionally separate from Yune engine-performance work.

## Current Snapshot

| Lane | Current state | Next gate |
| --- | --- | --- |
| Product shell | Renamed public baseline with TSF DLL, shared server, native candidate window, diagnostics tooling, installer scripts, non-elevated contract tests, and P2-WIN02 product-owned server startup implementation. Latest approved live closeout reached install/register, profile activation, Notepad, Chromium, diagnostics export, uninstall, and post-reboot no-residue cleanup. Both text-field smokes passed from the installed path, committed `我係個`, and recorded product-owned server start/readiness plus profile-active-before-typing evidence. Cold start is still synchronous in the TSF key path for up to `kServerLaunchReadyWaitMs = 15000`. | Move to dogfood package hardening and release evidence, including non-blocking cold-start and user-data preservation follow-ups. |
| Yune boundary | Windows consumes packaged Yune through `rime_get_api()` plus the opt-in `rime_get_yune_windows_profile_api()` surface. | Keep default `rime_get_api()` unchanged; send new engine needs to Yune as named proposals with tests. |
| Reference code | Legacy Weasel-derived implementation is reference material only. | Extract no more code without a focused audit and smoke proof. |
| Dogfood release | Public repo starts from clean initial history and omits old private evidence. Fresh post-rename live evidence exists, including Notepad, Chromium, diagnostics, recovered cleanup, compatibility matrix, signing decision, and complete closeout audit under the product-owned server contract. Compatibility matrix and signing decision are recorded; dogfood packaging, release signing, non-blocking cold-start, and user-data preservation remain open. | Start dogfood package hardening. |

## Completed Sequence

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
5. **Server lifecycle hardening** - implement product-owned
   `YuneWindowsServer.exe` startup, keep IPC bounded, and make
   installer/uninstaller cleanup evidence reliable enough for repeat dogfood
   runs. Status: latest live closeout reached install/register, profile
   activation, Notepad, Chromium, diagnostics export, and structured uninstall.
   Both text-field smokes passed from the installed path without a manual server
   start and recorded product-owned server start/readiness evidence. The current
   cold-start readiness path is bounded but synchronous in the TSF key path, so
   non-blocking launch remains a fast-follow. Cleanup
   initially recorded `requires_reboot=true` with delayed-delete paths under the
   install root because GUI processes kept `YuneWindowsTSF.dll` loaded, then
   passed post-reboot validation with no residue; see
   `docs/evidence/p2-win02-server-lifecycle/live-closeout-20260630-203015.md`.

## Scope Ledger

| In scope | Deferred | Non-goal |
| --- | --- | --- |
| Windows TSF input delivery | Production signing and release distribution | Rebuilding Yune engine internals here |
| Shared server/IPC process model | Rich settings UI until typing evidence is refreshed | Runtime librime fallback |
| Yune package loading | Auto-update until security review | Cloning old Weasel UI architecture |
| Native candidate window | WebView2 candidate window until latency/focus are proven | Widening Yune default ABI |
| Installer, uninstall, diagnostics | Store packaging | Using product evidence to close Yune engine milestones |

## Live Evidence Shape

The completed post-rename live evidence proves:

- clean install target and packaged Yune inputs;
- TSF registration and Yune Windows profile activation;
- `ngohaig` typed into Notepad through Yune;
- candidate display and candidate commit;
- one Chromium-based text-field smoke;
- diagnostics/log export without typed-content leakage;
- shared server readiness before typing, without requiring an operator to run a
  separate server command;
- uninstall and cleanup validation;
- no install directory, TSF DLL, server process, TSF profile, or machine
  residue left behind.

## Completed Milestone

**P2-WIN02 - Server Lifecycle And Cleanup Hardening**

Status: complete for product-owned server startup and recovered cleanup. The
implementation adds on-demand TSF startup for the shared server, pipe-scoped
duplicate-server protection, product-owned smoke contracts, and structured
uninstall cleanup results. The approved live closeout reached
install/register, profile activation, Notepad, Chromium, diagnostics export,
and structured uninstall. The installed Notepad and Chromium smokes both passed,
committed `我係個`, and recorded product-owned server start/readiness evidence
without per-smoke activation immediately before typing. Cleanup scheduled
delayed delete for locked install-root files, then passed post-reboot
cleanup validation and closeout audit with no residue. Known limitation: the
first cold keystroke can block the foreground app while the server starts
because TSF waits synchronously for up to `kServerLaunchReadyWaitMs = 15000`;
async launch, broker launch, or another non-blocking cold-start path remains a
dogfood fast-follow.

Historical plan:
`docs/plans/history/p2-win02-plan-server-lifecycle-cleanup-hardening.md`.

## Next Milestone

**Dogfood Package Hardening**

Start packaging and release-evidence work from the completed P2-WIN02 baseline.
Keep live IME install/register/uninstall loops approval-gated and reboot-aware.
Add dogfood follow-ups for non-blocking cold-start readiness and for preserving
or migrating learned dictionary/personalization data across reinstall loops;
today uninstall removes the install tree including `user-data` unless
`-KeepFiles` is used.
