# Active Plans

- `m10-plan-skin-breadth-candidate-window.md` - **current focus.** More built-in skins,
  user-imported skins, and applying the shared renderer + skin to the candidate
  window. **Reconciled with M11:** the candidate-window migration rides M11's
  composition renderer (built once); only the second-skin / user-skin / candidate
  schema-field slices are independent — candidate skinning waits on M11 Slice C.
- `m11-plan-ui-modernization-cantonese.md` - **Slices A+B landed** (`c014f18`):
  Win11-native settings panel (v6 manifest + JhengHei font + DWM gates), full
  Cantonese localization, combo label/value split, localized toolbar glyphs. Slice
  C (glass toolbar) was reworked on-device — see the handoff below.
- `m11c-dcomp-glass-toolbar-handoff.md` - **implemented.** Replaced the toolbar's
  `UpdateLayeredWindow` rendering with DirectComposition + Direct2D over DWM
  acrylic: the source drops ULW/layered presentation and uses the validated
  `src/tools/yune_windows_glass_spike.cpp` model (CANNOT_DRAW flag, fixed 96-DPI
  target, extend-frame acrylic, no-activate/drag/click/server-state preserved).
  Human live visual confirmation of clone-free drag + glass remains pending.

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
