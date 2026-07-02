# M07 Holder-free Live Checklist

Status: pending holder-free installed TSF DLL verification.

Use this checklist only after the current `main` build has been loaded into the
installed path in a holder-free session. Do not force-close non-dev holder
applications, and do not run elevated install/register/unregister/cleanup,
AppVerifier, PageHeap, or registry steps without explicit current-session
approval.

## Setup

1. Confirm `git rev-parse HEAD` matches the intended pushed build.
2. In a holder-free session, refresh the installed server with:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -RefreshSchema
   ```

3. If a dev-owned Explorer restart is acceptable, swap the installed TSF DLL with:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1 -RestartExplorer
   ```

4. Run the M06 environment collector so the evidence records the installed build:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\collect-m06-compatibility-environment.ps1
   ```

5. Capture a structural log window before or after each host run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-m06-tsf-events-window.ps1 -Label m07-<host> -OutputDir docs\evidence\m07\logs
   ```

## Required Host Proof

Run at least one normal desktop text host first. Notepad is the baseline; use
Chromium or the daily editor as the richer host if the baseline passes.

| Host | Inline preedit | Partial selection advances | Final phrase commit | Raw Enter | Space candidate commit | Backspace/Escape | Paging | M06 regressions | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Notepad | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Chromium or daily editor | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Test Script

For each host:

1. Focus a plain editable field.
2. Type a multi-syllable input that has partial-selection candidates, using the
   current server contract fixture as the oracle when possible.
3. Confirm the romanization/preedit is visible inline at the caret while
   composing, not only in the floating native candidate window.
4. Press a number key for a partial candidate and confirm the committed segment
   appears while the remaining input stays composing inline.
5. Continue selecting until the phrase is committed; confirm the committed text
   is ordered correctly and no remaining input is discarded.
6. Type `caksi` and press Enter; confirm the raw lowercase letters commit.
7. Type `caksi` and press Space; confirm a Chinese candidate commits instead of
   raw letters.
8. Verify Backspace edits the live composition and Escape cancels it without
   leaving stale inline text or candidate windows.
9. Verify PageUp/PageDown and unshifted `-`/`=` page candidates while composing.
10. Recheck M06 regressions in the same loaded DLL:
    - Shift+/ commits `？`.
    - Shift+= commits `＋`.
    - Shift+- commits `——`.
    - Lone Shift toggles Chinese/English without double-toggle.
    - Shift+letter still capitalizes and does not toggle.

## Result Rules

- Record `Pass`, `Fail`, `N-A`, or `Pending` in the host table with a short note.
- Link any captured log under `docs\evidence\m07\logs\`.
- If inline preedit or partial selection fails in a Tier-1 desktop host, do not
  mark M07 complete; classify the issue and keep the plan active.
- Until the holder-free live proof passes, do not mark M07 complete.
- If the live run cannot be performed because `YuneWindowsTSF.dll` is held by
  non-dev desktop apps, stop and retry from a holder-free session or after
  sign-out/reboot.
