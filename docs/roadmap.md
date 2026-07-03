# Roadmap

Yune Windows is the Windows product/frontend track for the Yune engine. It is
intentionally separate from Yune engine-performance work.

## Current Snapshot

| Lane | Current state | Next gate |
| --- | --- | --- |
| Product shell | Renamed public baseline with TSF DLL, shared server, native candidate window, diagnostics tooling, installer scripts, non-elevated contract tests, M02 product-owned server startup, M03 development inner-loop tooling, M04 candidate typing-quality implementation, and M05 IME controls implementation. Latest approved live closeout reached install/register, profile activation, Notepad, Chromium, diagnostics export, uninstall, and post-reboot no-residue cleanup. M04 runtime evidence covers clean candidate comments, 30-candidate server supply, full-width punctuation via `get_commit`, and installed-server reload/readiness. M05 adds server-owned persistent schema/options state in `state\ime-state.json`, `op=` IPC verbs, state reconciliation on every server response, lone-Shift and preserved-key toggles, a focus-scoped native mini language bar, and `YuneWindowsSettings.exe`. M05 review crash blockers are fixed in non-elevated scratch-server coverage: `ascii_mode=true` non-empty input, persisted ascii restart, invalid op/schema/option requests, and settings/schema-cycle fallback no longer kill the shared server. Post-reboot holder-free installed-path proof refreshed the installed server, swapped the TSF DLL, activated the profile, installed the settings executable, and manually verified the M05 typing controls in a dev-owned Notepad window. M06 is complete: server request resilience, async warm-up, capped foreground key-path IPC, shifted punctuation, raw Enter, the focus-gated low-level Shift fallback, a startup dictionary warm-up, and — the key fix — an explicit named-pipe security descriptor (current user + AppContainer) that resolved the no-output failure in sandboxed/lower-integrity hosts reboot-free. The folded-in fixes and core typing behaviors were confirmed live across the Tier-1 hosts (Notepad, Chromium, Telegram, Zed) plus Explorer's search box on 2026-07-02; the finer matrix items (language bar, settings live-apply, cross-app reconciliation, native indicator) are implemented, contract-covered, and spot-checked rather than exhaustively per-host audited. M07 persistent composition (server-held `compose-*` sessions, inline `ITfComposition`, Rime-routed selection, raw Enter, Space candidate commit) is confirmed live: F3 partial-selection compose (東突厥) and F4 inline preedit at the caret. Compact milestone summaries live under `docs/evidence/m01/` through `docs/evidence/m07/`; bulky raw artifacts are regenerated only when a fresh gate needs them. | M06 and M07 complete; next: dogfood package hardening, or non-blocking cold-start / per-user broker. |
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
   start and recorded product-owned server start/readiness evidence. The M06
   compatibility relief later added async warm-up plus capped foreground
   key-path IPC; full broker/autostart launch remains a fast-follow. Cleanup
   initially recorded
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
   server reload. A post-reboot holder-free dev Notepad session during M05
   closeout exercised the installed TSF path for input, paging, and
   punctuation; broader Chromium/no-orphan coverage remains compatibility
   breadth.
   Historical plan:
   `docs/plans/history/m04-plan-candidate-window-typing-quality.md`.
8. **IME toggles, language bar, and settings implementation** - server-owned
   persistent IME state, `op=` IPC verbs, per-response state reconciliation,
   lone-Shift Chinese/English toggle, `Ctrl+Shift+2` schema cycle,
   `Ctrl+Shift+3` full/half toggle, focus-scoped native mini language bar, and
   native `YuneWindowsSettings.exe`. Non-elevated runtime evidence now covers
   the post-review crash blockers for `ascii_mode`, persisted restart, invalid
   op/schema/option requests, and settings/schema-cycle fallback. Source
   contracts cover mid-composition toggle cleanup, lone-Shift false-toggle
   guards, and non-launching focus refresh. Post-reboot holder-free installed
   proof refreshed the server, TSF DLL, profile, and settings executable, then
   manually verified the M05 typing controls in a dev-owned Notepad window.
   Historical plan:
   `docs/plans/history/m05-plan-ime-toggles-language-bar-settings.md`.
9. **Host compatibility pass** - folded-in typing-blocker fixes F1 (shift-aware
   punctuation), F2 (En→Cn freeze: server resilience + async warm-up + capped
   key-path IPC + startup dictionary warm-up), F5 (lone-Shift `WH_KEYBOARD_LL`
   fallback + single-entry toggle guard), F6 (Enter commits raw letters), and the
   fix for the no-output hosts — an explicit named-pipe security descriptor
   scoping the pipe to the current user + AppContainer, deployed reboot-free. The
   folded-in fixes and core typing behaviors were confirmed live across the
   Tier-1 hosts (Notepad, Chromium, Telegram, Zed) plus Explorer's search box on
   2026-07-02; the finer matrix items are implemented and spot-checked.
   Historical plan:
   `docs/plans/history/m06-plan-host-compatibility-pass.md`.
10. **Persistent composition and candidate selection** - persistent per-client
    Rime `compose-*` sessions + inline `ITfComposition`, so multi-syllable
    out-of-lexicon input composes by picking characters one at a time
    (`dungdatkyut` → 東突厥, F3) with the romanization shown inline at the caret
    (F4). No Yune ABI change; `disable_learning` forced. Confirmed live 2026-07-02.
    Historical plan:
    `docs/plans/history/m07-plan-persistent-composition-selection.md`.

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
limitation: M06 now warms the server asynchronously and caps foreground
key-path IPC when the server is not ready. A broker/autostart path remains the
dogfood fast-follow for zero cold-start launch latency and restricted hosts.

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

Status: implementation complete. The implementation cleans raw `jyut6ping3`
CSV candidate comments server-side, returns up to 30 candidates for
client-side paging, uses a
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
build, and the candidate-window smoke. A post-reboot holder-free dev Notepad
session during M05 closeout manually confirmed the installed TSF path for input,
paging, and punctuation. Broader Chromium/no-orphan coverage remains
compatibility breadth; see `docs/evidence/m04/summary.md` and
`docs/evidence/m05/summary.md`.

Historical plan:
`docs/plans/history/m04-plan-candidate-window-typing-quality.md`.

### M05 - IME Toggles, Language Bar, And Settings

Status: complete. The implementation makes the shared server the single writer
for schema/options state in `state\ime-state.json`, adds `op=` IPC verbs,
returns state on every server response, adds lone-Shift Chinese/English toggle,
preserved-key schema/full-shape toggles, ASCII pass-through, a focus-scoped
native mini language bar, and `YuneWindowsSettings.exe`. Review follow-up
hardening prevents the ascii-mode crash loop, keeps invalid requests from
killing the shared server, commits or clears composition before state changes,
guards lone-Shift false toggles, and makes focus refresh a short
existing-server-only query.

Non-elevated scratch-server and dev REPL evidence prove the server protocol and
crash blockers. Post-reboot holder-free installed-path proof refreshed the
installed server, swapped `YuneWindowsTSF.dll`, activated the profile, installed
the settings executable, and manually verified the M05 typing controls in a
dev-owned Notepad window. Broader Chromium, native Windows input-mode
indicator, and multi-host language-bar/settings coverage remain compatibility
follow-up breadth; see `docs/evidence/m05/summary.md`.

Historical plan:
`docs/plans/history/m05-plan-ime-toggles-language-bar-settings.md`.

### M06 - Host Compatibility Pass

Status: complete (2026-07-02). Delivers the folded-in typing-blocker fixes and
verifies the typing controls across real desktop hosts. F1 (shift-aware
punctuation, so Shift+/=- give ？＋——), F2 (En→Cn no longer freezes: server
request resilience + async warm-up + capped key-path IPC + startup dictionary
warm-up), F5 (`WH_KEYBOARD_LL` lone-Shift fallback, single-entry toggle guard),
and F6 (Enter commits the raw letters). The no-output failure in
Chrome/Zed/Telegram/Explorer was root-caused to the shared server creating its
named pipe with the **default security descriptor**, which denied
sandboxed/lower-integrity host tokens; the fix scopes the pipe to the **current
user's SID** and all application packages (`AC`) with a Low mandatory label and
**deploys reboot-free** (excluding other machine users). The folded-in fixes and
core typing behaviors were confirmed live across the Tier-1 hosts (Notepad,
Chromium, Telegram, Zed) plus Explorer's search box on 2026-07-02; the finer
matrix items are implemented and spot-checked. See `docs/evidence/m06/summary.md`.

Historical plan: `docs/plans/history/m06-plan-host-compatibility-pass.md`.

### M07 - Persistent Composition And Candidate Selection

Status: complete (2026-07-02). Replaces the stateless-per-keystroke model with
persistent per-client Rime `compose-*` sessions and an inline `ITfComposition`
key path, so a multi-syllable out-of-lexicon input can be composed by picking
characters one at a time. Confirmed live: F4 (the romanization shows inline at
the caret while composing) and F3 (typing `dungdatkyut` and picking 東 advances
through `datkyut` to compose 東突厥 instead of committing only 東). No Yune ABI
change — `select_candidate_on_current_page` / `candidate_list_from_index` are
already exposed in the linked RimeApi; `disable_learning` stays forced. See
`docs/evidence/m07/summary.md`.

Historical plan:
`docs/plans/history/m07-plan-persistent-composition-selection.md`.

## Candidate Next Milestones (for discussion)

M02 through M07 are complete. **M08's non-elevated implementation is complete
with live visual pending**, and **M09 is the active UI track**; the rows below it
are later candidates.

| Candidate | Delivers | Rough size | Key dependency / risk |
| --- | --- | --- | --- |
| **M08 — Modern floating toolbar (shell complete)** | Replaced the flat GDI language bar with a draggable, position-remembering, Direct2D/DirectWrite toolbar (rounded translucent pill) driven by a JSON skin manifest. Native, a few MB, no WebView2. `UpdateLayeredWindow`+D2D (correct premultiplied alpha), no-activate capture-drag, device-loss + per-monitor DPI, position/skin persisted via server `op=` verbs, deployment wired. | M | **Carries into M09:** the renderer applies only colors/geometry/font — it hardcodes segment labels and does not yet render skin `segment_labels`/SVG icons; WIC is required-but-unused; hover lacks `TrackMouseEvent`; and the drag/persist/no-focus-steal behavior is not yet live-host-verified. Evidence: `docs/evidence/m08/summary.md`; historical plan: `docs/plans/history/m08-plan-modern-toolbar.md`. |
| **M09 — Settings panel + finish toolbar skinning (active)** | Finish M08's skinning (skin-driven icons/labels, lazy WIC, hover fix), add a toolbar ⚙ button, and build a full **settings panel** with yune-web-parity structure: session toggles + schema switch + skin picker wired; engine prefs / userdb import-export / schema import scaffolded present-but-disabled and future-ready. | M | Pivotal decision: WebView2 (reuse yune-web, recommended) vs. native Win32 for the panel. Plan: `docs/plans/active/m09-plan-skins-and-picker.md`. |
| **M10 — Skin breadth + candidate-window skinning (next)** | More built-in skins, user-imported skin folders (strict validation), and applying the shared Direct2D renderer + active skin to the candidate window. | M | Depends on M09's skin-driven rendering. Candidate restyle is render-only, must show no latency regression vs M04. Plan: `docs/plans/active/m10-plan-skin-breadth-candidate-window.md`. |
| **Engine prefs / schema import / userdb (future, scaffolded in M09)** | Actually apply deploy-time engine prefs (completion/correction/sentence/prediction) via a server `customize`+`deploy` path; import new schemas; userdb import/export + on-device learning. | M–L | Engine prefs + schema import need the customize/deploy path; userdb/learning is gated by D-05 privacy. M09 scaffolds the UI so these wire in without a redesign. |
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
   the native popup has an owner window and foreground guard. Broader
   multi-host proof remains follow-up compatibility breadth.
3. **Paging (DLL)**: implemented. The server returns a larger candidate list and
   the client pages it with PageUp/PageDown and a page indicator. Dev Notepad
   live proof was captured during M05 closeout; Chromium breadth remains
   follow-up coverage.
4. **Punctuation / full-width (DLL + schema)**: implemented. The server returns
   auto-committed punctuation through the existing Rime `get_commit` path, and
   TSF forwards punctuation keys when the buffer is empty or composing. In the
   composing case it commits the current candidate first, then inserts
   schema-produced punctuation. Server proof is captured by the dev REPL; dev
   Notepad live proof was captured during M05 closeout, with broader host
   coverage deferred to a compatibility pass.

Learning / userdb is intentionally split to a **later** milestone: it is a
protocol change (persistent per-client session, select-index/commit feedback,
userdb persistence, D-05 secure-context suppression with a fresh live privacy
proof), not a flag flip, and should not ride the candidate-window work.

### Cross-cutting

- M06 removes the hard foreground freeze path for ordinary key handling by
  keeping launch off focus/activation, warming asynchronously, and capping
  existing-server key IPC. Full broker/autostart launch remains separate and
  should still be weighed for sandboxed hosts, zero cold-start latency, and
  AV/EDR policy.
- Keep live IME install/register/uninstall loops approval-gated and
  reboot-aware regardless of which candidate is chosen.
