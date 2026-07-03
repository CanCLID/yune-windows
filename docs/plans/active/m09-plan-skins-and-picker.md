# M09 Settings Panel + Skin Picker Plan

> **Status:** active (next after M08). Give the toolbar a **settings button** that
> opens a **full settings panel** with yune-web-parity structure: all supported
> toggles + skin picker wired, and schema-import / userdb import-export scaffolded
> and ready for future implementation. Rich SVG/image asset rendering remains a
> deliberate skin-renderer extension if M09 needs it.

**Goal:** make the toolbar the launch point for a complete config surface and a
skin picker. A ⚙ button on the bar opens a settings panel modeled on
https://yune-web.pages.dev/ where the user can toggle every setting, pick a skin,
and (eventually) import schemas and import/export the user dictionary. Features
that aren't supported yet (userdb, schema import, deploy-time engine prefs) are
**present but disabled** with the plumbing shaped so they can be wired later
without a redesign.

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
- yune-web already has the parity UI (`apps/yune-web/src/Preferences.tsx`,
  `DictionaryPanel.tsx`, schema selection) driving a wasm Rime — reusable via
  WebView2 if we point its engine adapter at the Windows named-pipe server.
- Deploy-time engine prefs (completion/correction/sentence/prediction), schema
  import, and userdb import/export have **no server support yet** (they need a
  `customize`+`deploy` path and/or the deferred learning milestone).

## Non-Goals

- No animated/mascot skins (later `YuneWindowsUiHost.exe` milestone).
- No candidate-window restyle here (M10).
- No actual userdb persistence or learning (D-05 keeps `disable_learning` forced —
  scaffold the UI only). No actual schema import or engine-pref deploy path yet
  (scaffold + note the future milestone).
- No Yune ABI change.

## Slice Map (sequence)

1. **Slice A — Toolbar settings button** (a ⚙ segment that opens the settings
   panel; routed like the other segments but launches or focuses the panel).
2. **Slice B — Full settings panel** (yune-web-parity layout; wire the supported
   settings, scaffold the rest as disabled + future-ready).

## Design Details

### Optional skin asset renderer

M08 intentionally ships manifest glyph labels and no inert image assets. If M09
needs richer skins, add SVG/raster asset loading together with the renderer and
contracts that prove a changed asset changes the toolbar. Keep this independent
from the settings button and panel work.

### Slice A — Toolbar settings button

- Add a **⚙ settings segment** to the toolbar (a new `LanguageBarSegment::Settings`
  or a dedicated affordance). Clicking it launches `YuneWindowsSettings.exe`
  (or focuses it if already open) — a normal on-demand window, not a floating
  surface. Keep the click/drag threshold behavior from M08.

### Slice B — Full settings panel (yune-web parity)

- **Panel scope (parity layout).** One window with sections mirroring yune-web:
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
  "coming soon" note, so the panel matches yune-web's shape and nothing needs a
  redesign when the backing features land.
- **UI tech decision (the key M09 question):** the settings panel is an ordinary
  on-demand window (not floating/perf-critical), so **WebView2 reusing yune-web's
  Preferences/Dictionary/schema components** is the natural high-parity, low-effort
  choice — repoint yune-web's engine adapter from wasm Rime to the Windows
  named-pipe server. Tradeoff: it reintroduces the WebView2 runtime dependency for
  the settings exe (opened occasionally, so no always-on perf cost). The
  alternative is extending the native Win32 `YuneWindowsSettings.exe` (no
  dependency, but every parity control is hand-built). **Recommendation: WebView2
  for the panel** (the toolbar stays native D2D). Confirm before building.

## Tasks
- [ ] Slice A: toolbar ⚙ settings button that opens the settings panel.
- [ ] Slice B: settings panel (WebView2 or native per the decision) with the parity
  layout; wire session toggles + schema switch + skin picker; scaffold engine /
  dictionary / schema-import as disabled + future-ready.
- [ ] Evidence under `docs/evidence/m09/`; contracts (panel launch, skin picker,
  scaffold-disabled invariants); roadmap/decisions. Commit to `main`.

## Reviewer Questions
- **Panel tech: WebView2 (reuse yune-web, recommended) vs. native Win32?** This is
  the pivotal decision.
- Scaffolded sections: disabled controls with "coming soon", or hide them until
  their backing milestone lands? (Recommend: show disabled, so the shape is
  visible and future-ready.)
- Should the ⚙ button live on the bar always, or only in an overflow/expanded
  state to keep the bar compact?

## Completion Gates
- A ⚙ button on the toolbar opens the settings panel.
- The settings panel presents the full yune-web-parity layout; the supported
  settings (session toggles, schema switch, skin pick) work; unsupported ones
  (engine prefs, userdb import/export, schema import) are present-but-disabled with
  the plumbing shaped for future wiring.
- No actual learning/userdb enabled (D-05); no Yune ABI change. Evidence under
  `docs/evidence/m09/`.
