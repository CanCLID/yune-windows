# M06 Evidence Summary

M06 implements the host-compatibility relief batch for the known typing
blockers while keeping Yune engine internals and the default `rime_get_api()`
ABI unchanged.

## Final Status

- Status: implementation complete; holder-free live host matrix pending.
- Evidence retained here: compact summary, matrix template, environment
  snapshot.
- Combined live runbook: `docs\evidence\m06-m07-live-closeout.md`.
- Raw retained artifacts: none.
- Closeout basis so far: non-elevated build and source/runtime contracts for
  F1, F2a/F2b, F5, and F6.
- Manual holder-free live verification remains required before M06 is marked
  complete: Tier-1 Notepad, Chromium, daily editor, and Telegram host cells in
  `matrix.md` are still pending.

## Executed Proof

- `tools\test-server-request-resilience-contract.ps1` proves F2a: a client
  disconnecting before write or before read does not kill the shared server,
  and later `op=get-state` plus `input=ngohaig` requests still succeed.
- `tools\test-m06-key-path-fixes-contract.ps1` verifies F1/F2b/F5/F6 source
  contracts: shifted punctuation, unshifted-only `-`/`=` paging, raw Enter,
  capped no-launch key queries, async warm-up, and the low-level Shift hook
  double-toggle guard.
- `tools\test-server-persistent-composition-contract.ps1` verifies the
  persistent server protocol prerequisite used by the next milestone and keeps
  raw Enter semantics covered at server level.
- `tools\test-punctuation-commit-contract.ps1` verifies punctuation still
  forwards through Rime `get_commit` and composing punctuation commits the
  active composition before punctuation.
- `tools\test-tsf-key-eating-contract.ps1` verifies the key sink consumes
  handled composition keys consistently after `OnTestKeyDown`.
- `tools\test-tsf-ime-state-hotkey-contract.ps1`,
  `tools\test-tsf-key-up-pass-through-contract.ps1`, and
  `tools\test-tsf-focus-loss-clears-composition-contract.ps1` verify the
  preserved-key, Shift, focus-loss, and state-reconciliation source contracts.
- `tools\test-tsf-shell-build.ps1`,
  `tools\test-tsf-dll-export-contract.ps1`, and
  `tools\test-milestone-naming-contract.ps1` passed after the M06 batch.

## Host Matrix

- `docs\evidence\m06\matrix.md` exists and encodes the Tier 1-3 hosts, the
  12 compatibility checklist items, and the per-host operator script.
- Current matrix status: pending holder-free live verification.
- No host pass/fail claims are made in this summary until the operator-run
  matrix is filled with current installed-build evidence.

## Holder-free Live Proof

- Partial post-reboot retry was executed by Codex on 2026-07-02 and recorded in
  `docs\evidence\m06\logs\2026-07-02-post-reboot-retry.md`.
- `tools\dev\dev-reload-server.ps1 -RefreshSchema` now passes against the
  installed path after the readiness probe accepts the persisted active schema
  instead of requiring `jyut6ping3`.
- `tools\dev\dev-reload-tsf.ps1 -RestartExplorer` did not copy the installed
  DLL because `Codex.exe` held `YuneWindowsTSF.dll`; Codex was not force-closed
  and profile deactivation was not run.
- Required next operator action: use a holder-free session to run
  `tools\dev\dev-reload-server.ps1 -RefreshSchema`, then
  `tools\dev\dev-reload-tsf.ps1 -RestartExplorer` if a dev-owned Explorer
  restart is acceptable, then execute the Tier-1 matrix.
- Tooling must not force-close non-dev holder applications and must not run
  elevated install/register/unregister/cleanup/AppVerifier/PageHeap/registry
  steps without explicit approval in the current session.

## Follow-up Coverage

- Candidate anchoring in Chromium/Electron-rich fields remains a live matrix
  observation item.
- Native Windows input-mode indicator behavior remains an observation item.
- UWP/AppContainer/sandboxed hosts remain expected limitations until the
  separate broker/autostart milestone.

## Deferred

- Non-US keyboard layout punctuation derivation via `ToUnicodeEx` remains a
  follow-up because M06 intentionally preserves the existing US-layout
  assumption to avoid dead-key and `OnTestKeyDown` side effects.
- Full per-user broker/autostart cold-start elimination remains a later
  milestone; M06 only removes the foreground key-path hard freeze by warming
  asynchronously and capping synchronous key queries.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-request-resilience-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-key-path-fixes-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-punctuation-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-eating-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-up-pass-through-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-focus-loss-clears-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-dll-export-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\collect-m06-compatibility-environment.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
```
