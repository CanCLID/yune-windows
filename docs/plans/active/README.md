# Active Plans

- `m06-plan-host-compatibility-pass.md` — **current focus.** Verify the M04/M05
  typing controls across the real desktop hosts (Chromium, Electron editor,
  Telegram, rich-edit, console), fix the folded-in typing-blockers (F1
  Shift+punctuation, F2 En→Cn toggle freeze, F5 Telegram lone-Shift via
  `WH_KEYBOARD_LL`, F6 Enter-commits-raw), and capture host-matrix evidence.
- `m07-plan-persistent-composition-selection.md` — **next.** Persistent per-client
  Rime session + inline `ITfComposition` + Rime-driven candidate selection so
  multi-syllable words can be composed by picking characters one at a time
  (`dungdatkyut` → 東突厥), and the input is shown inline at the caret while
  composing. Fixes F3 + F4; no Yune ABI change.

## Bug ledger (folded into the plans above)

| ID | Bug | Milestone |
| --- | --- | --- |
| F1 | Shift+punctuation commits the wrong full-width symbol (`／` not `？`) | M06 |
| F2 | En→Cn toggle freezes the IME for seconds–30s (server death + cold-start) | M06 |
| F3 | Selecting a candidate commits one char and discards the rest of the input | M07 |
| F4 | Composing input is not shown inline at the caret (empty field) | M07 |
| F5 | Lone-Shift never toggles 中/英 in Telegram (Qt key-up delivery) | M06 |
| F6 | Enter commits a Chinese candidate instead of the raw typed letters | M06 |

## Implementation Sequence (best order for GPT)

Ordering rules: **server work first** (instant `dev-reload-server`, no DLL-holder
problem, no reboots) → **batch all DLL changes** into as few holder-free
`dev-reload-tsf` swaps as possible → **M06 fully, then M07** (M07 rewrites the TSF
key path, so it must land after and preserve the M06 key-path fixes). Everything
commits directly to `main`.

1. **Phase 1 — M06 server-side (fast loop, no swap):**
   - **F2a** server resilience (also a hard prerequisite for M07's persistent
     session). Verify with the server-survives-disconnect contract.
2. **Phase 2 — M06 DLL relief batch (holder-free swap #1):** land the key-path
   typing-blockers together —
   - **F1** Shift-aware punctuation, **F6** Enter-commits-raw, **F2b** async
     warm-up + capped key-path wait, **F5** `WH_KEYBOARD_LL` lone-Shift fallback.
   - Live-verify F1/F5/F6 and the F2 non-freeze in Notepad + Telegram.
3. **Phase 3 — M06 compatibility observation + discovered fixes:** run the host
   matrix (Tier 1→3), classify findings, fix in-scope discovered bugs (candidate
   anchoring, language bar, reconciliation, indicator) in a batched swap #2.
4. **Phase 4 — M06 closeout:** evidence, `test-m06-evidence-summary-contract.ps1`,
   roadmap/README updates, move plan to history.
5. **Phase 5 — M07 server-side (fast loop, no swap):** Slice A persistent-session
   protocol + `compose-*` verbs. Depends on F2a. Can be built in parallel with
   M06 Phases 2–4 since it does not touch the DLL.
6. **Phase 6 — M07 DLL rewrite (holder-free swap):** Slice B inline
   `ITfComposition` + Rime-driven selection, **preserving F1/F5/F6 semantics** in
   the new composition model. Verify F3 + F4.
7. **Phase 7 — M07 closeout:** evidence + docs.

M01 through M05 have moved to `docs/plans/history/`. See `docs/roadmap.md` for the
milestone table and candidate later milestones (broker/cold-start, dogfood
packaging, user-data preservation, learning/userdb).
