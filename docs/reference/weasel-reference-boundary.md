# Weasel Reference Boundary

The legacy Weasel-derived implementation is reference material only. It may
exist locally in a separate checkout, but it is not part of this public product
history.

## What To Reuse

Audit these areas first:

- `WeaselTSF/` - TSF text service registration, key sinks, edit sessions.
- `WeaselServer/` and `WeaselIPCServer/` - server lifecycle and IPC shape.
- `WeaselIPC/` - wire format helpers.
- `RimeWithWeasel/` - engine adapter patterns and migration hazards.
- `WeaselUI/` - caret/candidate positioning reference.
- `WeaselDeployer/` and `WeaselSetup/` - installer and registration behavior.
- smoke harnesses such as IPC console tools.

## What Not To Reuse Blindly

- librime runtime fallback assumptions;
- old Weasel visible UI architecture;
- stale settings panels;
- broad copy-paste of historical commits;
- default ABI widening;
- machine-state scripts without cleanup evidence.

## Required Audit Output

Post-rename dogfood work should regenerate public Yune Windows evidence such as:

```text
docs/evidence/p2-win01-bootstrap/reference-audit.md
docs/evidence/p2-win01-bootstrap/process-model.md
docs/evidence/p2-win01-bootstrap/first-smoke-target.md
```

Each audited module should be classified as one of:

- `reuse`
- `rewrite`
- `reference-only`
- `delete`

Any `reuse` decision must name the exact files and the first smoke proving that
the imported behavior works in this repo.
