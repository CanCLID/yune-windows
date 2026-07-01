# P2-WIN03 Runtime Validation - 2026-07-01

## Verdict

P2-WIN03 post-review fixups are validated for the non-elevated development
loop. Installed-server reload with schema/user-data refresh passed on the live
installed path. Installed TSF reload is implemented and guard-proven, but the
full TSF DLL file swap was not performed because the active desktop session had
non-dev holders for `YuneWindowsTSF.dll`.

This is the intended safety boundary: the dev tool must not close Chrome,
Claude, Codex, Explorer, GitHub Desktop, Notepad, NVIDIA Overlay, Telegram, or
other user apps to force a DLL swap. A full installed TSF file-swap validation
requires a holder-free session, app closure, or sign-out.

## Evidence Files

- `install-preflight.json` - non-elevated install preflight.
- `install-register-result.json` and `install-register-transcript.txt` -
  approved install/register result.
- `profile-activate.json` and `profile-state-after-activate.json` - profile
  active after install.
- `dev-reload-server-refreshschema-output.txt` and
  `dev-reload-server-refreshschema-result.json` - installed server reload with
  `-RefreshSchema`; result passed and server readiness completed.
- `dev-test-window-state-validated.json` and
  `dev-test-window-validated-output.txt` - disposable Notepad state with real
  process identity and start time.
- `dev-reload-tsf-unsafe-holders-output.txt` and
  `dev-reload-tsf-unsafe-holders-result.json` - first TSF reload safe abort
  with non-dev holder list.
- `profile-deactivate-before-tsf-reload.json` - temporary profile deactivation
  used to check whether active profile state would release holders.
- `dev-reload-tsf-after-deactivate-output.txt` and
  `dev-reload-tsf-after-deactivate-result.json` - second TSF reload safe abort;
  existing GUI processes still held the DLL after deactivation.
- `profile-reactivate-after-tsf-reload-attempt.json` and
  `profile-state-final.json` - profile reactivated and final state verified.
- `dev-test-window-force-cleanup-result.json` - verified dev-owned Notepad
  process was stopped after the blocked reload attempt.
- `stale-test-window-cleanup-result.json` - generated Notepad test window from
  the pre-fix test attempt was closed.
- `final-machine-state.json` - final installed/profile/server state and empty
  Notepad process list after cleanup.

## Machine State

Final intended state for this validation is installed and active for dogfooding:

- `YuneWindowsProfileTool.exe --state` reported `registered: true` and
  `active: true`.
- Active profile state can drift after the evidence run; before typing, reselect
  Yune Windows in the target text field and verify active state again if needed.
- `YuneWindowsServer.exe` was running from
  `%LOCALAPPDATA%\Yune\WindowsIme\YuneWindowsServer.exe`.
- No delayed-delete cleanup, uninstall, AppVerifier, PageHeap, or verifier
  cleanup step was run.

## Follow-Up Boundary

Do not treat a forced installed TSF DLL swap as routine verification. Run it
only in a holder-free desktop session or after the user explicitly approves
closing the listed holder applications. The normal development loop should use
static contracts, scratch builds, REPL checks, installed-server reloads, and the
TSF reload safe-abort guard.
