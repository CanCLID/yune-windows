# M07 Holder-free Live Checklist

Status: complete. Inline preedit (F4) and partial-selection compose (F3) were
confirmed live in Chrome / Telegram / Zed on 2026-07-02, after the M06
pipe-security fix restored server reachability from sandboxed hosts and the DLL
was swapped in via `tools\dev\dev-swap-tsf-dll.ps1`.

This checklist remains the operator record. Do not force-close non-dev holder
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

| Host | Inline preedit | Partial selection advances | Final phrase commit | Raw Enter | Space candidate commit | M06 regressions | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Chromium browser | Pass | Pass | Pass (東突厥) | Pass | Pass | Pass (F1/F5/F6) | User-confirmed 2026-07-02 after pipe-security fix + DLL swap |
| Telegram Desktop | Pass | Pass | Pass | Pass | Pass | Pass (lone-Shift first-press) | User-confirmed 2026-07-02 |
| Zed | Pass | Pass | Pass | Pass | Pass | Pass | User-confirmed 2026-07-02 |
| Notepad | Pass | Pass | Pass | Pass | Pass | Pass | Baseline |

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

## Result

- Inline preedit (F4) and partial-selection compose (F3) passed in Chrome,
  Telegram, and Zed on 2026-07-02, with single-word commit, Space candidate
  commit, raw Enter (F6), and the M06 F1/F5 regressions all confirmed. M07 is
  complete; the plan is archived under `docs\plans\history\`.
