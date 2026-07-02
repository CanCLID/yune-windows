# M06/M07 Holder-free Live Closeout

Status: complete (2026-07-02). The first operator host verification failed
outside Notepad; that was root-caused to the shared server's default named-pipe
security descriptor denying sandboxed/lower-integrity host tokens, and fixed
reboot-free by scoping the pipe to the current user + AppContainer. The folded-in
fixes (F1/F2/F5/F6) and the M07 inline composition (F3/F4) were then confirmed
live across the Tier-1 hosts. This document is retained as the process record; the
pre-live readiness contract `test-m06-m07-live-closeout-readiness-contract.ps1`
was retired at completion (it enforced the live-pending state).

Latest reload note: on 2026-07-02, the installed server reload passed, then the
user-approved non-elevated TSF DLL reload with Explorer restart passed. See
`docs/evidence/m06/logs/2026-07-02-approved-tsf-reload.md`. User testing after
that reload found Notepad normal typing worked, but Chrome, Zed, Telegram, and
Windows File Explorer produced no output. See
`docs/evidence/m06/logs/2026-07-02-user-host-results.md`. A source fix now
inserts raw fallback text instead of silently dropping eaten keys when TSF
compose operations fail, and logs `server_query_call_failed error_code=...` for
the next live capture. The updated TSF DLL still needs a holder-free reload
before the M06 host matrix and M07 checklist can be rerun.

This file is the combined live closeout runbook for the M06 host matrix and the
M07 inline composition proof. It does not replace the per-milestone evidence:

- M06 matrix: `docs/evidence/m06/matrix.md`
- M07 checklist: `docs/evidence/m07/live-checklist.md`
- M06 summary: `docs/evidence/m06/summary.md`
- M07 summary: `docs/evidence/m07/summary.md`

## Safety Boundary

- Do not force-close non-dev holder applications.
- Do not run elevated install/register/unregister/cleanup/AppVerifier/PageHeap
  or registry steps without explicit current-session approval.
- If `YuneWindowsTSF.dll` is held by non-dev desktop apps, stop and retry from a
  holder-free session or after sign-out/reboot.
- Do not mark M06 or M07 complete until the required live evidence is recorded.

## Required Build

Use the current pushed `main` build. Record the exact commit and installed
artifact hashes through the M06 collector before filling live results:

```powershell
git rev-parse HEAD
powershell -NoProfile -ExecutionPolicy Bypass -File tools\collect-m06-compatibility-environment.ps1
```

## Run Order

1. Start from a holder-free desktop session. If this run follows the
   2026-07-02 no-output failure, make sure the raw-fallback source fix is in
   the build being swapped.
2. Confirm the installed TSF DLL is not held by this Codex process or another
   non-dev desktop holder. If the planned reload will restart Explorer, include
   `-RestartExplorerPlanned`; the preflight must pass before attempting the TSF DLL swap:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-live-closeout-preflight.ps1 -RestartExplorerPlanned
   ```

3. Refresh the installed server:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -RefreshSchema
   ```

4. Swap the installed TSF DLL only from a holder-free state:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1 -RestartExplorer
   ```

5. Fill the M06 Tier-1 host matrix in `docs/evidence/m06/matrix.md`:
   Notepad, Chromium browser, VS Code or daily editor, and Telegram Desktop.
6. For each M06 host, capture a structural log window:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-m06-tsf-events-window.ps1 -Label m06-<host>
   ```

7. Run the M07 live checklist in `docs/evidence/m07/live-checklist.md`.
8. Capture M07 structural logs under `docs/evidence/m07/logs/`:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-m06-tsf-events-window.ps1 -Label m07-<host> -OutputDir docs\evidence\m07\logs
   ```

9. Update `docs/evidence/m06/summary.md`, `docs/evidence/m06/summary.json`,
   `docs/evidence/m07/summary.md`, and `docs/evidence/m07/summary.json` with
   the live proof.
10. Only after the live evidence passes, move the M06 and M07 plans from
   `docs/plans/active/` to `docs/plans/history/` and update
   `docs/plans/active/README.md`.

## Pass Criteria

M06 is complete only when:

- Every Tier-1 host has a non-pending result for all 12 matrix columns.
- F1, F2, F5, and F6 are live-verified in the installed TSF DLL.
- Any failure is classified and either fixed/re-verified or explicitly deferred
  with a recorded reason.

M07 is complete only when:

- Inline preedit is visible at the caret in an installed-DLL desktop host.
- Number-key candidate selection routes through Rime and advances through the
  remaining input instead of clearing it.
- The final phrase commit, raw Enter, Space candidate commit, Backspace, Escape,
  paging, shifted punctuation, lone-Shift, preserved-key toggles, and focus
  cleanup are live-verified.

## Closeout Verification Commands (post-completion)

M06 and M07 are complete; the post-live evidence contracts enforce the completed
state:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
git diff --check
```

The pre-live guard `tools\test-m06-m07-live-closeout-readiness-contract.ps1`,
which asserted M06/M07 remained active and live-pending, was **retired** at
completion — the evidence-summary contracts now enforce the completed state
instead.

## Post-live Closeout Commands

After the holder-free live proof passes, update the M06 and M07 summaries,
machine-readable summaries, and plan locations to the completed state. Then
update the per-milestone evidence summary contracts to assert that completed
state and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
git diff --check
```
