# M02 Evidence Summary

M02 hardened the shared-server lifecycle and cleanup behavior for repeatable
dogfood runs.

## Final Status

- Status: complete
- Evidence retained here: compact summary only
- Raw retained artifacts: none

## Proven Behaviors

- The installed TSF DLL starts or reconnects to the product-owned server.
- Duplicate server protection is scoped to the pipe name.
- Busy-pipe and missing-pipe paths remain bounded and structurally logged.
- Installed Notepad and Chromium smokes passed without manually starting the
  server.
- Cleanup can report delayed-delete recovery and post-reboot no-residue
  validation.
- The approved closeout covered diagnostics export and profile activation before
  typing, then passed post-reboot cleanup verification.

Raw transcripts, screenshots, state snapshots, and cleanup dumps were pruned.
Regenerate them with the approved live sequence only when a fresh live gate
requires them.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-product-owned-server-smoke-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-single-instance-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-uninstall-structured-cleanup-result-contract.ps1
```

Full live closeout remains approval-gated and reuses the M01 live-smoke tooling.
