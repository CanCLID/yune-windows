# Roadmap

Yune Windows is the Windows product/frontend track for the Yune engine. It is
intentionally separate from Yune engine-performance work.

## Current Snapshot

| Lane | Current state | Next gate |
| --- | --- | --- |
| Product shell | Renamed public baseline with TSF DLL, shared server, native candidate window, diagnostics tooling, installer scripts, non-elevated contract tests, P2-WIN02 product-owned server startup, and P2-WIN03 development inner-loop tooling. Latest approved live closeout reached install/register, profile activation, Notepad, Chromium, diagnostics export, uninstall, and post-reboot no-residue cleanup. Both text-field smokes passed from the installed path, committed the expected Cantonese text, and recorded product-owned server start/readiness plus profile-active-before-typing evidence. P2-WIN03 installed-server reload is runtime-proven; installed TSF reload correctly safe-aborts when the DLL is held by non-dev desktop processes. Cold start is still synchronous in the TSF key path for up to `kServerLaunchReadyWaitMs = 15000`. | P2-WIN04 Candidate Window and Typing Quality in progress: fix candidate-window caret positioning and the stuck top-left panel, comment hygiene, paging, punctuation. |
| Yune boundary | Windows consumes packaged Yune through `rime_get_api()` plus the opt-in `rime_get_yune_windows_profile_api()` surface. | Keep default `rime_get_api()` unchanged; send new engine needs to Yune as named proposals with tests. |
| Reference code | Legacy Weasel-derived implementation is reference material only. | Extract no more code without a focused audit and smoke proof. |
| Dogfood release | Public repo starts from clean initial history and omits old private evidence. Fresh post-rename live evidence exists, including Notepad, Chromium, diagnostics, recovered cleanup, compatibility matrix, signing decision, and complete closeout audit under the product-owned server contract. Compatibility matrix and signing decision are recorded; dogfood packaging, release signing, non-blocking cold-start, and user-data preservation remain open. | Start dogfood package hardening when selected. |

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
   non-blocking launch remains a fast-follow. Cleanup initially recorded
   `requires_reboot=true` with delayed-delete paths under the install root
   because GUI processes kept `YuneWindowsTSF.dll` loaded, then passed
   post-reboot validation with no residue; see
   `docs/evidence/p2-win02-server-lifecycle/live-closeout-20260630-203015.md`.
6. **Development inner loop** - add non-elevated dev tooling for a no-install
   REPL, installed-server hot reload with backup/rollback, installed TSF DLL
   reload through a dev-owned test window, and dry-run watch routing. The
   installed-server reload is runtime-proven with schema/user-data backup
   coverage; TSF reload guard evidence proves it refuses to close non-dev
   desktop holders. Historical plan:
   `docs/plans/history/p2-win03-plan-dev-inner-loop.md`.

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

## Completed Milestones

### P2-WIN02 - Server Lifecycle And Cleanup Hardening

Status: complete for product-owned server startup and recovered cleanup. The
implementation adds on-demand TSF startup for the shared server, pipe-scoped
duplicate-server protection, product-owned smoke contracts, and structured
uninstall cleanup results. The approved live closeout reached
install/register, profile activation, Notepad, Chromium, diagnostics export,
and structured uninstall. The installed Notepad and Chromium smokes both passed,
committed the expected Cantonese text, and recorded product-owned server
start/readiness evidence without per-smoke activation immediately before
typing. Cleanup scheduled delayed delete for locked install-root files, then
passed post-reboot cleanup validation and closeout audit with no residue. Known
limitation: the first cold keystroke can block the foreground app while the
server starts because TSF waits synchronously for up to
`kServerLaunchReadyWaitMs = 15000`; async launch, broker launch, or another
non-blocking cold-start path remains a dogfood fast-follow.

Historical plan:
`docs/plans/history/p2-win02-plan-server-lifecycle-cleanup-hardening.md`.

### P2-WIN03 - Development Inner Loop

Status: complete for non-elevated development tooling. The implementation adds
`dev-repl.ps1`, `dev-reload-server.ps1`, `dev-test-window.ps1`,
`dev-reload-tsf.ps1`, `dev-watch.ps1`, and static safety contracts. The
installed-path reload scripts keep timestamped backups and roll back on
validation failure; the watch wrapper defaults to dry-run, forwards the exact
`-YuneRoot`, and only runs reload commands with explicit `-AutoRun`.
Installed-server reload with `-RefreshSchema` passed on the live installed path.
Installed TSF reload is implemented, but the runtime attempt correctly
safe-aborted because the installed TSF DLL was held by Chrome, Claude, Codex,
Explorer, GitHub Desktop, Notepad, NVIDIA Overlay, and Telegram. That holder
state requires closing apps/sign-out before a full TSF file swap; the dev tool
must not force-close those apps. Installed-path reloads are development evidence
only and do not close dogfood readiness. Evidence:
`docs/evidence/p2-win03-dev-inner-loop/runtime-validation-20260701.md`.

Historical plan:
`docs/plans/history/p2-win03-plan-dev-inner-loop.md`.

## Candidate Next Milestones (for discussion)

P2-WIN02 and P2-WIN03 are complete. The active milestone is **P2-WIN04 Candidate
Window and Typing Quality** (see
`docs/plans/active/p2-win04-plan-candidate-window-typing-quality.md`), prompted by
dogfooding: the candidate panel lands in the top-left instead of at the caret and
can get stuck on screen, and candidate comments show raw dictionary CSV. The
other rows remain candidates.

| Candidate | Delivers | Rough size | Key dependency / risk |
| --- | --- | --- | --- |
| **P2-WIN04 - Candidate Window and Typing Quality (active)** | Fix candidate-window caret positioning and the stuck/orphaned top-left panel; candidate comment hygiene; candidate paging; punctuation/full-width input. Makes the installed IME usable for daily typing. | L (four slices) | Positioning/paging/punctuation are DLL-side (holder-free reload session); comment hygiene is server-side (fast loop). Plan: `docs/plans/active/p2-win04-plan-candidate-window-typing-quality.md`. Learning/userdb split to a later milestone. |
| **Non-blocking cold-start / per-user broker** | Removes the up-to-15s foreground freeze on the first cold keystroke and makes launch work in sandboxed/AppContainer hosts (UWP, WeChat, some Store/Electron). Reduces AV/EDR risk of spawning an unsigned exe from a browser. | M | Adds per-user autostart/broker state that install/uninstall must create and remove; documented P2-WIN02 fast-follow. |
| **Dogfood package hardening (WIN-11)** | Self-contained install bundle decoupled from the local Yune source build, so a second machine can install without a Rust/Yune toolchain. | M | Production signing stays deferred; needs pre-staged `rime.dll` + schema + binaries + `install-info.json`. |
| **User-data preservation (D-09)** | Preserve or migrate the learned dictionary / personalization across reinstall loops instead of deleting `user-data` on uninstall. | S | Decide backup vs. a `-PurgeUserData` switch; small but touches the uninstall path. |
| **Deferred (Scope Ledger)** | Production signing + release distribution, rich settings UI (WebView2), auto-update, Store packaging, broader compatibility matrix (Win10, Office/Electron/UWP). | varies | Formally deferred until typing evidence + security review; keep behind the above. |

### P2-WIN04 workstream notes

Sequence: do the server-side comment fix first (fast loop), then batch the
DLL-side candidate-window and input work in a holder-free session (the DLL swap
needs the holder apps closed).

1. **Comment hygiene (server, fast loop)**: the `jyut6ping3` dictionary packs a
   CSV comment for the web UI; the server passes it through and the candidate
   window draws it raw. Simplify it server-side (extract jyutping / blank) so it
   does not touch the shared web schema; iterate via `dev-reload-server`.
2. **Candidate window correctness (DLL)** - the top usability bugs from
   dogfooding: `ShowCandidates` (`src\tsf\yune_windows_tsf.cpp`) anchors on
   `GetScreenExt`/`{80,80}` instead of the caret - fix with
   `ITfContextView::GetTextExt` in a read edit session; the parentless
   `WS_EX_TOPMOST` candidate window can orphan on screen - give it an owner window
   and complete every hide path.
3. **Paging (DLL)**: add a page index + paging keys; first cut can page
   client-side over a larger candidate list, avoiding a session-model change.
4. **Punctuation / full-width (DLL + schema)**: forward punctuation keys to the
   schema `punct_translator`. Tone-digit vs 1-9-selection is moot for toneless
   input (`ngohaig`).

Learning / userdb is intentionally split to a **later** milestone: it is a
protocol change (persistent per-client session, select-index/commit feedback,
userdb persistence, D-05 secure-context suppression with a fresh live privacy
proof), not a flag flip, and should not ride the candidate-window work.

### Cross-cutting

- The synchronous cold-start wait (`kServerLaunchReadyWaitMs = 15000`) will
  color the daily-typing experience even though it is a separate milestone;
  weigh the broker candidate against P2-WIN04 accordingly.
- Keep live IME install/register/uninstall loops approval-gated and
  reboot-aware regardless of which candidate is chosen.
