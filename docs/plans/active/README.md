# Active Plans

- `m11-plan-ui-modernization-cantonese.md` - **current stop-the-line focus.**
  Slices A/B and the Slice C renderer are implemented. The toolbar-clone repair
  now fails closed on missing/invalid owners, arbitrates the visible toolbar
  within and across processes, watches foreground ownership every 250 ms, and
  keeps drag motion presentation-free until one final flush. Non-elevated build
  and expanded drag smoke pass; approval-gated installed visual proof is still
  required before M11 can close.
- `m11c-dcomp-glass-toolbar-handoff.md` - **implementation fixed; installed proof
  pending.** Records the current per-process TSF architecture, ownership and
  supersession rules, movement-only drag contract, effective-backdrop fallback,
  topology diagnostics, and deterministic live fallback order.
- `m10-plan-skin-breadth-candidate-window.md` - **blocked on the M11 installed
  gate.** M10 still owns built-in/user skin breadth and the native candidate
  restyle. Its locked V1 continuation is manifest-only, bounded, revisioned, and
  keeps candidate behavior/performance evidence separate. No M10 slice begins
  until an installed run proves one foreground-owned toolbar with clone-free
  dragging; M11 supplies only the reusable composition foundation.

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
