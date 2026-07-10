# M11 UI Modernization + Cantonese Localization Evidence

> **Pre-rebaseline provenance (D-21):** This file intentionally retains its
> original M11 label, paths, hashes, counts, test names, and historical verdicts.
> Under the canonical milestone map, the legacy M11/M11C native presentation and
> the settings DPI/resize/scroll portion of M11D belong to **M10**; M11D
> activation, state-transition, and toolbar-visibility reliability belongs to
> **M11**. References below to “M10 blocked” describe the former combined
> skin/candidate plan, now split into the **M12 skin platform** and **M13 candidate
> presentation** milestones. This evidence does not claim installed proof for the
> current rebaseline hash.

Pre-rebaseline status: installed clone/drag proof passed on 2026-07-09 PT
(2026-07-10 UTC). The M11D reliability and settings-layout repairs now pass
non-elevated gates, but their combined installed four-host/usability proof is
pending. M11/M11C remain active and M10 remains blocked.

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

## Approved Installed Clone/Drag Proof

The approved live run deployed source commit
`1f419837b0575dc1ea47dba2785cbb6949b7e73c` to the registered install path.
The installed TSF SHA-256 was
`76254CE522413F9283192FBC0A599767F1BC636002A2B564E900DC0F834937D0`;
the installed default-skin SHA-256 was
`D7771F05AEB1F4D4DFFDA809073E2FAC75D17810F130D4D0D2AF9D6950DF6C6F`.
No delayed-delete operation or reboot was scheduled.

The first post-deploy report of four copies was a mixed-image result: three
visible ownerless HWNDs belonged to an Explorer process still mapping the old
552,960-byte image, while the restarted Codex process had one hidden,
correctly owned toolbar from the new 569,344-byte image. After Explorer was
restarted, every holder mapped the new image, the old swap file was removed,
and no old-image holder remained.

The fresh installed drag proof then recorded:

- 20 Notepad drags (10 grip and 10 settings-segment) plus one Chromium grip
  drag, with 100 intermediate movement events per drag;
- at most one visible toolbar HWND in every topology sample;
- one stable HWND per drag, a valid foreground-root owner throughout, no
  settings-process launch, and no stuck capture;
- one Notepad-to-Chromium transfer hid the previous host in 34 ms, below the
  250 ms limit;
- server-owned final-position persistence after the repeated Notepad sequence;
  and
- the user's fresh visual verdict that the prior copies/afterimages no longer
  appeared.

Acrylic therefore remains enabled; the static-tint and redirected-D2D fallback
sequence was not invoked.

## M11D Installed Reliability Gate Still Open

Clone-free dragging and reliable activation are separate gates. The same live
run found that Chromium needed nine Shift attempts before its existing toolbar
became visible. Explorer needed five attempts on one focus and eleven on a
follow-up. Several Shift taps produced no `ascii_mode` transition. Claude loaded
the current DLL and received foreground composer focus, but no toolbar HWND
appeared after twelve attempts.

M11D implements generation-authoritative focus, event-correlated Shift routing,
boot-ID/revision CAS, deadline-bound worker I/O, and generation-fresh toolbar
eligibility. The settings panel now has DPI-aware initial sizing, safe resizing,
and constrained-work-area scrolling. Non-elevated evidence is recorded in
`docs/evidence/m11d/summary.md`.

The hash-pinned build must still complete the Notepad/Chromium/Explorer/Electron
matrix, installed settings usability, and final-position persistence across host
restart. Until then M11/M11C/M11D stay active and M10 remains blocked.
