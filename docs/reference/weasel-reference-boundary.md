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

Post-rename dogfood work should keep public Yune Windows evidence compact:

```text
docs/evidence/m01/summary.md
docs/evidence/m01/summary.json
```

When deeper reference-audit files are needed, generate them under
`docs/evidence/m01/bootstrap/` for the local run, then distill the result back
into the compact M01 summary instead of retaining bulky artifacts.

Each audited module should be classified as one of:

- `reuse`
- `rewrite`
- `reference-only`
- `delete`

Any `reuse` decision must name the exact files and the first smoke proving that
the imported behavior works in this repo.
