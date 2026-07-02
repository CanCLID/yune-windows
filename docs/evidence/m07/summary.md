# M07 Evidence Summary

M07 implements persistent per-client Rime composition sessions and the TSF
inline composition key path for candidate selection, while keeping Yune engine
internals and the default `rime_get_api()` ABI unchanged.
Boundary: Yune engine internals and the default rime_get_api() ABI unchanged.

## Final Status

- Status: implementation complete; holder-free live TSF proof pending.
- Evidence retained here: compact summary and machine-readable summary.
- Operator checklist: `docs\evidence\m07\live-checklist.md`.
- Combined live runbook: `docs\evidence\m06-m07-live-closeout.md`.
- Raw retained artifacts: none.
- Closeout basis so far: non-elevated server protocol contract, TSF source
  contracts, TSF shell build, DLL export contract, and M06 regression contracts.
- Manual holder-free live verification remains required before M07 is marked
  complete: the installed TSF DLL must be swapped in a holder-free session, then
  a real host must verify inline preedit plus partial candidate selection.

## Executed Proof

- `tools\test-server-persistent-composition-contract.ps1` verifies the
  persistent server protocol: session token lifecycle, live raw input/preedit,
  backspace, partial selection preserving remaining input, raw Enter commit, and
  candidate commit separation.
- `tools\test-m07-tsf-composition-contract.ps1` verifies the TSF source model:
  `ITfCompositionSink`, `ITfContextComposition::StartComposition`, inline
  preedit updates, `compose-key`, `compose-select`, `compose-page`,
  `compose-commit`, `compose-commit-raw`, and `compose-end`.
- `tools\test-m06-key-path-fixes-contract.ps1` verifies M06 semantics are
  preserved in the rewritten key path: shifted punctuation, unshifted-only
  `-`/`=` paging, raw Enter, capped no-launch key queries, async warm-up, and
  low-level Shift hook guard.
- `tools\test-punctuation-commit-contract.ps1` verifies punctuation still goes
  through Rime `get_commit` and composing punctuation commits the active
  persistent composition before inserting punctuation.
- `tools\test-tsf-key-eating-contract.ps1` verifies `OnTestKeyDown` and
  `OnKeyDown` still consume handled composition keys consistently, including
  the not-ready-server drop path.
- `tools\test-tsf-ime-state-hotkey-contract.ps1`,
  `tools\test-tsf-key-up-pass-through-contract.ps1`, and
  `tools\test-tsf-focus-loss-clears-composition-contract.ps1` verify preserved
  keys, lone-Shift pass-through, state reconciliation, focus cleanup, and inline
  composition cleanup contracts.
- `tools\test-tsf-shell-build.ps1`,
  `tools\test-tsf-dll-export-contract.ps1`, and
  `tools\test-milestone-naming-contract.ps1` passed after the M07 DLL slice.

## Holder-free Live Proof

- Not yet executed by Codex in this session.
- Required next operator action: use a holder-free installed TSF DLL session,
  run the M03 dev reload sequence for the current build, then follow
  `live-checklist.md` in a real host to prove inline preedit and number-key
  candidate selection advance through the remaining input instead of clearing it.
- Also recheck single-word commit, raw Enter, Space candidate commit, backspace,
  Escape cancel, paging, shifted punctuation, lone-Shift, preserved-key toggles,
  and focus-loss cleanup.
- Tooling must not force-close non-dev holder applications and must not run
  elevated install/register/unregister/cleanup/AppVerifier/PageHeap/registry
  steps without explicit approval in the current session.

## Follow-up Coverage

- Richer segmented preedit display and display attributes remain polish beyond
  the first inline composition implementation.
- Mouse candidate selection remains a later interaction layer; M07 routes
  number-key selection through Rime.
- Learning/userdb remains deferred even though persistent sessions are now in
  place.

## Deferred

- Yune learning/userdb persistence and select-index feedback.
- Full mid-composition cursor editing beyond append, backspace, cancel, page,
  raw commit, and candidate commit.
- Broker/autostart cold-start architecture and sandboxed/AppContainer host
  support.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-persistent-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-tsf-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-key-path-fixes-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-punctuation-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-eating-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-up-pass-through-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-focus-loss-clears-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-dll-export-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
```
