# M03 Evidence Summary

M03 added the non-elevated development inner loop: no-install REPL, installed
server reload, installed TSF DLL reload guardrails, disposable test window, and
dry-run watch routing.

## Final Status

- Status: complete
- Evidence retained here: compact summary only
- Raw retained artifacts: none

## Proven Behaviors

- `dev-repl.ps1` can query a scratch server without install or TSF registration.
- Installed-server reload keeps backups and validates readiness.
- Installed TSF reload refuses unsafe non-dev DLL holders.
- Watch mode defaults to dry-run and only acts with explicit opt-in.
- Dev tooling avoids elevated registration, registry edits, delayed-delete
  cleanup, verifier setup, and canonical live install/uninstall loops.

Installed-path reload logs and holder snapshots are intentionally pruned.
Regenerate them only when validating a new installed build.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-tooling-safety-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-reload-no-reregister-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -InputText ngohaig -Once
```
