# M05 IME Toggles, Language Bar, and Settings Implementation Plan

> **Status:** completed and archived on 2026-07-01. This plan remains as the
> implementation record; future work should use a new active plan.

**Goal:** give the installed Yune Windows IME the everyday controls a real IME
has, with parity to yune-web: schema switching, 中/英 (`ascii_mode`), full/half
width (`full_shape`), and output character standard — via toggle hotkeys, a small
floating language bar, and a settings config UI.

**Closeout update (2026-07-01):** implementation, non-elevated verification,
post-review crash blockers, and holder-free installed-path dev Notepad proof
are complete for the server-owned state protocol, TSF hotkeys,
focus-scoped native language bar, and native settings entrypoint. The
post-reboot closeout rebuilt and hot-swapped the installed server, swapped the
installed TSF DLL, activated the profile, installed the settings executable,
and manually verified `ngohaig` input, Shift Chinese/English toggle, English
pass-through, toggling back to Cantonese, PageUp/PageDown paging, punctuation,
and the settings entrypoint in a dev-owned Notepad window. Chromium
cross-app breadth, native Windows input-mode indicator observation, and broader
host coverage are follow-up compatibility evidence, not M05 closeout blockers.

**Architecture:** the shared server becomes the single source of truth for
persistent IME state (schema + options), applied to every per-keystroke session
and saved to a per-user state file, mutated by new `op=` pipe verbs. The TSF DLL
gains toggle hotkeys and a clickable language bar (cloned from the candidate
window) that call those verbs; a new standalone settings exe drives the same
verbs only (the state file is private to the server). The latency-critical inline candidate path stays native
(D-04). No Yune ABI change is required — the linked `RimeApi` already exposes
every needed function.

**Tech Stack:** Win32 TSF COM DLL + native GDI (C++20), the shared server + pipe
IPC, the linked Rime-compatible `RimeApi`, and a new native (or WebView2)
settings exe. Iterate via the M03 dev loop (server = instant
`dev-reload-server`; DLL = holder-free `dev-reload-tsf` swap).

---

## Current Facts (grounded)

- **The engine already exposes what we need.** The server links the full upstream
  `RimeApi` via `rime_get_yune_windows_profile_api()->upstream`
  (`src/server/yune_windows_server.cpp:331`). Available and populated
  (`api_table.rs` proves all `Some(...)`): `get_schema_list`/`free_schema_list`,
  `get_current_schema`, `select_schema`, `set_option`, `get_option`, and
  `get_status` (whose `RimeStatus` carries `is_ascii_mode`, `is_full_shape`,
  `is_simplified`, `is_traditional`, `is_ascii_punct`). **No ABI additions.**
- **The server is stateless per keystroke.** `YuneRuntime::Process`
  (`src/server/yune_windows_server.cpp:410-501`) creates a fresh session,
  hard-codes `select_schema(session,"jyut6ping3")` (419) and
  `set_option(session,"ascii_mode",False)` (421), processes keys, then
  `destroy_session` (467). Rime options are session-scoped, so nothing set on a
  session survives — persistent toggle state must live **outside** the session.
- **Schema list** (from `get_schema_list`, driven by `default.custom.yaml`
  patching `default.yaml`): `jyut6ping3` (粵語拼音), `cangjie5` (倉頡五代),
  `luna_pinyin` (朙月拼音). The runtime template for `jyut6ping3` is
  `jyut6ping3_mobile`.
- **Option names** (from the deployed schema `switches:`): `ascii_mode` (中/英,
  bool), `full_shape` (全/半, bool). Output standard is a **per-schema
  mutually-exclusive option group**, not one bool:
  - `jyut6ping3` / `jyut6ping3_mobile` / `cangjie5` / `cangjie3` / `loengfan`:
    `{variants_hk, trad_tw, simplification}` (+ implicit `noop` = OpenCC
    traditional / none).
  - `luna_pinyin`: `{zh_hant_hk, zh_hant_tw, zh_hans}` (+ `zh_hant` = none).
  Setting one member `true` auto-clears its siblings.
- **Parity output-standard values** (from yune-web `outputOptionForStandard`):
  `opencc_traditional` (no variant option set), `hong_kong_traditional`
  (default; `variants_hk` / `zh_hant_hk`), `taiwan_traditional`
  (`trad_tw` / `zh_hant_tw`), `mainland_simplified`
  (`simplification` / `zh_hans`). yune-web also always sets `soft_cursor=true` and
  `traditionalization=false`.
- **Pipe protocol** is a trivial line protocol: `input=<x>\ncommit=0\n.\n` →
  one JSON line (`ParseRequest` `src/server/yune_windows_server.cpp:301-316`;
  client `src/tsf/yune_windows_tsf.cpp:559-560`). It extends cleanly with a
  leading `op=` verb line; old `input=` requests still parse.
- **TSF hooks:** `OnPreservedKey` (`src/tsf/yune_windows_tsf.cpp:1104`) and
  `OnKeyUp` (1095) are no-op stubs — the clean hooks for toggle hotkeys.
  `GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT` is already registered (1461), so the
  DLL can drive the native Windows 中/英 indicator.
- **Toolbar template:** `NativeCandidateWindow`
  (`src/candidate_window/yune_windows_candidate_window.*`) is a
  `WS_POPUP` `WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW|WS_EX_TOPMOST` GDI window with
  monitor-clamped positioning — the exact pattern to clone, made clickable
  (real `WM_NCHITTEST` + `WM_LBUTTONUP` instead of `HTTRANSPARENT`).
- **No settings app exists;** WebView2 was deferred (`webview2-spike.md`), but
  D-04 permits WebView2 specifically for settings/dictionary panels. The profile
  tool (`src/tools/yune_windows_profile_tool.cpp`) is the standalone-exe pattern.

## Non-Goals

- No Yune engine change and no default `rime_get_api()` ABI widening.
- Keep `disable_learning` forced on every session (D-05 privacy) — independent of
  any user toggle.
- Do not put persistent state in the TSF DLL (per-process; inconsistent across
  apps). The server is the authority.
- Deploy-time preferences that require a **redeploy** (`page_size`, completion,
  correction, sentence, learning, prediction threshold, dictionary_exclude,
  Cangjie 3/5, AI rerank) are **deferred to a later slice** — they need a
  `customize`+`deploy` path, not `set_option`.
- UI language and light/dark theme are presentation-only (no engine effect); only
  include them inside the settings UI's own chrome, not as engine state.
- Do not make the inline candidate window WebView2.

## Slice Map (sequence)

1. **Slice A — Server option/schema state + `op=` protocol** (server, fast loop).
2. **Slice B — TSF toggle hotkeys + English pass-through + native 中/英 indicator**
   (DLL, holder-free swap).
3. **Slice C — Floating language bar** (native clickable window; DLL swap).
4. **Slice D — Settings config UI** (new standalone exe; native core first,
   WebView2/yune-web reuse as the richer form).

Do A first — it is foundational, server-side, and iterates instantly. B and C are
DLL swaps (holder-free). D is the largest (new build target).

## Design Details

### Slice A — Server state + protocol

- Add a server-global `YuneState { std::string schema_id; bool ascii_mode;
  bool full_shape; std::string output_standard; }` as a `YuneRuntime` member.
  **The server is the ONLY writer of this state.** Persist it to a dedicated,
  stable path **outside** `user-data`/`schema` — `state\ime-state.json` under the
  install root (`%LOCALAPPDATA%\Yune\WindowsIme\state\`) — so schema/user-data
  refresh and reload flows never touch it. Load in the constructor; rewrite on
  every mutation. Guarantee it survives `-RefreshSchema` and reinstall; decide
  uninstall behavior explicitly (remove only on full uninstall). Default:
  `schema_id=jyut6ping3`, `ascii_mode=false`, `full_shape=false`,
  `output_standard=hong_kong_traditional`.
- In `Process`, replace the hard-coded `select_schema`/`set_option(ascii_mode)`
  (lines 419/421) with applications of `YuneState`: `select_schema(state.schema)`;
  `set_option(ascii_mode)`, `set_option(full_shape)`; `set_option(soft_cursor,
  true)`, `set_option(traditionalization, false)`; and the output-standard group
  write (below). Keep `disable_learning=True` (424) forced.
- **Output-standard mapping** (per-schema; always write all group members, one
  `true`): choose the option-group by schema — jyut6ping3/cangjie/loengfan →
  `{variants_hk, trad_tw, simplification}`; luna_pinyin →
  `{zh_hant_hk, zh_hant_tw, zh_hans}`. Map the 4 standards: `opencc_traditional`
  → all false; `hong_kong_traditional` → HK member true; `taiwan_traditional` →
  TW member true; `mainland_simplified` → simplified member true.
- **New `op=` verbs** in `Request`/`ParseRequest` (26-29, 301-316):
  - `op=set-option\nname=<n>\nvalue=<0|1>\n.` — mutate + persist + return state.
    For `name=output_standard`, `value` is the standard id, not a bool.
  - `op=select-schema\nschema=<id>\n.` — set + persist + return state.
  - `op=get-state\n.` — return `{schema_id, ascii_mode, full_shape,
    output_standard}` (no session created).
  - `op=list-schemas\n.` — `get_schema_list`/`free_schema_list` → array of
    `{schema_id, name}` (no session created).
  Reuse `JsonEscape` and the one-line-JSON convention. **Include the current
  state block (`schema_id, ascii_mode, full_shape, output_standard`) in EVERY
  response — including the `input=` keystroke response** — so any client caching
  it is refreshed on every request (the reconciliation basis for Slice B).
- Add `get_schema_list`/`get_current_schema` to the server's `Require()` presence
  checks (352-364).
- **Verify:** extend `dev-repl` (or add a small dev command) to send `op=`
  requests and print state; confirm toggling `ascii_mode`/`full_shape`/output
  standard/schema changes the candidates for a fixed input — all on the fast
  `dev-reload-server` loop, no DLL/install change.

### Slice B — TSF hotkeys + English pass-through + native indicator

- **Hotkeys.** The primary 中/英 toggle is a **lone Shift press** (the Microsoft
  Pinyin / Sogou convention users expect). This is NOT a `PreserveKey` chord — it
  needs a key-up state machine in the TSF key sink:
  - Track `bool shift_down_` and `bool shift_consumed_` on the `TextService`. In
    `OnKeyDown` for `VK_SHIFT`/`VK_LSHIFT`/`VK_RSHIFT`: set `shift_down_=true`,
    `shift_consumed_=false` (do NOT eat it). In `OnKeyDown` for any **other** key
    while `shift_down_`: set `shift_consumed_=true` (Shift acted as a modifier —
    e.g. Shift+letter for a capital — so it is not "lone"). In `OnKeyUp` for
    `VK_SHIFT` with `shift_down_ && !shift_consumed_`: it was a lone Shift →
    toggle `ascii_mode` via `op=set-option`; then clear `shift_down_`.
  - Never eat the Shift key itself (return not-eaten) so it still works as a
    modifier in the host app.
  - **Delivery risk to resolve in implementation:** confirm the TSF key sink
    reliably receives `VK_SHIFT` key-**up** across host apps; if some app does not
    deliver it, fall back to a low-level keyboard hook (`WH_KEYBOARD_LL`) for the
    lone-Shift detection (the approach Weasel and other IMEs use). Note this may
    interact with any OS/other-IME "Shift to switch language" setting.
  - **Secondary toggles stay chords** via `PreserveKey` + `OnPreservedKey` (1104):
    `Ctrl+Shift+3` toggles `full_shape`, plus a schema-cycle chord.
  On any toggle, send `op=set-option`/`op=select-schema` through a generalized
  `QueryServer` (471).
- **State reconciliation (no cross-app drift):** the DLL treats the server as the
  source of truth and keeps only a short-lived cache, refreshed two ways — from
  the **state block on every server response** (Slice A), and by sending
  `op=get-state` on `OnSetFocus(focused=TRUE)`/`ActivateEx` so the mode is fresh
  when you switch into an app before typing. This keeps 中/英 and full/half
  consistent across apps and the settings UI even when another client changed
  server state through the server.
- When `ascii_mode` is on (per the reconciled state), bypass the letter-buffering
  path (946-969) so English/ASCII passes straight through.
- Drive the Windows 中/英 tray indicator via the registered input-mode
  compartment (1461).
- **Verify live:** holder-free `dev-reload-tsf` swap; confirm a **lone Shift**
  press toggles 中/英 (while Shift+letter still types a capital with no toggle),
  `Ctrl+Shift+3` toggles 全/半, English passes through in ascii mode, and the
  native indicator reflects state.

### Slice C — Floating language bar

- Clone `NativeCandidateWindow` into a `LanguageBarWindow`: same
  `WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW|WS_EX_TOPMOST` popup, but **clickable**
  (return real `WM_NCHITTEST`, handle `WM_LBUTTONUP` per segment). Segments: 中/英,
  全/半, output standard (cycle the 4), schema (cycle/menu). Reflect state from
  `op=get-state`; a click sends the matching `op=` verb and re-renders.
- Owned by `TextService` like `candidate_window_` (1301); position at a fixed
  screen corner (simplest) or near the caret via the existing
  `CandidateAnchorEditSession` plumbing (708-808). Keep `WS_EX_NOACTIVATE` so
  clicks don't steal focus from the typing app.
- **Scope for this milestone: a focus-scoped mini bar**, not a persistent
  always-on-screen bar. It is a per-`TextService` window shown while the current
  app has a Yune-active field (shown on focus/composition, hidden on
  `OnSetFocus(FALSE)`/`Deactivate`), mirroring the candidate window's lifecycle so
  bars never duplicate or go stale across apps. A single always-on tray/bar
  process (one window for the whole session) is a **later** refinement — it needs
  a server→client push channel the current one-shot request/response pipe lacks.
- **Verify live:** DLL swap; click each segment, confirm state changes across
  apps (because the server is the authority).

### Slice D — Settings config UI

- Add a 5th build target: a standalone `YuneWindowsSettings.exe` modeled on
  `yune_windows_profile_tool.cpp` (wmain + CoInitialize). **It does NOT touch the
  state file — the server is the sole writer.** It reads current state via
  `op=get-state` and `op=list-schemas`, and applies changes via
  `op=set-option`/`op=select-schema` over `\\.\pipe\yune-windows-ime`, so the
  server persists them and every client (DLL, language bar) stays consistent.
- **Core settings (this slice):** schema, 中/英, 全/半, output standard — parity
  with the toolbar, in a proper window. Start **native Win32/GDI** (matches the
  native-first stance, no runtime dependency) OR a minimal **WebView2** page.
- **Richer settings (deferred stretch / Slice E):** the deploy-time preferences
  (`page_size`, completion, correction, sentence, learning, prediction, Cangjie
  3/5, AI). These require a `customize` (write `<schema>.custom.yaml`) +
  redeploy path in the server — a bigger lift; scope separately. WebView2 reuse
  of yune-web's Preferences UI is the aspirational form once the deploy path
  exists.

## Tasks

### Task 0: Prerequisites (before DLL-side M05 work)
- [x] Record holder-free installed-path proof under `docs\evidence\m05\`
  after the post-reboot `dev-reload-tsf` swap. The same dev Notepad session
  exercised the M04/M05 typing surface for candidate input, paging, and
  punctuation. Broader M04 Chromium/no-orphan compatibility evidence remains
  follow-up breadth, not a blocker for this M05 state-controls closeout.
- [x] Fix `tools\dev\dev-reload-server.ps1 -RefreshSchema` ordering: it currently
  runs `prepare-yune-product-data` (schema/user-data refresh) BEFORE stopping the
  running server (`dev-reload-server.ps1:67-72`, ahead of the stop at ~85), so the
  server holds those files mapped and the refresh can fail. Move the refresh to
  AFTER the server is stopped (before restart).

### Task 1: Slice A — server state + protocol
- [x] Add `YuneState` + per-user state file (load in ctor, persist on mutate).
- [x] Apply state in `Process`; implement the per-schema output-standard mapping;
  keep `disable_learning` forced; add `soft_cursor`/`traditionalization`
  constants.
- [x] Add `op=set-option`/`select-schema`/`get-state`/`list-schemas`; add
  `get_schema_list`/`get_current_schema` to `Require()`.
- [x] Extend `dev-repl` to exercise `op=` verbs; add a server contract test.
- [x] Harden protocol behavior so ascii pass-through and invalid requests return
  responses without killing the shared server.
- [x] Verify via scratch server/dev REPL/build checks. Commit directly to `main`.

### Task 2: Slice B — hotkeys + pass-through + indicator
- [x] Lone-Shift key-up state machine for the 中/英 toggle; `PreserveKey` +
  `OnPreservedKey` chord for `full_shape` + schema-cycle; generalize
  `QueryServer` for `op=` requests; ascii-mode English pass-through; input-mode
  compartment. The `WH_KEYBOARD_LL` fallback is explicitly deferred until
  holder-free live proof shows it is needed.
- [x] Guard lone-Shift against preserved-key chords, modifier chords,
  autorepeat, mouse-selection false toggles, focus loss, and deactivation.
- [x] Commit or clear live composition before mode/schema/output-standard
  changes.
- [x] Avoid launch-and-wait focus sync by making activation/focus refresh a
  short existing-server-only query.
- [x] Contract tests for the new key path; build.
- [x] Live-verify via holder-free `dev-reload-tsf`. Commit directly to `main`.

### Task 3: Slice C — language bar
- [x] `LanguageBarWindow` (clickable clone of the candidate window); wire clicks
  to `op=` verbs; reflect `get-state`.
- [x] Holder-free live-verify the installed language-bar/settings path in a
  dev-owned Notepad session. Broader cross-app language-bar click coverage is
  deferred to compatibility breadth. Commit directly to `main`.

### Task 4: Slice D — settings exe (core)
- [x] New `YuneWindowsSettings.exe` build target; native core settings (schema +
  3 toggles) over the state file + `op=` verbs.
- [x] Live-verify the installed settings entrypoint after the post-reboot
  server/TSF reload. Commit directly to `main`.

### Task 5: Docs
- [x] Update `README.md`, `docs/roadmap.md`, `docs/requirements.md`,
  `docs/decisions.md` (record: server is the state authority; toolbar native;
  WebView2 reserved for the richer settings; deploy-time prefs deferred).

## Reviewer Questions (for GPT / Codex)

- Settings UI: native Win32 core first (no dependency), or go straight to
  WebView2 reusing yune-web's components (heavier: WebView2 runtime + packaging)?
- Are the deploy-time preferences (`page_size`, learning, prediction, Cangjie
  3/5, AI) in scope, given they need a `customize`+`deploy` redeploy path the
  server does not have yet?
- Cold-start: a language bar / settings app querying the server at startup hits
  the up-to-15s cold-start wait — do we need the deferred per-user broker first?
- Lone-Shift delivery: does the TSF key sink reliably receive `VK_SHIFT` key-up
  across host apps (so the state machine works), or must we install a
  `WH_KEYBOARD_LL` hook fallback? And does it collide with any OS/other-IME
  "Shift to switch input language" setting?

Resolved in this revision (from the plan reviews): the server is the **single
writer** of state (clients use `op=` verbs only); state lives in a dedicated
`state\ime-state.json` (outside `user-data`/`schema`); cross-app drift is
prevented by the state block on **every** response plus a short
existing-server-only `op=get-state` on focus; the language bar is a
**focus-scoped** mini bar this milestone; the 中/英 toggle is a **lone-Shift**
key-up state machine with guard rails for preserved chords, modifiers,
autorepeat, mouse-selection false toggles, focus loss, and deactivation;
`full_shape`/schema stay on `PreserveKey` chords. The `WH_KEYBOARD_LL` fallback
is deferred unless holder-free live proof shows TSF key-up delivery is
unreliable. Task 0 fixed the `-RefreshSchema` ordering. The post-reboot
holder-free dev Notepad session captured enough installed-path proof for this
M05 closeout; broader M04/M05 Chromium and multi-host compatibility proof
remains follow-up breadth.

## Completion Gates

- Server holds persistent schema + `ascii_mode`/`full_shape`/output-standard
  state, applied to every keystroke and saved across restarts; `op=` verbs work
  and are dev-loop verified.
- A lone Shift press toggles 中/英 (with English pass-through), Shift+letter still
  types a capital, and `Ctrl+Shift+3` toggles full/half; the native Windows
  indicator reflects 中/英.
- The floating language bar shows current mode and its segments toggle state,
  consistently across apps.
- The settings exe changes schema + the three toggles live, via the shared state
  file and pipe verbs.
- Output character standard produces the correct variant per schema (HK/TW/simp/
  OpenCC), matching yune-web's mapping.
- No Yune ABI widening; `disable_learning` stays forced; inline candidate window
  stays native. Live DLL-side verification captured under `docs/evidence/m05/`.
