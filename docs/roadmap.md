# Roadmap

Yune Windows is the Windows product/frontend track for the Yune engine. It is
intentionally separate from Yune engine-performance work.

## Current Snapshot

| Lane | Current state | Next gate |
| --- | --- | --- |
| Product shell | Renamed public baseline with TSF DLL, shared server, native candidate window, diagnostics tooling, installer scripts, non-elevated contract tests, M02 product-owned server startup, M03 development inner-loop tooling, and M04 candidate typing-quality implementation. Latest approved live closeout reached install/register, profile activation, Notepad, Chromium, diagnostics export, uninstall, and post-reboot no-residue cleanup. M04 runtime evidence covers clean candidate comments, 30-candidate server supply, full-width punctuation via `get_commit`, and installed-server reload/readiness. Review follow-up hardening adds unique per-run dev REPL pipes, no-anchor popup suppression, and composing-punctuation handling. DLL-side caret placement, no-orphan lifecycle, PageUp/PageDown paging, and punctuation forwarding are build/static/smoke verified; live app proof remains blocked until a holder-free TSF DLL session. Cold start is still synchronous in the TSF key path for up to `kServerLaunchReadyWaitMs = 15000`. Compact milestone summaries live under `docs/evidence/m01/` through `docs/evidence/m05/`; bulky raw artifacts are regenerated only when a fresh gate needs them. | Holder-free M04 live verification, or dogfood package hardening if packaging is prioritized first. |
| Yune boundary | Windows consumes packaged Yune through `rime_get_api()` plus the opt-in `rime_get_yune_windows_profile_api()` surface. | Keep default `rime_get_api()` unchanged; send new engine needs to Yune as named proposals with tests. |
| Reference code | Legacy Weasel-derived implementation is reference material only. | Extract no more code without a focused audit and smoke proof. |
| Dogfood release | Public repo starts from clean initial history and omits old private evidence. Fresh post-rename live evidence exists, including Notepad, Chromium, diagnostics, recovered cleanup, compatibility target, signing decision, and complete closeout audit under the product-owned server contract. Compatibility target and signing decision are retained in compact M01 summary evidence; dogfood packaging, release signing, non-blocking cold-start, and user-data preservation remain open. | Start dogfood package hardening when selected. |

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
   post-reboot validation with no residue; see `docs/evidence/m02/summary.md`.
6. **Development inner loop** - add non-elevated dev tooling for a no-install
   REPL, installed-server hot reload with backup/rollback, installed TSF DLL
   reload through a dev-owned test window, and dry-run watch routing. The
   installed-server reload is runtime-proven with schema/user-data backup
   coverage; TSF reload guard evidence proves it refuses to close non-dev
   desktop holders. Historical plan:
   `docs/plans/history/m03-plan-dev-inner-loop.md`.
7. **Candidate window and typing quality implementation** - clean raw dictionary
   CSV candidate comments, expose enough candidates for client-side paging, add
   read-session caret anchoring, owner-window/no-orphan guards, PageUp/PageDown
   paging, punctuation/full-width forwarding through Rime `get_commit`, and
   review follow-up hardening for dev REPL pipe isolation and composing
   punctuation.
   Server-side behavior is runtime-proven through the dev REPL and installed
   server reload. DLL-side app behavior still needs holder-free live proof.
   Historical plan:
   `docs/plans/history/m04-plan-candidate-window-typing-quality.md`.

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

### M02 - Server Lifecycle And Cleanup Hardening

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
`docs/plans/history/m02-plan-server-lifecycle-cleanup-hardening.md`.

### M03 - Development Inner Loop

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
only and do not close dogfood readiness. Evidence summary:
`docs/evidence/m03/summary.md`.

Historical plan:
`docs/plans/history/m03-plan-dev-inner-loop.md`.

### M04 - Candidate Window And Typing Quality

Status: implementation complete, with DLL-side live proof pending a holder-free
desktop session. The implementation cleans raw `jyut6ping3` CSV candidate
comments server-side, returns up to 30 candidates for client-side paging, uses a
read-only TSF edit session to anchor the candidate window near the caret, gives
the native candidate window an owner and foreground guard, adds PageUp/PageDown
paging, and forwards punctuation keys so full-width punctuation can commit via
the existing Rime `get_commit`/`free_commit` API. The review follow-up removes
the old top-left anchor fallback when no valid caret or screen anchor exists,
rejects clipped or zero-size `GetTextExt` anchors, and makes composing
punctuation commit the current candidate before inserting schema-produced
punctuation. It does not widen Yune's default ABI and does not add a librime
fallback.

Runtime evidence proves the server-side paths through the dev REPL and installed
server reload. DLL-side behavior is covered by static contracts, the TSF shell
build, and the candidate-window smoke. Live Notepad/Chromium proof for caret
placement, no-orphan behavior, paging keys, and full-sentence punctuation was
not attempted because non-dev desktop processes held `YuneWindowsTSF.dll`; see
`docs/evidence/m04/summary.md`.

Historical plan:
`docs/plans/history/m04-plan-candidate-window-typing-quality.md`.

## Candidate Next Milestones (for discussion)

M02 and M03 are complete. M04 implementation is complete, but
DLL-side live proof still needs a holder-free desktop session. The remaining
rows are candidate next milestones.

| Candidate | Delivers | Rough size | Key dependency / risk |
| --- | --- | --- | --- |
| **M04 holder-free live verification** | Prove the implemented caret placement, no-orphan behavior, PageUp/PageDown paging, and full-sentence punctuation in Notepad and Chromium after the TSF DLL can be reloaded without non-dev holders. | S | Requires closing holder apps, sign-out, or reboot to produce a holder-free desktop session; do not force-close non-dev apps from tooling. Evidence root: `docs/evidence/m04/`. |
| **Non-blocking cold-start / per-user broker** | Removes the up-to-15s foreground freeze on the first cold keystroke and makes launch work in sandboxed/AppContainer hosts (UWP, WeChat, some Store/Electron). Reduces AV/EDR risk of spawning an unsigned exe from a browser. | M | Adds per-user autostart/broker state that install/uninstall must create and remove; documented M02 fast-follow. |
| **Dogfood package hardening (WIN-11)** | Self-contained install bundle decoupled from the local Yune source build, so a second machine can install without a Rust/Yune toolchain. | M | Production signing stays deferred; needs pre-staged `rime.dll` + schema + binaries + `install-info.json`. |
| **User-data preservation (D-09)** | Preserve or migrate the learned dictionary / personalization across reinstall loops instead of deleting `user-data` on uninstall. | S | Decide backup vs. a `-PurgeUserData` switch; small but touches the uninstall path. |
| **Deferred (Scope Ledger)** | Production signing + release distribution, rich settings UI (WebView2), auto-update, Store packaging, broader compatibility matrix (Win10, Office/Electron/UWP). | varies | Formally deferred until typing evidence + security review; keep behind the above. |

### M04 closeout notes

1. **Comment hygiene (server, fast loop)**: complete. The Windows server
   simplifies `jyut6ping3` CSV comments to clean jyutping or blanks without
   changing the shared web schema.
2. **Candidate window correctness (DLL)**: implemented. `ShowCandidates` uses a
   read-only edit session with `ITfContextView::GetTextExt` for caret anchoring;
   the native popup has an owner window and foreground guard. Live proof remains
   blocked by TSF DLL holders.
3. **Paging (DLL)**: implemented. The server returns a larger candidate list and
   the client pages it with PageUp/PageDown and a page indicator. Live app proof
   remains blocked by TSF DLL holders.
4. **Punctuation / full-width (DLL + schema)**: implemented. The server returns
   auto-committed punctuation through the existing Rime `get_commit` path, and
   TSF forwards punctuation keys when the buffer is empty or composing. In the
   composing case it commits the current candidate first, then inserts
   schema-produced punctuation. Server proof is captured by the dev REPL; live
   app proof remains blocked by TSF DLL holders.

Learning / userdb is intentionally split to a **later** milestone: it is a
protocol change (persistent per-client session, select-index/commit feedback,
userdb persistence, D-05 secure-context suppression with a fresh live privacy
proof), not a flag flip, and should not ride the candidate-window work.

### Cross-cutting

- The synchronous cold-start wait (`kServerLaunchReadyWaitMs = 15000`) will
  color the daily-typing experience even though it is a separate milestone;
  weigh the broker candidate against M04 accordingly.
- Keep live IME install/register/uninstall loops approval-gated and
  reboot-aware regardless of which candidate is chosen.
