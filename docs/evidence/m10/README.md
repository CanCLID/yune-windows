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
   executable, and default skin. `Deploy` atomically refreshes the canonical
   manifest at
   `docs/evidence/m10/machine-state/frozen-candidate.json` before the first
   rename and after every terminal state change. An explicit alternate durable
   path is allowed, but the deploy helper rejects paths below the OS temp tree;
   a scratch manifest is never the sole post-restart provenance copy. Verify
   loaded TSF holders map the pinned image.
   The deployment helper must write the authoritative candidate manifest to the
   durable repository evidence path, not leave its only copy under `%TEMP%`.
   After that manifest exists, replace
   `pending_until_frozen_docs_commit` in `non-elevated-preflight.json` with the
   manifest's exact `source.actual_commit`; the completed-summary contract
   requires those values to match.
4. In fresh Notepad, Chromium, Explorer, and one named Electron host, run one
   toolbar session per host with at least 10 grip and 10 settings-segment drags.
   Use `tools/dev/capture-m10-toolbar-session.ps1` while the operator performs
   the drags, and let sampling continue through the final pointer release. A
   passing capture requires its final sample to show one stable, foreground-owned
   visible toolbar with no toolbar capture. Before its initial process snapshot,
   the recorder exclusively holds `Local\YuneWindowsM10ToolbarCapture.v1` and
   atomically creates the initially unsignaled manual-reset
   `Local\YuneWindowsSettingsLaunchObserved.v1` event. The instrumented settings
   executable signals that event before singleton handling, so an attempted
   startup cannot disappear between topology samples; a signaled event fails the
   gate. A signal during initialization aborts instead of being cleared, and
   concurrent recorders are rejected so neither can interfere with the other's
   observation. WMI process-start observation and the continuous 5 ms poller are
   auxiliary telemetry only and never substitute for a held, unsignaled launch
   sentinel. The recorder freezes its completion boundary after the final
   topology sample, then drains auxiliary telemetry, snapshots PIDs, and checks
   the still-held sentinel; post-boundary observations may fail conservatively
   but cannot create an unobserved pre-boundary gap. Missing sentinel coverage
   fails closed. That first phase leaves every operator field pending and emits
   a sibling capture-time receipt containing the capture SHA-256. After the
   actions and any required host restart, use
   `tools/dev/finalize-m10-toolbar-session.ps1` to attach drag counts and visual
   verdicts to the exact capture SHA-256. The finalizer requires the original
   receipt and rejects a capture edited after receipt creation; do not resample
   or edit either JSON file.
5. Launch the installed settings executable directly. Capture `initial`,
   `minimum`, `minimum_scrolled`, `larger`, and `reopened` geometry as relevant
   with `tools/dev/capture-m10-settings-geometry.ps1`. Exercise both Windows
   light and dark themes and record the DPI actually inspected. The completed
   contract derives the exercised DPI and initial/minimum/larger client sizes
   from these files. Its `minimum_scrolled` capture must mechanically show both
   scrollbar positions at their computed ends.
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

Every toolbar start/completion/sample timestamp, sentinel interval, auxiliary
watcher interval, settings geometry timestamp, and user verdict must be later
than the frozen deployment and the passing post-restart verifier. The completed
summary contract recomputes
toolbar topology metrics from each receipt-bound source sample instead of
trusting copied aggregate fields, rejects duplicate session paths, and binds the
geometry-derived values to the summary.

The canonical final evidence layout is:

- `summary.md` and `summary.json`;
- `source-provenance.json` and `non-elevated-preflight.json`;
- the exact frozen-candidate manifest plus its post-restart verifier output,
  copied into the evidence tree with their SHA-256 values;
- `installed-artifacts.json` when a separate human-readable projection is
  useful;
- `toolbar-gate.json` and `settings-gate.json` when separate detailed ledgers
  are useful;
- `topology/*.json` plus each recorder-generated `*.receipt.json` sibling; and
- `settings/*.json` plus privacy-reviewed screenshots or an equivalent explicit
  visual checklist.

Machine-state evidence must be committed separately from implementation and
non-elevated tooling changes.

The normal deployment contract is deliberately static and records its
post-restart lane as `skipped` with reason `opt_in_required_after_restart`.
After the required session boundary, run the installed lane explicitly against
the durable manifest; do not synthesize an old timestamp to make process-start
comparisons pass:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools\test-m10-frozen-candidate-deploy-contract.ps1 `
  -RunPostRestartLiveVerification `
  -LiveCandidateManifest docs\evidence\m10\machine-state\frozen-candidate.json `
  -LiveVerificationResultPath docs\evidence\m10\machine-state\post-restart-verification.json
```

The live verifier admits only `status=deployed_restart_required` manifests with
`performed=true`, an empty deployment error, and no rollback attempt or
completion. Its holder scan records current-session process coverage and blocks
the final pass when any process module enumeration remains inaccessible.
