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

M08 keeps the focus-scoped language bar native inside the TSF DLL: a
`WS_EX_NOACTIVATE | WS_EX_LAYERED` Win32 popup rendered with Direct2D/DirectWrite
and presented through `UpdateLayeredWindow`. WebView2, Electron, HTML, and a
session-wide always-on UI host stay out of this milestone. The toolbar skin loads
from `skins/<name>/theme.json` with a compiled-in default fallback, and toolbar
position plus selected skin remain server-owned state via `op=set-toolbar-position`
and `op=set-skin`; the TSF DLL does not read or write `state\ime-state.json`.
The candidate window remains visually unchanged in M08, but the renderer/skin
scaffolding is shared so M09 can adopt it deliberately.

## Last Updated

2026-07-02 - M08 Modern Floating Toolbar landed the native Direct2D/DirectWrite
layered toolbar, default skin manifest/assets, no-activate grip drag, monitor
clamp, and server-owned toolbar position/skin protocol. Evidence is non-elevated
build/contract/server/window-smoke proof under `docs/evidence/m08/`; elevated
install/register and full live IME loops were not run without current-session
approval.

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
