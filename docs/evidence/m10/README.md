# M10 Native UI Presentation Closeout Evidence

This directory is reserved for current-hash M10 evidence. The preserved
`docs/evidence/m11/`, `m11c/`, and `m11d/` records remain historical provenance;
they do not close M10 for a newer installed build.

No file in this directory currently claims that M10 passed. Copy
`summary.template.json` to `summary.json` only after the frozen build has been
deployed and both installed gates have actually been exercised. Publish a
matching `summary.md` with the final human-readable verdict.

## Capture order

1. Record the clean full source commit and the diff proving whether intervening
   changes affect product build/package inputs.
2. Run and record the focused non-elevated preflight, including the 100%, 125%,
   150%, and 200% settings minimum/larger/scroll matrix.
3. Record built and installed SHA-256 values for the TSF DLL, server, settings
   executable, and default skin. Verify loaded TSF holders map the pinned image.
4. In fresh Notepad, Chromium, Explorer, and one named Electron host, run one
   toolbar session per host with at least 10 grip and 10 settings-segment drags.
   Use `tools/dev/capture-m10-toolbar-session.ps1` while the operator performs
   the drags, and let sampling continue through the final pointer release. A
   passing capture requires its final sample to show one stable, foreground-owned
   visible toolbar with no toolbar capture. That first phase leaves every
   operator field pending. After the actions and any required host restart, use
   `tools/dev/finalize-m10-toolbar-session.ps1` to attach drag counts and visual
   verdicts to the exact capture SHA-256 without resampling or editing JSON.
5. Launch the installed settings executable directly. Capture `initial`,
   `minimum`, `minimum_scrolled`, `larger`, and `reopened` geometry as relevant
   with `tools/dev/capture-m10-settings-geometry.ps1`. Exercise both Windows
   light and dark themes and record the DPI actually inspected.
6. Fill `summary.json`, add `summary.md`, and run
   `tools/test-m10-evidence-summary-contract.ps1` before archival.

Example topology capture:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\capture-m10-toolbar-session.ps1 `
  -HostId notepad `
  -ExpectedHostProcessName notepad `
  -OutputPath docs\evidence\m10\topology\notepad-capture.json

powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\finalize-m10-toolbar-session.ps1 `
  -CapturePath docs\evidence\m10\topology\notepad-capture.json `
  -OutputPath docs\evidence\m10\topology\notepad-final.json `
  -GripDragsCompleted 10 `
  -SettingsSegmentDragsCompleted 10 `
  -VisualCopiesOrAfterimagesAbsent pass `
  -FocusNeverStolen pass `
  -SettingsDragDidNotActivate pass `
  -CantoneseOnly pass `
  -PositionPersistedAfterFocus pass `
  -PositionPersistedAfterHostRestart pass
```

The capture phase cannot accept pass/fail verdicts. Run the finalizer only after
the user has actually observed every claimed result. For the Electron entry,
name the tested product rather than writing only
“Electron.” Do not record window/control titles, typed text, composition text,
arbitrary keystrokes, or unrelated process content in notes or screenshots.
Settings geometry is a post-action snapshot: its optional operator fields may be
set to `pass` or `fail` only for observations already completed at that exact
phase; leave unobserved fields at `pending`.

The canonical final evidence layout is:

- `summary.md` and `summary.json`;
- `source-provenance.json` and `non-elevated-preflight.json`;
- the exact frozen-candidate manifest plus its post-restart verifier output,
  copied into the evidence tree with their SHA-256 values;
- `installed-artifacts.json` when a separate human-readable projection is
  useful;
- `toolbar-gate.json` and `settings-gate.json` when separate detailed ledgers
  are useful;
- `topology/*.json` from the read-only toolbar recorder; and
- `settings/*.json` plus privacy-reviewed screenshots or an equivalent explicit
  visual checklist.

Machine-state evidence must be committed separately from implementation and
non-elevated tooling changes.
