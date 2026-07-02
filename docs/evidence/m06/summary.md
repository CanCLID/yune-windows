# M06 Evidence Summary

M06 delivers the host-compatibility relief batch for the known typing blockers
and verifies the M04/M05 typing controls across real desktop hosts, while keeping
Yune engine internals and the default `rime_get_api()` ABI unchanged.

## Final Status

- Status: complete. All folded-in fixes (F1, F2, F5, F6) and the compatibility
  behaviors were confirmed live across the Tier-1 hosts on 2026-07-02.
- Evidence retained here: compact summary, filled host matrix, environment
  snapshot, and the dated host-result logs under `logs/`.
- Combined live runbook: `docs\evidence\m06-m07-live-closeout.md`.
- Root cause of the earlier no-output failure (Chrome/Zed/Telegram/Explorer): the
  shared server created its named pipe with the **default security descriptor**,
  which admits only the server creator's own token, so a TSF DLL loaded inside a
  sandboxed / lower-integrity host process got `ERROR_ACCESS_DENIED` on connect
  (`WaitNamedPipeW` succeeds, `CreateFileW`/`CallNamedPipeW` fails — the captured
  `server_warmup_started -> server_launch_ready -> server_query_failed` pattern).
  This was a server-side access issue, independent of the M07 composition work.
- Fix: the pipe now uses an explicit descriptor scoping access to the **current
  user's SID** at any integrity level plus all application packages (`AC`,
  AppContainer/UWP) with a Low mandatory label, excluding other machine users. It
  deploys reboot-free (no DLL reload) because the already-loaded DLLs connect on
  their next query. (The live host proof was captured with the initial equivalent
  `IU`+`AC` descriptor; every tested host is one of the current user's own
  processes, so it connects identically under the tightened current-user+`AC`
  grant — the scoping only removes *other* users' access.)

## Executed Proof

- `tools\test-server-pipe-security-contract.ps1` proves the pipe DACL grants
  AppContainer (`AC`) and the current user's SID (not the broad IU/WD/AU aliases)
  and still answers requests (30 candidates); this is the fix for the no-output
  hosts.
- `tools\test-server-request-resilience-contract.ps1` proves F2a: a client
  disconnecting before write or before read does not kill the shared server, and
  later `op=get-state` plus `input=ngohaig` requests still succeed.
- `tools\test-m06-key-path-fixes-contract.ps1` verifies F1/F2b/F5/F6 source
  contracts: shifted punctuation, unshifted-only `-`/`=` paging, raw Enter, capped
  no-launch key queries, async warm-up, and the single-entry lone-Shift toggle
  whose double-toggle guard is spent only when a toggle actually fires.
- `tools\test-server-ime-state-protocol-contract.ps1` (F2 latency fix) confirms
  the server still persists and returns option/schema state after the startup
  dictionary warm-up was added.
- `tools\test-server-persistent-composition-contract.ps1` verifies the persistent
  server protocol prerequisite and keeps raw Enter semantics covered.
- `tools\test-punctuation-commit-contract.ps1` verifies punctuation still forwards
  through Rime `get_commit` and composing punctuation commits first.
- `tools\test-tsf-key-eating-contract.ps1` verifies the key sink consumes handled
  composition keys consistently after `OnTestKeyDown`.
- `tools\test-tsf-server-fallback-raw-commit-contract.ps1` verifies a
  compose-operation failure inserts raw fallback text instead of dropping an eaten
  letter key.
- `tools\test-tsf-ime-state-hotkey-contract.ps1` and
  `tools\test-tsf-shell-build.ps1` passed after the M06 batch.

## Host Matrix

- `docs\evidence\m06\matrix.md` records the Tier 1-3 hosts, the 12 compatibility
  checklist items, the per-host operator script, and the filled 2026-07-02
  results.
- Result: **Notepad, Chromium browser, Telegram Desktop, and Zed all pass** the
  Tier-1 behavior checks (caret-anchored candidates, paging, punctuation, F1
  shifted punctuation, F6 raw Enter, F5 lone-Shift toggle, F3/F4 inline compose).
  File Explorer's search box types Chinese after the pipe fix.
- The earlier no-output failure in Chrome/Zed/Telegram/Explorer is resolved by the
  pipe-security fix and re-verified by the user typing in each host.

## Holder-free Live Proof

- The pipe-security fix was deployed to the installed server reboot-free via
  `tools\dev\dev-swap-server-binary.ps1` (rename-aside swap + launch-mutex hold);
  it reported the hardened pipe live and 30 candidates.
- Objective confirmation: a restricted/sandboxed client that was denied on the
  installed pipe before the fix connected successfully afterward.
- The F5/toggle DLL fix was swapped in via `tools\dev\dev-swap-tsf-dll.ps1`
  (rename-aside; apps reload on restart).
- User live host testing on 2026-07-02, across Chrome / Telegram / Zed / Explorer,
  confirmed: F1 shifted full-width punctuation, F6 raw Enter, F4 inline preedit,
  F3 partial-selection compose (東突厥), and — after the dictionary warm-up and the
  single-entry lone-Shift toggle fix — the F2/F5 中/英 Shift toggle switching
  instantly and registering on the first press.
- Earlier dated attempts (the pre-fix no-output failure and its diagnosis) are
  retained in `logs/2026-07-02-user-host-results.md`.
- Tooling did not force-close non-dev holders and ran no elevated
  install/register/unregister/cleanup/AppVerifier/PageHeap/registry steps.

## Follow-up Coverage

- Broader host breadth (Office, WeChat, additional Electron apps) can be added to
  the matrix opportunistically.
- Native Windows input-mode indicator behavior across hosts remains an observation
  item.
- UWP/AppContainer/sandboxed hosts beyond the pipe-access fix (e.g. cold-start in
  those hosts) remain the separate broker/autostart milestone.

## Deferred

- Non-US keyboard layout punctuation derivation via `ToUnicodeEx` remains a
  follow-up; M06 preserves the US-layout assumption to avoid dead-key /
  `OnTestKeyDown` side effects.
- Full per-user broker/autostart cold-start elimination remains a later milestone;
  M06 removes the foreground key-path hard freeze (server resilience + async
  warm-up + capped key queries) and the first-keystroke latency (startup
  dictionary warm-up), not the whole cold-start architecture.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-pipe-security-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-request-resilience-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-ime-state-protocol-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-persistent-composition-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-key-path-fixes-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-punctuation-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-eating-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-fallback-raw-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
```
