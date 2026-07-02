# M06/M07 Holder-free Live Closeout

Status: pending operator-run holder-free installed TSF DLL verification.

Latest retry note: on 2026-07-02, the installed server reload passed after the
readiness probe was made schema-flexible, but the installed TSF DLL swap stopped
because `Codex.exe` held `YuneWindowsTSF.dll`. See
`docs/evidence/m06/logs/2026-07-02-post-reboot-retry.md`.

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

1. Start from a holder-free desktop session.
2. Refresh the installed server:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -RefreshSchema
   ```

3. Swap the installed TSF DLL only from a holder-free state:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1 -RestartExplorer
   ```

4. Fill the M06 Tier-1 host matrix in `docs/evidence/m06/matrix.md`:
   Notepad, Chromium browser, VS Code or daily editor, and Telegram Desktop.
5. For each M06 host, capture a structural log window:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-m06-tsf-events-window.ps1 -Label m06-<host>
   ```

6. Run the M07 live checklist in `docs/evidence/m07/live-checklist.md`.
7. Capture M07 structural logs under `docs/evidence/m07/logs/`:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-m06-tsf-events-window.ps1 -Label m07-<host> -OutputDir docs\evidence\m07\logs
   ```

8. Update `docs/evidence/m06/summary.md`, `docs/evidence/m06/summary.json`,
   `docs/evidence/m07/summary.md`, and `docs/evidence/m07/summary.json` with
   the live proof.
9. Only after the live evidence passes, move the M06 and M07 plans from
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

## Final Verification Commands

Run these after recording live evidence and before the final direct-to-main
commit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m07-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m06-m07-live-closeout-readiness-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-milestone-naming-contract.ps1
git diff --check
```
