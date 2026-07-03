# Active Plans

- `m08-plan-modern-toolbar.md` — **current focus.** Replace the flat GDI language
  bar with a draggable, position-remembering, Direct2D/DirectWrite toolbar
  (rounded translucent icon pill) driven by a JSON skin-pack architecture. Native,
  a few MB, no WebView2. Position/skin persisted through the server; renderer + skin
  schema designed to be reused by the candidate window later.
- `m09-plan-skins-and-picker.md` — **next.** Skin picker in the settings UI, a
  second built-in skin, user-imported skin folders, and applying the shared
  Direct2D renderer + skin to the candidate window.

Later (not yet planned): a per-user `YuneWindowsUiHost.exe` hosting a single
always-on toolbar window + animated skins, only if native Direct2D skins prove
insufficient.

M01 through M07 are in `docs/plans/history/`; see `docs/roadmap.md` for the
milestone table and other candidate milestones (cold-start/broker, dogfood
packaging, user-data preservation, learning/userdb).
