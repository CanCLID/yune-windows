# P2-WIN02 Live Closeout Attempt - 2026-06-29

Status: failed-pending-reboot-and-rerun

Fresh approval was used for the resumed live path:

- approval note: `User approved P2-WIN02 live install/register/smoke/uninstall/cleanup in this session.`
- launcher transcript:
  `docs/evidence/p2-win01-installer/elevated-live-smoke-transcript-20260629-223512.txt`
- closeout audit:
  `docs/evidence/p2-win01-closeout/audit.json`

The run reached install/register and profile activation. The Notepad smoke then
failed before Chromium or diagnostics:

- Notepad result:
  `docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md`
- `profile_active_verified_before_typing: True`
- `product_owned_server_start_observed: True`
- observed committed text: empty
- structural summary:
  `server_launch_attempt=3, server_launch_exited=1, server_launch_pending=3, server_launch_started=3, server_launch_timeout=10, server_query_connect_failed=4, server_query_failed=4`

The failure is consistent with cold server readiness taking longer than the
TSF post-launch readiness probe. A non-elevated diagnostic readiness measurement
against a temp build reached a usable pipe response in about `7482ms`, while the
TSF source used `kServerLaunchReadyWaitMs = 750`.

Follow-up fix in this branch:

- added `tools/test-tsf-server-cold-start-readiness-contract.ps1`
- raised `kServerLaunchReadyWaitMs` to `15000`
- full non-elevated `tools/test-*.ps1` suite passed: 203 scripts, 0 failures
- `git diff --check` passed

Cleanup scheduled delayed deletes under
`C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme` and requires sign-out or
reboot before another live closeout attempt. Current post-run residue:

- install directory exists
- installed `YuneWindowsTSF.dll` exists
- installed server process count is 0
- `PendingFileRenameOperations` contains Yune Windows install-root entries

Do not mark P2-WIN02 or dogfood readiness complete from this run. The next live
step is sign-out/reboot, verify the install directory and pending-delete entries
are gone, then rerun the approved live closeout with the patched TSF readiness
probe.
