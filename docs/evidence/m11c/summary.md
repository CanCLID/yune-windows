# M11 Slice C Toolbar Stabilization Evidence

Status: DirectComposition toolbar plus ownership/drag/backdrop repair is
implemented non-elevated. Approval-gated installed visual proof has not run, so
M11C remains active and M10 remains blocked.

## Diagnosed Topology

A read-only window probe found six real `YuneWindowsLanguageBar_*` HWNDs across
four processes. All were ownerless, and a background process could retain a
visible toolbar. Production also redrew and committed the DComp surface during
drag movement, unlike the movement-only spike.

`tools/dev/capture-language-bar-topology.ps1` now emits privacy-safe JSON with
HWND, PID/TID/process, visibility, rect/DWM frame, owner/root, foreground,
styles, and capture state. It records no arbitrary window titles or typed text.

## Implemented Repair

- Missing contexts recover through `ITfThreadMgr::GetFocus` ->
  `ITfDocumentMgr::GetTop`; the focused service caches only a valid root owner,
  anchor, and DPI. Null/invalid ownership fails closed.
- `ActivateFocusedTextService(this)` uses a per-service apartment dispatcher and
  activation generation to hide/release the prior service asynchronously;
  `DeactivateFocusedTextService(this)` clears focus only for the current caller.
- Process-local arbitration and `YuneWindows.ToolbarSuperseded.v1` provide fast
  same/cross-process cleanup. Receivers validate the claimant against the
  foreground root. A 250 ms watchdog is authoritative.
- `WM_ACTIVATEAPP(FALSE)` hides. `WM_NCDESTROY` clears timer, visibility,
  capture/finalizer, owner/HWND, and graphics state.
- Drag movement performs only `SetWindowPos`. Mid-drag render/resource changes
  queue, and all capture-ending paths share one finalizer that persists once and
  flushes exactly one render when still visible.
- DWM system backdrop use starts at build 22621 and is effective only after an
  actual successful frame extension and backdrop call. Otherwise rendering is
  fully opaque. Same-size acrylic/static transitions apply or clear DWM state
  once.
- The toolbar remains a `WS_EX_NOREDIRECTIONBITMAP` Direct3D/Direct2D/
  DirectComposition surface using
  `D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW`, a fixed
  `SetDpi(96,96)` target, and guarded DWM Desktop Acrylic.
- V1 keeps `glass_mechanism` plus consumed `glass_fallback=static_tint`; inert
  tint/opacity/blur/highlight manifest fields are removed.

The architecture remains a native per-process TSF toolbar. No WebView2 or
`YuneWindowsUiHost.exe` is introduced. Candidate rendering is not M11C scope.

## Current Non-Elevated Verification

Passed on 2026-07-09:

- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m08-modern-toolbar-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m11-ui-modernization-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m11c-dcomp-glass-toolbar-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-window-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-topology-diagnostic-contract.ps1`

The expanded smoke includes 50 drags with at least 100 move events each, real
owner windows, ownerless rejection, same- and cross-process arbitration, stale
claimant rejection, watchdog hiding, DPI/hide/cancel/capture-loss finalization,
owner/`WM_NCDESTROY` cleanup, zero movement renders, one final render, one
position callback, stable HWND count/identity, preserved click semantics, and
no focus steal. Deterministic backdrop coverage includes builds 22000/22621,
DWM and frame-extension failures, same-size transitions, effective opacity, and
no unchanged-present DWM churn.

The broader M11 evidence summary records the passed settings, candidate,
state-protocol, hotkey, response-validation, and dev-REPL gates. None of these
non-elevated checks pre-claims the installed visual result.

## Installed Proof Not Run

The installed host matrix remains approval-gated because non-dev processes hold
the TSF DLL and deployment may require closing holders or signing out/rebooting.
No unrelated process may be force-closed and no cleanup may be scheduled without
fresh approval.

Acceptance requires at most one visible toolbar system-wide, a valid foreground
root owner, stable HWND identity through drag, previous-host hide within 250 ms,
no visual copies/afterimages, no focus steal, and persisted final position across
focus changes and host restart in Notepad, Chromium, Explorer, and one Electron
host.

If any visual condition fails, use the deterministic acrylic -> static DComp ->
normally redirected opaque native D2D fallback. Clone-free behavior has priority
over glass.
