# M09 Settings Panel + Skin Picker Plan

> **Status:** active (next after M08). Give the toolbar a **settings button** that
> opens a **native settings panel**: the supported toggles + a skin picker wired,
> and schema-import / userdb import-export scaffolded and ready for future
> implementation. **UI tech decided: native Win32** (extend
> `YuneWindowsSettings.exe`) — the user does not need web/visual parity with
> yune-web, so no WebView2. Rich SVG/image asset rendering remains a deliberate
> skin-renderer extension if M09 needs it.

**Goal:** make the toolbar the launch point for a config surface and a skin
picker. A ⚙ button on the bar opens a native settings window where the user can
change the supported settings, pick a skin, and (eventually) import schemas and
import/export the user dictionary. It covers the same *functional* areas as
https://yune-web.pages.dev/ but is a focused native window, **not** a visual replica
(parity is explicitly not a goal). Features that aren't supported yet (userdb,
schema import, deploy-time engine prefs) are **present but disabled** with the
plumbing shaped so they can be wired later without a redesign.

**Skin-breadth (more built-in skins, user-imported skins) and candidate-window
skinning move to M10** so M09 stays focused on the panel + finishing M08.

---

## Current Facts (grounded, after M08)

- M08 ships a Direct2D toolbar (ULW, no-activate drag, server-persisted
  position/skin, reusable `D2DSurface`) driven by `skins/<name>/theme.json`.
  The renderer consumes manifest geometry/colors/font and segment glyph labels.
  It does not ship or render SVG/image assets; richer asset rendering is optional
  M09/M10 scope and should only land with a renderer path that consumes it.
- The toolbar hover state uses `TrackMouseEvent(TME_LEAVE)`, and the current
  glyph render path does not require WIC.
- `YuneWindowsSettings.exe` (M05) exists as a native Win32 config exe wired to the
  server `op=` verbs; it currently covers the core session toggles only.
- The server owns state (`ime-state.json`, `op=` verbs, state block on every
  response) and is the sole writer; skin selection is already an `op=set-skin`
  value.
- (Historical, not the chosen path: yune-web's `Preferences.tsx`/`DictionaryPanel.tsx`
  could have been reused via WebView2, but D-16 chose **native Win32** — no
  WebView2 — so the panel is hand-built with only the controls the IME needs.)
- Deploy-time engine prefs (completion/correction/sentence/prediction), schema
  import, and userdb import/export have **no server support yet** (they need a
  `customize`+`deploy` path and/or the deferred learning milestone).

## Non-Goals

- No WebView2 or visual/behavioral parity replica of yune-web — native Win32
  panel (decided). Same functional areas, not the same UI.
- No animated/mascot skins (later `YuneWindowsUiHost.exe` milestone).
- No candidate-window restyle here (M10).
- No actual userdb persistence or learning (D-05 keeps `disable_learning` forced —
  scaffold the UI only). No actual schema import or engine-pref deploy path yet
  (scaffold + note the future milestone).
- No Yune ABI change.

## Slice Map (sequence)

1. **Slice A — Toolbar settings button** (a ⚙ segment that opens the settings
   panel; routed like the other segments but launches or focuses the panel).
2. **Slice B — Native settings panel** (wire the supported settings, scaffold the
   rest as disabled + future-ready).

## Design Details

### Optional skin asset renderer

M08 intentionally ships manifest glyph labels and no inert image assets. If M09
needs richer skins, add SVG/raster asset loading together with the renderer and
contracts that prove a changed asset changes the toolbar. Keep this independent
from the settings button and panel work.

### Slice A — Toolbar settings button

- **Decided:** add a persistent **`LanguageBarSegment::Settings` (⚙) segment** at
  the end of the toolbar (always visible, not an overflow). It participates in the
  existing segment layout, hit-testing, skin labels, and click handling exactly
  like the other segments. Clicking it launches `YuneWindowsSettings.exe` (or
  focuses it if already open) — a normal on-demand window, not a floating surface.
  Keep the M08 click/drag threshold so dragging the bar via the ⚙ area still moves
  the bar rather than opening the panel.

### Slice B — Native settings panel

- **Panel scope.** One native Win32 window with sections covering:
  - **Input / session** — 中/英, 全/半, output standard, extended charset, disabled
    (wire via the existing M05 `op=` verbs — supported today).
  - **Appearance** — skin picker (choose among installed skins via `op=set-skin`,
    with a live preview inside the panel), plus display prefs (page size, candidate
    layout, font, romanization display) — page size/display prefs may be
    **scaffolded** until the candidate window consumes them (M10).
  - **Engine** — completion / correction / sentence / prediction / combine —
    **scaffolded (disabled, "not yet available")**; needs a server `customize`+
    `deploy` path (a future milestone). Lay out the UI + the intended `op=` shape
    so wiring is a fill-in-the-blank later.
  - **Dictionary** — userdb import / export — **scaffolded (disabled)**; depends on
    the deferred learning/userdb milestone (D-05). Show it so the surface is
    complete and future-ready.
  - **Schemas** — list installed schemas (switch via `op=select-schema`, supported)
    and a **scaffolded** "import schema" affordance (future customize/deploy).
- **Every unsupported control is visibly present but disabled** with a short
  "coming soon" note, so nothing needs a redesign when the backing features land.
- **UI tech: native Win32 (decided).** Extend `YuneWindowsSettings.exe` (already a
  native Win32 exe wired to the server `op=` verbs) with the sections above — no
  WebView2, no runtime dependency, consistent with the native toolbar. Since web
  parity is not a goal, only build the controls the IME actually needs. The skin
  picker's **live preview** reuses the shared `D2DSurface` to render the bar inside
  a preview area of the window. Scaffolded sections are ordinary disabled Win32
  controls with a "coming soon" note.

## Tasks
- [ ] Slice A: toolbar ⚙ settings button that opens the settings panel.
- [ ] Slice B: native Win32 settings panel (extend `YuneWindowsSettings.exe`); wire
  session toggles + schema switch + skin picker (live preview via `D2DSurface`);
  scaffold engine / dictionary / schema-import as disabled + future-ready.
- [ ] Evidence under `docs/evidence/m09/`; contracts (panel launch, skin picker,
  scaffold-disabled invariants); roadmap/decisions. Commit to `main`.

## Decisions (locked — no open questions for handoff)
- **Panel tech:** native Win32, extend `YuneWindowsSettings.exe` (no WebView2; D-16).
- **⚙ button:** a persistent `LanguageBarSegment::Settings` at the end of the bar
  (always visible, not overflow).
- **Scaffolded sections:** shown as **disabled controls with a "coming soon"
  note** (not hidden), so the surface shape is visible and future-ready.

## Completion Gates
- Live toolbar check (M09 modifies the bar, so its live pass re-confirms it):
  after a clean DLL load, exactly **one** toolbar renders (the glass bar with the
  ⚙ segment), it drags and remembers its position, and it never steals focus. (This
  also stands in for M08's still-pending live visual, which is otherwise a
  standalone user check.)
- A ⚙ button on the toolbar opens the settings panel.
- The native settings panel presents the settings sections; the supported
  settings (session toggles, schema switch, skin pick) work; unsupported ones
  (engine prefs, userdb import/export, schema import) are present-but-disabled with
  the plumbing shaped for future wiring.
- No actual learning/userdb enabled (D-05); no Yune ABI change. Evidence under
  `docs/evidence/m09/`.
