# M08 Modern Floating Toolbar (Direct2D + Skins) Implementation Plan

> **Status:** active. Planned 2026-07-02 as the milestone after M06/M07. Fixes the
> two problems with the M05 language bar: it sits in a fixed corner with no way to
> reposition, and it looks flat/dated. Redesigns it as a draggable, position-
> remembering, Direct2D-rendered bar with a skin-pack architecture.

**Goal:** replace the flat GDI language bar with a modern, high-fidelity toolbar —
a rounded, translucent, icon-based pill rendered with Direct2D/DirectWrite — that
the user can **drag anywhere** and that **remembers its position**, driven by a
**skin-pack** system so the look is customizable (Sogou-style). Native and small
(a few MB), not WebView2.

**Chosen approach (decided with the user):** native Win32 no-activate window +
Direct2D/DirectWrite renderer + JSON skin packs. **No WebView2/Electron in the TSF
DLL** — too heavy, worse focus/input behavior, and it would load into every host
process. If animated Sogou-level skins are ever needed, a separate per-user
`YuneWindowsUiHost.exe` is a later milestone, not this one.

**Architecture principle:** build the Direct2D renderer + skin schema as a
**shared component** so the toolbar uses it now and the **candidate window can
adopt the same skin later** (M09/later). Direct2D is native, so a skinned
candidate window stays compatible with D-04 ("candidate window stays native for
latency"). Do not build a toolbar-only skin engine that must be rewritten.

**Tech Stack:** Win32 layered/no-activate window (C++20), Direct2D + DirectWrite
(+ WIC for raster assets, `ID2D1SvgDocument` for vector icons), the shared server
+ `op=` pipe for persisted position/skin (server stays the sole state writer), and
the M03 dev loop. Iterate via holder-free `dev-reload-tsf` / `dev-swap-tsf-dll`.

---

## Current Facts (grounded)

- **The bar is a flat GDI popup.** `LanguageBarWindow`
  (`src/candidate_window/yune_windows_candidate_window.*`) is a
  `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST` window
  (`yune_windows_candidate_window.cpp:500`) painted with GDI (`Paint`, `:613`),
  with segment hit-testing (`SegmentFromPoint`, `:593`) and a click handler that
  fires `LanguageBarSegment` events (`:585`). It is a clone of
  `NativeCandidateWindow`.
- **It is positioned by the DLL off the caret anchor and cannot be moved.**
  `UpdateLanguageBar` (`src/tsf/yune_windows_tsf.cpp:1840`) fills a
  `LanguageBarState` and sets `anchor` from the caret/candidate anchor, offset up
  ~40px; there is no user reposition and no persisted position, so it effectively
  lives in a fixed spot.
- **Segments already route to server `op=` verbs.** Clicks map to
  `AsciiMode`/`FullShape`/`OutputStandard`/`Schema` (`LanguageBarSegment`,
  `yune_windows_candidate_window.h:28`) → `HandleLanguageBarClick` → the M05
  `op=set-option`/`op=select-schema` path. The content is currently text segments
  (`EN | Half | OpenCC | jyut6ping3`).
- **Monitor-clamp logic already exists to reuse.** `ComputeCandidateWindowRect`
  (`yune_windows_candidate_window.cpp:221`) uses `MonitorFromRect` + `rcWork` to
  keep a window on-screen — reuse it to clamp a restored/dragged position.
- **The server owns persistent state and is its sole writer** (M05):
  `state\ime-state.json`, `op=` verbs, state block on every response
  (`src/server/yune_windows_server.cpp`). Toolbar position and skin selection are
  new persisted values that must go through the server, not per-process file writes
  (multiple in-proc DLLs would race).
- **Build wiring:** `tools/build-tsf-shell.ps1` links the TSF DLL with
  `ole32.lib uuid.lib advapi32.lib user32.lib gdi32.lib`; the candidate-window
  smoke exe is a separate target linking `user32.lib gdi32.lib`. Direct2D needs
  `d2d1.lib dwrite.lib` (+ `windowscodecs.lib` for WIC raster assets); optional
  `dcomp.lib` if DirectComposition is used for shadow/compositing.
- **`ID2D1SvgDocument` (Direct2D SVG) is available** on the Win11 target
  (Windows 10 1703+), so icons can be crisp vector at any DPI.

## Non-Goals

- No WebView2/Electron/HTML in the TSF DLL for this toolbar.
- No always-on, session-wide single toolbar window this milestone — the bar stays
  **per-process, focus-scoped** (it appears at the saved position when a Yune field
  is focused, hides otherwise). A single `YuneWindowsUiHost.exe` that owns one
  always-visible bar is a **later** milestone (needs a server→client push channel).
- No animated mascots / sticker skins / skin store this milestone (later, and only
  if native D2D skins prove insufficient — that is the UI-host milestone).
- No candidate-window restyle this milestone (design the renderer to allow it;
  apply in M09/later).
- No Yune ABI change; `disable_learning` stays forced; the inline candidate window
  stays native.

## Slice Map (sequence)

1. **Slice A — Shared Direct2D renderer + skin-manifest architecture + one default
   skin** (DLL; holder-free swap).
2. **Slice B — Draggable, position-remembering bar** (DLL drag + server-persisted
   position via new `op=` verbs; server fast loop for the protocol).
3. **Slice C — Icon-based redesign + polished default skin** (visual; clicks still
   route to the M05 `op=` verbs).
4. **Slice D — Smoke tool + contracts + evidence.**

Do A first (the renderer + skin schema underpin everything). B is the server
protocol + drag. C is the visual finish. D proves it.

## Design Details

### Slice A — Shared Direct2D renderer + skin manifest + default skin

- **Add a reusable D2D surface** (e.g. `yune_windows::D2DSurface`): owns the
  `ID2D1Factory`/`ID2D1DeviceContext` (or `ID2D1HwndRenderTarget`),
  `IDWriteFactory`, and (if used) WIC factory. Handle **device loss** (recreate on
  `D2DERR_RECREATE_TARGET`) and **per-monitor-v2 DPI** (`WM_DPICHANGED`, DPI-scaled
  metrics). This surface is written once and reused by the toolbar now and the
  candidate window later.
- **Skin manifest.** Define a JSON skin schema — `skins/<name>/theme.json` +
  assets — covering: colors (background, text, accent, hover, pressed, separator,
  shadow), geometry (corner radius, padding, bar height, segment gap), background
  opacity/translucency, font (family, size), and icons (an icon set / per-segment
  SVG or glyph), with an optional logo/avatar. Load from the install root
  `skins/`; **validate and fall back to the built-in default** if a skin is
  missing or malformed. **The default skin ships through this manifest** (not
  hardcoded) so M09 only adds skins + a picker.
- **Toolbar renderer.** Replace `LanguageBarWindow::Paint` (GDI) with a D2D render
  that draws the skinned pill: rounded translucent background, soft shadow,
  separators, each segment with its icon + hover/pressed state. Keep the window
  `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST`; make the background
  translucent via a layered/composited window (per-pixel alpha).
- **Verify:** the bar renders with the default skin, crisp at 100%/150%/200% DPI,
  no device-loss glitches after a display mode change. Holder-free swap.

### Slice B — Draggable, position-remembering bar

- **Drag without stealing focus.** On `WM_LBUTTONDOWN` in the drag zone (the bar
  background / a grip, not a segment): `SetCapture`, track `WM_MOUSEMOVE`, move
  with `SetWindowPos(..., SWP_NOACTIVATE | SWP_NOZORDER)`; release on
  `WM_LBUTTONUP`. Do **not** use `HTCAPTION` (it can activate the window). Use a
  movement threshold to distinguish a drag from a segment click.
- **Persist position through the server.** Add `op=set-toolbar-position\nx=<>\ny=<>`
  (and read it back in the state block); the server persists it in
  `ime-state.json` (a `toolbar` sub-object) as the **sole writer**. On drag-end the
  DLL sends the new position; on show, the DLL places the bar at the persisted
  position (screen coordinates), **clamped to a visible monitor** (reuse
  `ComputeCandidateWindowRect`'s monitor logic). Default position when unset: a
  sensible near-caret or corner spot.
- **Focus-scoped show/hide unchanged** (per-process bar shown while a Yune field is
  focused), just anchored to the saved position instead of a fixed offset. Every
  app's bar reads the same persisted position/skin, so dragging in one app carries
  everywhere.
- Add `op=set-skin\nname=<>` similarly (persisted; used by the M09 picker; in M08
  it just selects the default).
- **Verify:** drag the bar, switch apps → it reappears where you left it; restart →
  position persists; move to a second monitor → clamps sanely; the composing app
  never loses focus during drag. Server protocol verified on the fast loop.

### Slice C — Icon-based redesign + polished default skin

- Redesign the content from text segments to an **icon language**: 中/英 glyph,
  全/半, output standard, schema — with clear hover/pressed affordances and a small
  active-state indicator. Clicks still route to the existing
  `LanguageBarSegment` → M05 `op=` verbs (no protocol change here).
- Ship one **polished default skin** (modern rounded translucent pill, soft
  shadow, tasteful accent) as the reference skin authored against the manifest.
- **Verify live:** the bar looks modern and legible in light/dark backgrounds and
  across the Tier-1 hosts.

### Slice D — Smoke tool + contracts + evidence

- Add a **language-bar smoke exe** (mirroring the candidate-window smoke target)
  that renders the bar with a chosen skin and state for visual/DPI inspection
  without a full install.
- Extend `tools/test-language-bar-window-contract.ps1` for: the D2D render path,
  skin-manifest load + fallback, drag/no-activate + position persistence via
  `op=set-toolbar-position`, and monitor clamping. Add a skin-manifest schema
  contract.
- Record evidence under `docs/evidence/m08/` (summary + contract + a screenshot of
  the default skin at a couple of DPIs). Update roadmap/decisions.

## Tasks

### Task 1: Slice A — renderer + skin manifest
- [ ] Shared `D2DSurface` (device, DPI, device-loss recovery); add
  `d2d1/dwrite`(+`windowscodecs`) to the DLL + smoke link.
- [ ] Skin-manifest schema + loader with validation and default fallback; ship the
  default skin via the manifest.
- [ ] D2D toolbar render (rounded translucent pill, shadow, separators, segments).
- [ ] Holder-free swap; verify render + DPI + device-loss.

### Task 2: Slice B — drag + persisted position
- [ ] Manual no-activate drag with click/drag threshold; monitor clamp on restore.
- [ ] `op=set-toolbar-position` / `op=set-skin` server verbs + `toolbar` state,
  returned in the state block; DLL reads/writes position and skin through the
  server. Verify on `dev-reload-server`.
- [ ] Holder-free swap; verify drag, cross-app persistence, restart persistence,
  multi-monitor, no focus steal.

### Task 3: Slice C — icon redesign + default skin
- [ ] Icon set (SVG via `ID2D1SvgDocument` or an icon font); hover/pressed states;
  clicks route to the M05 `op=` verbs.
- [ ] Author the polished default skin against the manifest. Live-verify.

### Task 4: Slice D — smoke + contracts + evidence
- [ ] Language-bar smoke exe; extend the language-bar contract; skin-schema
  contract; build.
- [ ] `docs/evidence/m08/` summary + contract + screenshots; roadmap/decisions.
  Commit directly to `main`.

## Reviewer Questions (for the user / Codex)

- **Glass style:** translucent-gradient panel (layered per-pixel alpha, easy) is
  the default. Do you also want true OS acrylic backdrop-blur behind the bar
  (`SetWindowCompositionAttribute`), or is the translucent-gradient look enough?
- **Position persistence store:** through the server (`op=set-toolbar-position`,
  keeps the sole-writer invariant — recommended) vs. a separate DLL-owned
  UI-settings file. Confirm the server route.
- **Icon assets:** hand-authored SVGs (`ID2D1SvgDocument`) vs. an icon font vs.
  packaged PNGs. Recommend SVG for DPI-crispness.
- **Default position** when unset: near the caret, or a fixed screen corner?

## Completion Gates

- The language bar is a Direct2D-rendered, rounded, translucent, icon-based bar
  that renders crisply at 100/150/200% DPI with no device-loss glitches.
- The user can **drag it anywhere**; it **remembers its position** across app
  switches and restarts (persisted via the server), clamped to visible monitors,
  and dragging never steals focus from the composing app.
- The look is driven by a **skin manifest**; the default skin loads through it and
  a missing/invalid skin falls back cleanly. The renderer/skin schema is written to
  be reusable by the candidate window later.
- Segment clicks still drive the M05 `op=` verbs (中/英, 全/半, output standard,
  schema).
- No WebView2 in the DLL; no Yune ABI change; `disable_learning` forced; inline
  candidate window unchanged. Evidence + contracts under `docs/evidence/m08/`.
