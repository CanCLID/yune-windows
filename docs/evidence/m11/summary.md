# M11 UI Modernization + Cantonese Localization Evidence

Status: implementation fixed in the non-elevated tree; approval-gated installed
visual proof pending. Keep M11 active. M10 must not begin until the installed
gate proves one foreground-owned toolbar with clone-free dragging.

## Implemented Scope

- Settings and localization:
  - common-controls v6/PerMonitorV2, JhengHei DPI relayout, guarded Windows 11
    DWM polish, centralized Cantonese strings, and settings combo label/value
    separation;
  - localized toolbar glyphs including the explicit `luna_pinyin_octagram` path.
- DirectComposition toolbar:
  - native `WS_EX_NOACTIVATE | WS_EX_NOREDIRECTIONBITMAP` popup;
  - Direct3D/Direct2D/DirectComposition surface with a fixed 96-DPI target and
    `D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW`;
  - device-loss recreation without adopting WebView2 or a UI-host process.
- Ownership and visibility repair:
  - missing contexts resolve through `ITfThreadMgr::GetFocus` and
    `ITfDocumentMgr::GetTop`;
  - the last valid root owner, anchor, and DPI are cached while focused;
    ownerless or invalid updates fail closed;
  - focused-service activation/deactivation is identity-aware; a per-service
    apartment dispatcher and activation generation hide/release the superseded
    service asynchronously outside the global mutex without an A -> B -> A race;
  - process-local single-visible arbitration, the registered
    `YuneWindows.ToolbarSuperseded.v1` cross-process fast path, and a 250 ms
    foreground watchdog converge on the foreground owner;
  - app deactivation hides; `WM_NCDESTROY` clears visibility, timer, capture,
    owner, HWND, and graphics state.
- Movement-only drag:
  - intermediate movement performs `SetWindowPos` only, with no render,
    `BeginDraw`, or composition commit;
  - mid-capture state/DPI/layout/backdrop/device work queues;
  - release, capture loss, cancel, focus loss, and hide share one non-reentrant
    finalizer that persists once and renders once while preserving click behavior.
- Effective backdrop:
  - `DWMWA_SYSTEMBACKDROP_TYPE` is gated at Windows 11 build 22621;
  - rendering opacity follows actual DWM success;
  - failure/older Windows draw an opaque static pill;
  - same-size acrylic/static changes apply/clear DWM state without per-present
    churn;
  - V1 retains `glass_mechanism` and consumed
    `glass_fallback=static_tint`; inert `glass_tint`,
    `glass_tint_opacity`, `blur_amount`, and `highlight_intensity` are removed.

## Diagnostic Evidence

`tools/dev/capture-language-bar-topology.ps1` records privacy-safe toolbar
topology: HWND, PID/TID/process, visibility, rect/DWM frame, owner/root,
foreground relationship, styles, and capture state. It does not collect
arbitrary titles or typed text.

The read-only probe that motivated the repair found six real
`YuneWindowsLanguageBar_*` HWNDs across four processes. All were ownerless, and
a background process could retain a visible toolbar. This means the screenshot
was primarily real-window duplication, not merely a painted afterimage.

## Current Non-Elevated Verification

Passed on 2026-07-09:

- `tools\test-tsf-shell-build.ps1`
- `tools\test-language-bar-smoke.ps1`
- `tools\test-settings-window-smoke.ps1`
- `tools\test-candidate-window-smoke.ps1`
- `tools\test-settings-ime-state-contract.ps1`
- `tools\test-server-ime-state-protocol-contract.ps1`
- `tools\test-tsf-ime-state-hotkey-contract.ps1`
- `tools\test-tsf-server-response-validation-contract.ps1`
- `tools\test-dev-repl-ime-state-contract.ps1`
- `tools\test-m08-modern-toolbar-contract.ps1`
- `tools\test-m09-settings-panel-contract.ps1`
- `tools\test-m11-ui-modernization-contract.ps1`
- `tools\test-m11c-dcomp-glass-toolbar-contract.ps1`
- `tools\test-language-bar-window-contract.ps1`
- `tools\test-language-bar-topology-diagnostic-contract.ps1`
- `tools\test-m06-key-path-fixes-contract.ps1`

The expanded smoke covers real ownership, ownerless-show rejection, same- and
cross-process arbitration, stale supersession rejection, foreground/watchdog
hiding, owner/`WM_NCDESTROY` cleanup, mid-drag state/paint/DPI/hide work,
capture loss/cancel, and 50 repeated drags with at least 100 move events each.
It checks zero movement renders, one final render, stable total HWND count and
identity, one position callback, no segment misclick, and no focus steal. The
backdrop seam covers build 22000, build 22621 success/failure, frame-extension
failure, same-size acrylic/static transitions, effective opacity, and no
per-present DWM churn.

These are non-elevated source/build/protocol/UI-smoke results only. They do not
substitute for the installed visual/topology gate below.

## Approval-Gated Installed Proof Not Run

No installed DLL swap, TSF registration, registry mutation, AppVerifier/PageHeap,
forced holder shutdown, or reboot-prone cleanup was run. Current non-dev
processes hold the TSF DLL.

After fresh approval, exercise Notepad, Chromium, Explorer, and one Electron
host. Accept only when at most one toolbar is visible system-wide; each visible
toolbar has a valid foreground root owner; one drag retains one HWND; the old
host hides within 250 ms; no copies/afterimages appear; focus is never stolen;
and position survives focus changes and host restart.

If acrylic fails with one real HWND, default to static-tint DirectComposition.
If static DirectComposition also trails, use a normally redirected opaque native
D2D toolbar. Do not archive M11/M11C or begin M10 before this gate passes.
