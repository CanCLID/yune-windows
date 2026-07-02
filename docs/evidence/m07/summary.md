# M07 Evidence Summary

M07 implements persistent per-client Rime composition sessions and the TSF inline
composition key path for candidate selection, while keeping Yune engine internals
and the default `rime_get_api()` ABI unchanged.

## Final Status

- Status: complete. Inline preedit (F4) and partial-selection compose (F3) were
  confirmed live across Tier-1 hosts on 2026-07-02.
- Evidence retained here: compact summary, machine-readable summary, operator
  checklist, and the host-failure diagnostic log under `logs/`.
- Combined live runbook: `docs\evidence\m06-m07-live-closeout.md`.
- The earlier no-output failure (Chrome/Zed/Telegram/Explorer produced no output
  before the inline preedit and partial-selection checks could run) was **not** a
  composition defect: it was the shared server pipe using the default security
  descriptor, which denied sandboxed/lower-integrity host tokens
  (`ERROR_ACCESS_DENIED`). It was fixed reboot-free server-side in M06
  (`test-server-pipe-security-contract.ps1`); the M07 composition path then
  verified live.

## Executed Proof

- `tools\test-server-persistent-composition-contract.ps1` verifies the persistent
  server protocol: session token lifecycle, live raw input/preedit, backspace,
  partial selection preserving remaining input, raw Enter commit, and candidate
  commit separation.
- `tools\test-m07-tsf-composition-contract.ps1` verifies the TSF source model:
  `ITfCompositionSink`, `ITfContextComposition::StartComposition`, inline preedit
  updates, `compose-key`, `compose-select`, `compose-page`, `compose-commit`,
  `compose-commit-raw`, and `compose-end`.
- `tools\test-m06-key-path-fixes-contract.ps1` verifies M06 semantics (F1/F2b/F5/F6)
  are preserved in the rewritten key path, including the single-entry lone-Shift
  toggle whose double-toggle guard is spent only on an actual toggle.
- `tools\test-punctuation-commit-contract.ps1` and
  `tools\test-tsf-key-eating-contract.ps1` verify punctuation forwarding and
  consistent key eating over the persistent composition.
- `tools\test-tsf-server-fallback-raw-commit-contract.ps1` verifies the TSF path
  inserts raw fallback text instead of silently dropping an eaten letter when a
  compose operation fails.
- `tools\test-tsf-ime-state-hotkey-contract.ps1`,
  `tools\test-tsf-shell-build.ps1`, and `tools\test-milestone-naming-contract.ps1`
  passed after the M07 DLL slice.

## Holder-free Live Proof

- The M07 DLL was deployed via `tools\dev\dev-swap-tsf-dll.ps1` (rename-aside;
  apps reload on restart), after the M06 pipe-security fix restored server
  reachability from sandboxed hosts.
- User live host testing on 2026-07-02 confirmed, in Chrome / Telegram / Zed:
  - **F4** — the typed romanization shows inline at the caret while composing.
  - **F3** — typing `dungdatkyut` and picking 東 advances the composition through
    `datkyut`; picking 突 then 厥 composes 東突厥 instead of committing only 東.
  - single-word commit, Space candidate commit, and raw Enter (F6) all work.
- The earlier failed attempt (no output before the composition checks) and its
  diagnosis are retained in `docs\evidence\m06\logs\2026-07-02-user-host-results.md`
  and `docs\evidence\m07\logs\m07-user-host-failures-tsf-events.md`.
- Tooling did not force-close non-dev holders and ran no elevated
  install/register/unregister/cleanup/AppVerifier/PageHeap/registry steps.

## Follow-up Coverage

- Richer segmented preedit display and display attributes remain polish beyond the
  first inline composition implementation.
- Mouse candidate selection remains a later interaction layer; M07 routes
  number-key selection through Rime.
- Learning/userdb remains deferred even though persistent sessions are now in
  place.

## Deferred

- Yune learning/userdb persistence and select-index feedback.
- Full mid-composition cursor editing beyond append, backspace, cancel, page, raw
  commit, and candidate commit.
- Broker/autostart cold-start architecture and sandboxed/AppContainer host support
  beyond the pipe-access fix.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-persistent-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-tsf-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-key-path-fixes-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-punctuation-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-eating-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-fallback-raw-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
```
