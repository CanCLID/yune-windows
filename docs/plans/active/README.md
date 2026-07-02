# Active Plans

- `m06-plan-host-compatibility-pass.md` — **current focus.** Verify the M04/M05
  typing controls across the real desktop hosts (Chromium, Electron editor, chat,
  rich-edit, console), fix in-scope defects (F1 Shift+punctuation, F2 En→Cn toggle
  freeze, and the deferred lone-Shift `WH_KEYBOARD_LL` fallback), and capture
  host-matrix evidence.
- `m07-plan-persistent-composition-selection.md` — **next.** Persistent per-client
  Rime session + inline `ITfComposition` + Rime-driven candidate selection so
  multi-syllable words can be composed by picking characters one at a time
  (`dungdatkyut` → 東突厥). Fixes F3; no Yune ABI change. Starts once M06 lands
  (server side can proceed in parallel).

M01 through M05 have moved to `docs/plans/history/`. See
`docs/roadmap.md` for candidate next milestones.
