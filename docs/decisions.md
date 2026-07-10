# Decisions

This file records standing product decisions for Yune Windows.

## Standing Decisions

### D-01 - Yune-only runtime

Yune Windows uses Yune as the only runtime engine. A librime fallback would keep
old architecture debt alive and make product bugs harder to classify.

### D-02 - Fresh public repo with reference extraction

The product starts in this fresh public repo. The legacy Weasel-derived
implementation is reference material, not the product architecture. Reuse small
proven TSF, IPC, server, installer, smoke, and candidate-positioning pieces only
after they are audited.

### D-03 - Shared server/IPC by default

The default process model is a shared server/IPC spine because it matches
Yune's process-global runtime/session/userdb model. In-process TSF-per-app
loading must win an explicit spike before it replaces the default.

### D-04 - Native first candidate window

The inline candidate window starts native. WebView2 can be evaluated for
settings and dictionary-panel UI, but not for the latency-critical inline
candidate window until focus, positioning, accessibility, and latency are
proven.

### D-05 - Privacy gates from the first host contract

The host contract reserves sensitive-context behavior from the start. Password
or secure TSF contexts suppress learning, AI staging, and typed-content logs.

### D-06 - Engine and product evidence stay separate

Windows product evidence does not close Yune engine-performance milestones.
Yune engine evidence does not prove Windows product readiness.

### D-07 - No blocker closeout for live readiness

Dogfood readiness is a product-readiness gate, not a diagnosis-only gate. A
measured TSF, installer, candidate-window, or cleanup blocker is recorded as
evidence, then implementation continues or the gate stays open.

### D-08 - Shared server lifecycle must become product-owned

The shared server model remains the default. The first product-owned lifecycle
path is on-demand `YuneWindowsServer.exe` launch from the installed TSF DLL, with
bounded IPC failure behavior and structural diagnostics. M06 adds the bounded
subset that belongs in the TSF DLL: activation/focus state refresh never
launches the server synchronously, the DLL requests asynchronous server warm-up,
and foreground key-path IPC uses a capped existing-server query so a not-ready
server does not hard-freeze the foreground app. A session-scoped broker or
autostart path remains the fast-follow if restricted hosts, AppContainer
coverage, zero cold-start launch latency, or AV/EDR policy make in-host launch
insufficient.

### D-09 - Dogfood uninstall must preserve user data deliberately

The current uninstaller removes the install tree, including `user-data`, unless
`-KeepFiles` is used. That is acceptable for the M02 live closeout, but
dogfood package hardening must decide and verify a user-data preservation or
migration policy before repeated reinstall loops can be considered safe for
learned dictionary or personalization data.

### D-10 - Dev inner loop remains non-elevated

The M03 development loop may rebuild, stop exact-path user processes, copy
files under the per-user install root, and relaunch a dev-owned disposable test
window. It must not perform TSF registration, registry edits, delayed-delete
cleanup, verifier setup, or canonical install/uninstall loops. Installed-path
reloads are development evidence only and do not close dogfood readiness.
Installed TSF reload must verify dev-owned process identity before closing a
test window and must safe-abort if any non-dev process holds
`YuneWindowsTSF.dll`; full TSF file swap validation can require closing GUI apps
or signing out, and is not part of the normal dev loop.

### D-11 - Candidate typing fixes stay Windows-side unless engine APIs change explicitly

M04 keeps candidate-display and input-quality fixes in Yune Windows when
the existing packaged Yune ABI is sufficient. Raw `jyut6ping3` candidate
comments are simplified in the Windows server for display, candidate paging is
client-side over a larger candidate list, and punctuation commits use the
existing default Rime `get_commit`/`free_commit` slots. The default
`rime_get_api()` ABI stays unchanged, and any future engine requirement must be
a named Yune proposal with tests before this repo depends on it. DLL-side
candidate-window behavior must keep live app evidence separate from
static/build proof. Review follow-up hardening may improve the TSF code path
and dev harness without changing that evidence boundary.

### D-12 - IME state is server-owned

M05 makes the shared server the only writer for live IME state: schema,
`ascii_mode`, `full_shape`, and output standard. Clients, including the TSF DLL,
the focus-scoped native language bar, dev tooling, and `YuneWindowsSettings.exe`,
must use `op=` pipe verbs instead of reading or writing the private
`state\ime-state.json` file directly. The TSF DLL treats state as a short-lived
cache, refreshes it from server responses, and uses a short existing-server-only
state query on focus/activation so host input threads do not launch-and-wait for
the shared server during focus changes. The first key cold-start path remains a
separate product-owned server lifecycle follow-up. WebView2 remains reserved for
a richer future settings/dictionary panel, not the latency-critical inline
candidate surface.

### D-13 - M06 compatibility relief stays Windows-side

M06 fixes the known host compatibility typing blockers inside Yune Windows
without changing Yune engine internals or widening the default `rime_get_api()`
ABI. The TSF key path forwards a conservative US-layout shifted punctuation map
to Rime instead of calling `ToUnicodeEx` from `OnTestKeyDown`, keeps `-`/`=`
paging unshifted-only, treats Enter as raw-buffer commit while Space remains
candidate commit, and installs a process-wide, focus-gated `WH_KEYBOARD_LL`
lone-Shift fallback whose callback only posts work back to the focused text
service. Non-US keyboard-layout derivation, full broker/autostart cold-start
removal, and sandboxed/AppContainer host support remain later milestones.

### D-14 - Persistent composition is server-session backed

M07 makes the shared server own per-client Rime composition sessions addressed by
one-shot pipe request tokens. The TSF DLL renders Rime preedit through inline
`ITfComposition`, routes number-key selection through `compose-select`, treats
Enter as `compose-commit-raw`, and treats Space as `compose-commit`. The old
TSF-only fake-selection path is removed. Learning/userdb stays disabled and
deferred; persistent sessions are the prerequisite architecture, not a decision
to enable learning.

### D-15 - Modern toolbar stays native and server-owned

M08 keeps the focus-scoped language bar native inside the TSF DLL. M08 first
landed a `WS_EX_NOACTIVATE | WS_EX_LAYERED` Direct2D/DirectWrite popup presented
through `UpdateLayeredWindow`; M11 Slice C supersedes that presentation with a
`WS_EX_NOREDIRECTIONBITMAP` DirectComposition + Direct2D surface over DWM Desktop
Acrylic when DWM accepts it, otherwise an opaque static pill. WebView2, Electron,
HTML, and a session-wide always-on UI host stay out of the toolbar path. The
toolbar skin loads from `skins/<name>/theme.json` with a
compiled-in default fallback, and toolbar position plus selected skin remain
server-owned state via `op=set-toolbar-position` and `op=set-skin`; the TSF DLL
does not read or write `state\ime-state.json`. The candidate window remains
visually unchanged for now, but the renderer/skin scaffolding is shared so M10 can
adopt it deliberately. Manifest segment glyph labels are rendered; SVG/image
asset rendering is deferred until a renderer path actually consumes those assets.

### D-16 - Settings panel is native Win32 (no WebView2)

The M09 settings panel is a native Win32 window (extending
`YuneWindowsSettings.exe`), not WebView2 and not a visual/behavioral replica of
yune-web. The user does not need web parity, so the panel covers the same
*functional* areas (session toggles, skin picker, and scaffolded schema-import /
userdb import-export / deploy-time engine prefs) with only the controls the IME
needs, avoiding a WebView2 runtime dependency and staying consistent with the
native Direct2D toolbar. The toolbar settings segment launches or focuses this
native executable; supported changes still flow through server `op=` verbs, and
the settings executable must not read or write `state\ime-state.json` directly.
This narrows D-04/D-12's "WebView2 may be evaluated for settings" to "settings
panel is native"; WebView2 is not adopted for any Yune Windows surface.

### D-17 - M11 localization and glass proof boundary

M11 localizes the native settings panel and toolbar to Cantonese only for now,
with user-visible strings centralized in a native `ui_strings` source so a
future language toggle can be added without changing server protocol values.
Settings combo boxes must keep display labels separate from the server IDs sent
through `op=` payloads. The glass toolbar path uses native DirectComposition +
Direct2D. It requests the supported DWM Desktop Acrylic system backdrop only on
build 22621+, records successful frame extension plus backdrop application as
the effective state, and otherwise draws an opaque static pill; the earlier
host-backdrop and accent-acrylic routes are not used. Non-elevated implementation
evidence may prove source, build, and smoke contracts while installed topology
and visual proof remain approval-gated.

### D-18 - Toolbar visibility is foreground-owned and fail-closed

The native per-process TSF architecture remains. A toolbar may be visible only
with a valid root owner that matches the foreground root. Missing TSF contexts
resolve through the focused document and reuse only a last-known valid
owner/anchor/DPI cache only for contextless replies; an explicit context that
cannot establish its own owner fails closed. Focus-service handoff is
identity-aware and asynchronous through a per-service apartment dispatcher with
an activation generation; process-local arbitration plus the registered
supersession message is the fast path, and a 250 ms foreground watchdog is
authoritative.

During capture, pointer movement changes only the HWND position. State, DPI,
backdrop, and graphics changes queue until one non-reentrant finalizer persists
the position at most once and renders at most once. Clone-free correctness
outranks acrylic: an installed failure demotes the toolbar from acrylic to static
DirectComposition, then to a normally redirected opaque native D2D HWND. M10 is
blocked until this installed gate passes and retains ownership of candidate
rendering.

### D-19 - M10 V1 skins are manifest-only and candidate proof is independent

After the M11 installed gate passes, M10 introduces shared `SkinDefinition` and
`SkinCatalog` code for server, TSF, and settings. V1 accepts bounded JSON
manifests only: no PNG, SVG, executable content, or asset paths. User skins live
under `%LOCALAPPDATA%\Yune\WindowsIme\skins-user`, are deleted by normal
uninstall/reinstall, and survive non-elevated dev swaps. Catalog IPC uses
`list-skins`, `reload-skins`, `set-skin`, and a stable `skin_revision`; invalid or
deleted active skins fall back atomically to `default`.

Candidate rendering remains an M10 gate, not evidence inherited from M11. It
uses an opaque/static-tint DComp surface, preserves M04 ownership/typing
semantics, and recreates a normally redirected GDI window if composition fails
before first show. Cold and warm candidate performance must be compared with a
recorded GDI baseline before M10 can close.

### D-20 - Clone topology and activation reliability are separate gates

The installed M11C clone/drag sub-gate may pass without proving that Windows
profile activation, the Yune lone-Shift toggle, server-state acknowledgement,
and toolbar show eligibility are deterministic. M11D owns those activation and
visibility layers and must preserve every M11C ownership/drag invariant.

M11/M11C/M11D archive together only after Notepad, Chromium, Explorer, and one
Electron host show the toolbar without sacrificial toggles; each lone Shift
causes exactly one acknowledged state transition; previous-host hiding remains
within 250 ms; and the clone, focus, and position-persistence gates pass. M10
remains blocked and continues to own skin breadth and candidate rendering.

## Last Updated

2026-07-09 PT / 2026-07-10 UTC - Approved installed M11 proof deployed commit
`1f419837b0575dc1ea47dba2785cbb6949b7e73c` with TSF SHA-256
`76254CE522413F9283192FBC0A599767F1BC636002A2B564E900DC0F834937D0`.
Fresh Notepad/Chromium dragging retained one valid foreground-owned HWND and the
user reported no copies or afterimages. Activation/visibility failed separately:
Chromium needed nine attempts, Explorer needed five and then eleven, several
Shift taps produced no state transition, and Claude produced no toolbar after
twelve attempts. D-20 creates M11D for that stop-the-line work before M10.

2026-07-09 - M11 toolbar stabilization corrected the diagnosed real-window
topology: owner recovery/cache now fails closed, focused-service replacement is
identity-aware and asynchronously generation-guarded, visibility arbitrates
within/across processes, and a 250 ms watchdog enforces foreground ownership.
Drag movement no longer renders or commits; one finalizer persists and flushes
once. DWM backdrop use is gated at build 22621 and requires successful frame plus
backdrop setup, otherwise using an opaque static fallback. At that implementation
landing, installed visual proof was still approval-gated; the later result and
remaining M11D blocker are recorded in D-20.

2026-07-07 - M11 Slice C replaces the language-bar toolbar's layered/ULW
presentation with `WS_EX_NOREDIRECTIONBITMAP`, DirectComposition, Direct2D, and
DWM Desktop Acrylic. The DComp surface render path uses a fixed 96-DPI D2D target
and `D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW`; device loss
recreates the graphics stack. Evidence was initially non-elevated under
`docs/evidence/m11c/`; the later installed clone result is recorded in D-20.

2026-07-03 - M11 UI Modernization + Cantonese Localization added the embedded
common-controls v6/PerMonitorV2 settings manifest, Microsoft JhengHei UI font
and DPI relayout, build-gated DWM settings polish, centralized Cantonese UI
strings, settings combo label/value split, toolbar glyph fixes including
`luna_pinyin_octagram`, default-skin glass fields, and the initial `GlassSurface`
shell. Evidence was initially non-elevated under `docs/evidence/m11/`; the later
installed clone result is recorded in D-20.

2026-07-03 - M08/M09 live-test follow-up: reduced the toolbar "clone trail" on
drag (made `SetWindowPos` the single position authority with a NULL
`UpdateLayeredWindow` `pptDst`, plus a drag-active guard in
`LanguageBarWindow::Update`) and fixed the stray terminal on the gear button (the
swap tooling now redeploys the GUI-subsystem
`YuneWindowsSettings.exe`, which had been left as a stale console build). No
decision change; consistent with D-15 (native server-owned toolbar) and D-16
(native Win32 settings panel). Regression guards added to the M08 contract.

2026-07-03 - M09 Settings Panel + Skin Picker landed a persistent toolbar
settings segment, native Win32 settings panel sections, server-routed session /
schema / skin changes, a shared `D2DSurface` toolbar preview, and disabled
future engine/dictionary/schema controls. The candidate window remains visually
unchanged for M10. Evidence is non-elevated build/contract/toolbar-smoke/
settings-self-test proof under `docs/evidence/m09/`; live-machine steps were
not run without current-session approval.

2026-07-02 - M08 Modern Floating Toolbar landed the native Direct2D/DirectWrite
layered toolbar, default skin manifest glyph labels, no-activate grip drag,
monitor clamp, and server-owned toolbar position/skin protocol. SVG/image asset
rendering is deferred, and no inert skin image assets ship in M08. Evidence is
non-elevated build/contract/server/window-smoke proof under `docs/evidence/m08/`;
elevated install/register, full live IME loops, and live dogfood visual proof
were not run without current-session approval.

2026-07-02 - M06 and M07 completed. The no-output failure in sandboxed hosts was
root-caused to the shared server's default named-pipe security descriptor and
fixed reboot-free by scoping the pipe to the current user's SID plus AppContainer
(`AC`); a startup dictionary warm-up removed the first-keystroke latency and a
single-entry lone-Shift guard fixed missed toggles. F1/F2/F5/F6 and the M07 inline
composition (F3 partial-selection compose to 東突厥, F4 inline preedit) were
confirmed live across the Tier-1 hosts. Both plans are archived under
`docs/plans/history/`; evidence under `docs/evidence/m06/` and `docs/evidence/m07/`.

2026-07-02 - M07 persistent composition landed the server-owned `compose-*`
protocol and TSF inline `ITfComposition` key path, preserving M06 Shift,
punctuation, raw Enter, and hotkey behavior.

2026-07-02 - M06 compatibility relief landed server resilience, async warm-up
plus capped foreground key-path waits, shifted punctuation forwarding,
unshifted-only `-`/`=` paging, raw Enter commit, and the focus-gated low-level
Shift fallback. Local build/source/runtime contracts and
`docs/evidence/m06/summary.md` are green; M06 remains active until the
holder-free live host matrix is filled.

2026-07-01 - M05 IME Toggles, Language Bar, and Settings implementation added
server-owned state, `op=` verbs, TSF hotkeys, focus-scoped native mini language
bar, and native settings entrypoint with non-elevated build/contract/runtime
evidence. Review crash blockers for ascii pass-through, persisted ascii restart,
invalid requests, settings/schema-cycle fallback, mid-composition toggles,
lone-Shift guards, and focus-time sync are fixed or explicitly deferred in
`docs/evidence/m05/summary.md`. Post-reboot holder-free installed-path proof
refreshed the installed server, swapped the TSF DLL, activated the profile,
installed the settings executable, and manually verified the M05 typing controls
in a dev-owned Notepad window. Chromium/native-indicator and broader multi-host
coverage remain follow-up compatibility evidence.
