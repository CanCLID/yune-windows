# M01 Evidence Summary

M01 established the Yune Windows product baseline: product identity, packaged
Yune loading, TSF shell build, shared server IPC, native candidate window,
installer scripts, diagnostics export, and the approved live closeout path.

## Final Status

- Status: complete
- Evidence retained here: compact summary only
- Raw retained artifacts: none
- Raw transcripts, screenshots, diagnostic bundles, and state snapshots were
  pruned because they are regeneratable and were too bulky for the public repo.

## Proven Behaviors

- Packaged Yune can be loaded through the Windows profile API.
- TSF shell, server, profile tool, and candidate-window smoke binaries build.
- The approved live path covered install, TSF registration, profile activation,
  Notepad input, Chromium input, diagnostics export, uninstall, and cleanup.
- The closeout audit contract checks the live path using synthetic or regenerated
  evidence instead of committed raw transcripts.
- Compatibility target `M01-WIN11-X64` is recorded in the compact summary.
- Signing decision is `defer-production-signing`; unsigned artifacts are local
  dogfood-only and production/public distribution remains blocked on signing.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-host-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-ipc-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1
```

The full live install/register/type/diagnostics/uninstall/cleanup path remains
approval-gated and is run through `tools\run-m01-live-smoke.ps1`.
