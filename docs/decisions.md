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
bounded IPC failure behavior and structural diagnostics. The current P2-WIN02
implementation uses a bounded synchronous cold-start readiness wait in the TSF
key path (`kServerLaunchReadyWaitMs = 15000`), so the first cold keystroke can
block the foreground app while the product-owned server starts. A session-scoped
broker or otherwise non-blocking/asynchronous cold-start path remains the
fast-follow if restricted hosts, AppContainer coverage, foreground-app latency,
or AV/EDR policy make in-host launch insufficient.

### D-09 - Dogfood uninstall must preserve user data deliberately

The current uninstaller removes the install tree, including `user-data`, unless
`-KeepFiles` is used. That is acceptable for the P2-WIN02 live closeout, but
dogfood package hardening must decide and verify a user-data preservation or
migration policy before repeated reinstall loops can be considered safe for
learned dictionary or personalization data.

### D-10 - Dev inner loop remains non-elevated

The P2-WIN03 development loop may rebuild, stop exact-path user processes, copy
files under the per-user install root, and relaunch a dev-owned disposable test
window. It must not perform TSF registration, registry edits, delayed-delete
cleanup, verifier setup, or canonical install/uninstall loops. Installed-path
reloads are development evidence only and do not close dogfood readiness.
Installed TSF reload must verify dev-owned process identity before closing a
test window and must safe-abort if any non-dev process holds
`YuneWindowsTSF.dll`; full TSF file swap validation can require closing GUI apps
or signing out, and is not part of the normal dev loop.

### D-11 - Candidate typing fixes stay Windows-side unless engine APIs change explicitly

P2-WIN04 keeps candidate-display and input-quality fixes in Yune Windows when
the existing packaged Yune ABI is sufficient. Raw `jyut6ping3` candidate
comments are simplified in the Windows server for display, candidate paging is
client-side over a larger candidate list, and punctuation commits use the
existing default Rime `get_commit`/`free_commit` slots. The default
`rime_get_api()` ABI stays unchanged, and any future engine requirement must be
a named Yune proposal with tests before this repo depends on it. DLL-side
candidate-window behavior still needs live app evidence after a holder-free TSF
DLL reload; static/build proof must not be described as live proof.

## Last Updated

2026-07-01 - P2-WIN04 Candidate Window And Typing Quality implementation
completed with server-side runtime evidence and DLL-side static/build/smoke
evidence. Live app proof for caret placement, no-orphan behavior, paging keys,
and full-sentence punctuation remains blocked until `YuneWindowsTSF.dll` is not
held by non-dev desktop processes.
