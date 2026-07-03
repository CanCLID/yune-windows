# Active Plans

- `m10-plan-skin-breadth-candidate-window.md` - **current focus.** More built-in skins,
  user-imported skins, and applying the shared renderer + skin to the candidate
  window. **Reconciled with M11:** the candidate-window migration rides M11's
  composition renderer (built once); only the second-skin / user-skin / candidate
  schema-field slices are independent — candidate skinning waits on M11 Slice C.
- `m11-plan-ui-modernization-cantonese.md` - **current implementation focus.**
  Non-elevated implementation now covers the Win11-native settings baseline
  (v6 manifest + JhengHei font + DWM gates), Cantonese settings/toolbar strings,
  combo label/value split, toolbar glyph fixes, and the glass-toolbar surface
  shell with host-backdrop/acrylic/static-tint fallback ordering. Live TSF-host
  visual proof of the glass effect remains approval-gated.

Later / unplanned, noted so the settings panel is designed for them:
- Server `customize`+`deploy` path to actually apply the deploy-time **engine
  prefs** (completion/correction/sentence/prediction).
- **Schema import** (bring a new schema; needs the customize/deploy path).
- **Userdb + learning** (import/export + on-device learning; gated by D-05 privacy).
- Per-user `YuneWindowsUiHost.exe` with a single always-on toolbar + animated skins,
  only if native Direct2D skins prove insufficient.

M01 through M09 are in `docs/plans/history/`; see `docs/roadmap.md` for the
milestone table and other candidate milestones (cold-start/broker, dogfood
packaging).
