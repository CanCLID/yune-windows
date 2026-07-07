# M11 Slice C — DirectComposition Glass Toolbar (GPT implementation handoff)

> **Status:** ready to implement. Replaces the language-bar toolbar's
> `WS_EX_LAYERED` + `UpdateLayeredWindow` (ULW) rendering with a
> **DirectComposition + Direct2D** renderer over a **DWM Desktop Acrylic**
> backdrop. This (a) **fixes the drag clone-trail** — a ULW move artifact that a
> non-ULW window does not have — and (b) **delivers the glass** the user wants.
> Native only; **no WebView2** (D-15/D-16 hold).

**This is de-risked.** Every unknown was validated on the user's machine with a
throwaway prototype: **`src/tools/yune_windows_glass_spike.cpp`** — study it; its
`InitGraphics()` / `Render()` / `ApplyAcrylic()` are the working reference. Do not
re-derive the DComp setup; port it.

---

## Why this is the fix (evidence, not theory)

- The clone-trail is a `UpdateLayeredWindow` move artifact. The **DComp prototype
  dragged clone-free** on the user's machine; the ULW toolbar clones with the same
  drag code. Dropping ULW removes the clone mechanism entirely.
- Glass backdrops (accent/DWM) **do not compose on a ULW window** (confirmed
  on-device: accent gave a flat gray, DWM gave a rectangular halo). A DComp /
  `WS_EX_NOREDIRECTIONBITMAP` window is required for real glass.

## Locked gotchas (each cost a live cycle to find — honor them)

1. **`D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW`** when wrapping
   the DComp surface's DXGI surface in an `ID2D1Bitmap1`. Omitting `CANNOT_DRAW`
   → `CreateBitmapFromDxgiSurface` returns **E_INVALIDARG** (renders nothing).
2. **Render the D2D content at a fixed 96 DPI (1 DIP = 1 px).** Do **not** set the
   device-context/surface DPI to the display DPI. `DrawLanguageBarContent` already
   scales every dimension via `ScaleFloat(x, state.dpi)`; setting the target DPI
   too double-scales (the ~2× "enlarge" bug just fixed in `efd96f2`). The surface
   is sized in physical pixels; content scales once, via `ScaleFloat`.
3. **`DwmExtendFrameIntoClientArea(hwnd, {-1,-1,-1,-1})`** is needed for the DWM
   acrylic to actually render on the borderless popup (plus
   `DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_TRANSIENTWINDOW` and
   `DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND`).
4. The DWM system backdrop (mode 1, Desktop Acrylic) blurs the **desktop
   wallpaper**, not the live app behind the bar. This is **accepted** — the user
   chose mode 1 (supported/stable) over the undocumented live-blur. Do not chase
   accent/host-backdrop; they are dropped.

---

## Target architecture (port from the prototype)

### Window
Create the language-bar window with:
`WS_POPUP` + `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOREDIRECTIONBITMAP`.
**Remove `WS_EX_LAYERED`.** Size the window to the pill (no ULW shadow margin — the
DWM rounded window provides its own drop shadow; drop the D2D `shadow_radius`
padding from the window rect, or keep a tiny margin if a softer shadow is wanted).

### Graphics stack (create ONCE per window; store in the surface object)
D3D11CreateDevice (`D3D11_CREATE_DEVICE_BGRA_SUPPORT`, hardware → WARP fallback) →
`IDXGIDevice` → `ID2D1Factory1` → `CreateDevice(dxgi)` → `CreateDeviceContext` →
`dc->SetDpi(96,96)` → `DCompositionCreateDevice(dxgi, ...)` →
`CreateTargetForHwnd(hwnd, TRUE)` → `CreateVisual` →
`CreateSurface(w, h, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_ALPHA_MODE_PREMULTIPLIED)` →
`visual->SetContent(surface)` → `target->SetRoot(visual)`.
Apply the backdrop (gotcha 3) after `CreateWindowEx`.

### Per-present render (reuse `DrawLanguageBarContent` unchanged)
`surface->BeginDraw(nullptr, __uuidof(IDXGISurface), &dxgiSurface, &offset)` →
`CreateBitmapFromDxgiSurface(dxgiSurface, {TARGET|CANNOT_DRAW, B8G8R8A8_UNORM,
PREMULTIPLIED}, &bmp)` (gotcha 1) → `dc->SetTarget(bmp)` → `dc->BeginDraw()` →
`dc->SetTransform(Translation(offset.x, offset.y))` → `dc->Clear(transparent)` →
**`DrawLanguageBarContent(dc, ...)`** (it takes `ID2D1RenderTarget*`;
`ID2D1DeviceContext` is one — reuse as-is) → `dc->EndDraw()` →
`dc->SetTarget(nullptr)` → `surface->EndDraw()` → `dcompDevice->Commit()`.
Re-render on state/hover/pressed change and on resize; the DComp content persists
between presents (no per-frame window move — SetWindowPos moves it cleanly).

### Glass look
The acrylic shows through wherever the D2D content is transparent. Draw the pill
background with a **low-alpha tint** (glass) so glyphs stay readable and the
acrylic frosts through — extend the skin's `background`/`glass_tint` for this.
Hover/pressed highlights must be **semi-transparent** D2D fills (real alpha), not
opaque. Keep dividers, grip dots, and the accent-blue active glyphs.

### Size / DPI (keep the just-shipped behavior)
Keep the **compact fixed size** the user approved (`state_.dpi = 96` in
`Update()`), render target at 96 (1:1). If per-monitor scaling is wanted later,
the *only* correct way is: size the surface in physical px (`Scale(min_width,
dpi)`), keep the target at 96, and let `ScaleFloat` scale content once. Handle
`WM_DPICHANGED` by recreating the surface at the new size and re-rendering.

---

## Behavior that MUST be preserved (regression checklist)

Port from the current `LanguageBarWindow` — do not lose any of these:
- **No focus steal:** `WS_EX_NOACTIVATE` + `WM_MOUSEACTIVATE → MA_NOACTIVATE` +
  `WM_NCHITTEST → HTCLIENT`. Verify typing continues in the host app while the bar
  is shown/dragged.
- **Drag:** the existing `SetCapture` click-vs-drag state machine
  (`BeginPointerInteraction`/`ContinuePointerInteraction`/`EndPointerInteraction`),
  the `kLanguageBarDragThreshold`, the grip-zone + settings-segment drag zones, and
  the **drag-active guard** in `Update()` (skip caret-follow reposition while
  `pointer_captured_`). Move via `SetWindowPos` (clone-free on a DComp window).
- **Click dispatch:** fire only when release is on the same segment as press,
  within threshold, inside the window (the M09 semantics). Route segment clicks to
  the server ops (ascii/full/output/schema cycle, ⚙ → launch/focus settings).
- **Server-owned state (D-12):** skin, `toolbar_position`, mode/shape/output/schema
  via `op=` verbs; `op=set-toolbar-position` on drag-end; **never** read/write
  `state\ime-state.json` from the DLL.
- **Localized glyphs (M11):** `中/英`, `全/半`, `傳/港/台/简`, `粵/倉/朙`, `⚙` —
  already in `ToolbarSegmentLabelForState`; unchanged.
- **Caret-follow + foreground scoping:** `ForegroundMatchesOwner()` hide/show when
  the host app is/isn't foreground; monitor clamp
  (`ClampToolbarRectToVisibleMonitor`); saved-position vs caret-anchor placement.
- **Single position authority / no clone:** verify by dragging repeatedly (the bug
  report: clean first drag, then accumulates — must stay clean indefinitely).
- **Device loss (NEW):** handle D3D/DXGI device-removed and DComp device-lost by
  recreating the whole graphics stack and re-rendering (analogous to the old
  `D2DERR_RECREATE_TARGET`). Do not crash or leave a black bar.

## Skin / backdrop
- Default skin `glass_mechanism` = **`dwm_acrylic`** (DWM Desktop Acrylic, mode 1).
  The `accent_*` / `host_backdrop` mechanisms are dead on ULW and not used by the
  DComp path — remove them or repurpose `glass_mechanism` to select DWM backdrop
  type (acrylic vs mica vs none/flat). Keep a **flat/no-glass fallback** for
  Windows 10 (Decision 7: build < 22000 → skip the backdrop, solid pill).
- Extend the skin schema as needed for the glass tint/opacity over the acrylic;
  keep back-compat with existing manifests.

## Settings-panel preview
`PaintLanguageBarPreview` (in the settings window) renders a static toolbar preview
via `ID2D1DCRenderTarget`. It can stay as-is (static, opaque preview) — it does not
need the DComp/acrylic path. Just apply the same **96-DPI / no-double-scale** fix
there (already done in `efd96f2`).

## Build
Add `d3d11.lib dxgi.lib dcomp.lib` to the **TSF DLL** link line in
`tools/build-tsf-shell.ps1` (it already links `d2d1 dwrite dwmapi`). Include
`<d3d11.h> <dxgi1_2.h> <d2d1_1.h> <dcomp.h>` in the candidate-window source.

## Contracts + evidence + gates
- Source-grep contract: toolbar window uses `WS_EX_NOREDIRECTIONBITMAP` and **not**
  `WS_EX_LAYERED`/`UpdateLayeredWindow`; `DCompositionCreateDevice` +
  `CreateTargetForHwnd` present; `D2D1_BITMAP_OPTIONS_CANNOT_DRAW` present; render
  target/`SetDpi` fixed at 96 (no `state.dpi` passed to the composition target);
  `DWMSBT_TRANSIENTWINDOW` + extend-frame present; no WebView2/HTML.
- Keep the M08/M09/M11 contracts green (update the ones asserting ULW invariants —
  they now assert the DComp model instead).
- **Live-visual gate (user):** dragging repeatedly leaves **no clones**; the bar
  shows frosted acrylic + rounded; no focus steal while typing; size stays compact
  and stable idle vs composing; the candidate window is unaffected (no latency
  regression). Evidence under `docs/evidence/m11c/`.

## Non-goals
- No WebView2/Electron/HTML. No live-content blur (mode 1 wallpaper acrylic is the
  choice). No Yune ABI change; `disable_learning` forced. No candidate-window
  restyle in this slice (M10 owns that; it can later ride the same renderer).
