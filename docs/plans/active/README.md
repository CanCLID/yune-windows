# Active Plans

- `m09-plan-skins-and-picker.md` — **current focus.** Add a toolbar settings
  button and build a full **settings panel** with yune-web-parity structure —
  session toggles + schema switch + skin picker wired, and engine prefs / userdb
  import-export / schema import scaffolded (present-but-disabled, future-ready).
  Rich SVG/image asset rendering is optional follow-up only when the renderer
  consumes those assets. Key open decision: WebView2 (reuse yune-web, recommended)
  vs. native for the panel.
- `m10-plan-skin-breadth-candidate-window.md` — **next.** More built-in skins,
  user-imported skins, and applying the shared Direct2D renderer + skin to the
  candidate window.

Later / unplanned, noted so the settings panel is designed for them:
- Server `customize`+`deploy` path to actually apply the deploy-time **engine
  prefs** (completion/correction/sentence/prediction).
- **Schema import** (bring a new schema; needs the customize/deploy path).
- **Userdb + learning** (import/export + on-device learning; gated by D-05 privacy).
- Per-user `YuneWindowsUiHost.exe` with a single always-on toolbar + animated skins,
  only if native Direct2D skins prove insufficient.

M01 through M08 are in `docs/plans/history/`; see `docs/roadmap.md` for the
milestone table and other candidate milestones (cold-start/broker, dogfood
packaging).
