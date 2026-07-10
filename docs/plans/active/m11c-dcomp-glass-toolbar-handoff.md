# M11 Slice C — Toolbar Clone Repair Handoff

> **Status:** installed clone/drag proof passed on 2026-07-09 PT
> (2026-07-10 UTC). Keep M11/M11C active under M11D until activation, lone-Shift
> transition, and toolbar visibility are deterministic across all four hosts.
> Do not begin M10 before M11D passes.

## What the probe established

The reported copies were primarily multiple real toolbar windows, not only
painted afterimages. The read-only topology probe found six
`YuneWindowsLanguageBar_*` HWNDs across four processes. They were ownerless, and
a background process could retain a visible toolbar. Production also presented
the DirectComposition surface during every drag move, unlike the clone-free
spike, which moved the HWND only.

The repair therefore addresses both window topology and presentation churn. It
keeps the existing per-process TSF model; it does not introduce
`YuneWindowsUiHost.exe`.

## Implemented ownership contract

- `TextService::UpdateLanguageBar` resolves a missing context through
  `ITfThreadMgr::GetFocus` and `ITfDocumentMgr::GetTop`.
- While focused, the service caches the last valid root owner, anchor, and DPI.
  Contextless server replies may reuse that cache, but the toolbar never shows or
  reparents with a null or invalid owner.
- Foreground matching fails closed and compares root windows.
- `ActivateFocusedTextService(this)` replaces the focused service, then uses a
  per-service apartment dispatcher plus activation generation to hide/release
  the superseded service asynchronously outside the focus mutex without a stale
  A -> B -> A hide. `DeactivateFocusedTextService(this)` clears the global only
  when the caller is still current.
- Process-local arbitration permits only one visible toolbar HWND.
- The registered `YuneWindows.ToolbarSuperseded.v1` message is the cross-process
  fast path. A receiver revalidates the claimant against the foreground root
  before hiding, preventing stale-message races.
- A 250 ms foreground watchdog is the authoritative fallback for missed TSF focus
  events or blocked cross-integrity messages.
- `WM_ACTIVATEAPP(FALSE)` hides the toolbar. `WM_NCDESTROY` clears the HWND,
  owner, capture/finalizer state, visibility registration, timer, and graphics
  resources.

## Implemented drag contract

After the pointer crosses the drag threshold, `WM_MOUSEMOVE` performs
`SetWindowPos` only. It does not call `Render`, `BeginDraw`, or `Commit`.

State, skin, hover, DPI, surface-reset, and backdrop requests received during
capture are queued. Release, unexpected `WM_CAPTURECHANGED`, `WM_CANCELMODE`,
focus loss, and `Hide()` converge on one non-reentrant finalizer:

1. Snapshot the final position.
2. Clear capture and drag state before `ReleaseCapture`.
3. Persist the position once when movement occurred.
4. If still visible, apply queued resource/backdrop work and render once.

Movement below the threshold keeps the existing segment-click semantics. The
smoke-only render counter proves zero presents during movement and exactly one
final flush.

## Backdrop and schema contract

- `DWMWA_SYSTEMBACKDROP_TYPE` is attempted only on Windows 11 build 22621 or
  later.
- The renderer caches whether full-frame extension and the DWM backdrop call
  both succeeded. Draw opacity follows this effective state, not the requested
  skin value.
- Failure and older Windows use a fully opaque static pill.
- Same-sized acrylic-to-static transitions apply `DWMSBT_NONE` and reset the
  frame extension; static-to-acrylic transitions reapply the backdrop and record
  success. Unchanged presents do not churn DWM attributes.
- V1 keeps `glass_mechanism` and the consumed
  `glass_fallback=static_tint`. The inert `glass_tint`,
  `glass_tint_opacity`, `blur_amount`, and `highlight_intensity` fields are
  removed from the manifest, parser, contracts, and default skin.

## Diagnostics and non-elevated coverage

`tools/dev/capture-language-bar-topology.ps1` emits privacy-safe JSON for each
toolbar: HWND, PID/TID/process, visibility, client/DWM bounds, owner/root,
foreground relationship, styles, and capture state. It does not record arbitrary
window titles or typed text.

The expanded language-bar smoke covers real owners, ownerless-show rejection,
same- and cross-process arbitration, stale supersession rejection,
foreground/watchdog hiding, capture-loss/cancel/DPI/hide finalization,
owner/`WM_NCDESTROY` cleanup, and 50 drags with at least 100 move events each. It
also guards zero movement renders, one final render, stable total HWND count and
identity, one position callback, click semantics, and no focus steal.
Deterministic backdrop cases cover builds 22000/22621, attribute and frame
failure, same-size transitions, effective opacity, and unchanged-present churn.

Current confirmed checks:

- `tools\test-tsf-shell-build.ps1`
- `tools\test-language-bar-smoke.ps1`

## Installed clone/drag result and remaining gate

The approved run deployed source commit
`1f419837b0575dc1ea47dba2785cbb6949b7e73c`; the installed TSF SHA-256 was
`76254CE522413F9283192FBC0A599767F1BC636002A2B564E900DC0F834937D0`.
After the stale Explorer holder restarted, all mapped images were current and
the old swap residue was removed without a reboot or delayed delete.

Twenty Notepad drags and one Chromium drag, each with 100 movement events,
retained one valid foreground-owned HWND. The settings segment did not launch
settings while dragging, capture did not stick, one Notepad-to-Chromium
previous-host hide was seen in 34 ms, and the user reported no fresh copies or
afterimages. Acrylic is therefore retained.

The complete gate still requires Notepad, Chromium, Explorer, and one Electron
host, including repeated grip/settings-segment drags and rapid focus changes.
Accept only when:

- at most one toolbar HWND is visible system-wide;
- every visible toolbar has a valid owner whose root is foreground;
- a drag retains the same HWND;
- the old host hides within 250 ms after focus transfer;
- no visible copies or afterimages remain;
- typing focus is never stolen; and
- the final position survives focus changes and host restart.

If one real HWND remains but acrylic ever trails, make static-tint
DirectComposition the default and defer acrylic. If static DirectComposition
also trails, replace only the toolbar presentation with a normally redirected,
opaque native D2D HWND (no `WS_EX_NOREDIRECTIONBITMAP`, no toolbar DComp path).
Clone-free behavior outranks glass.

M11D now owns the blocking result: Chromium required nine attempts to show its
toolbar, Explorer required five and then eleven, several Shift taps did not
change `ascii_mode`, and Claude showed no toolbar after twelve attempts. It must
make activation/toggle/visibility deterministic and complete Explorer/Electron
drag plus host-restart persistence before archival.

## M10 boundary

M11 supplies the reusable composition device/surface foundation only. M10 owns
skin breadth, catalog/import behavior, and candidate-window rendering. The
candidate window remains unchanged in M11, and M10 stays blocked until M11D
passes the complete installed gate.
