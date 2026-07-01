# P2-WIN02 Live Closeout Attempt - 2026-06-30

Status: failed-pending-reboot-and-rerun

Fresh approval was used for the resumed live path:

- approval note: `User approved P2-WIN02 live install/register/smoke/uninstall/cleanup in this session.`
- launcher transcript:
  `docs/evidence/p2-win01-installer/elevated-live-smoke-transcript-20260630-164736.txt`
- launcher result:
  `docs/evidence/p2-win01-installer/elevated-live-smoke-launch-result.json`
- closeout audit:
  `docs/evidence/p2-win01-closeout/audit.json`

Post-reboot preflight was clean before the run: the install directory was
absent, no installed TSF DLL remained, no `YuneWindowsServer.exe` process was
running, and `PendingFileRenameOperations` had no Yune Windows entries.

The run reached install/register and profile activation. The Notepad smoke then
failed before Chromium or diagnostics:

- Notepad result:
  `docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md`
- `profile_active_verified_before_typing: True`
- `product_owned_server_start_observed: True`
- observed committed text: empty
- structural summary:
  `server_launch_attempt=1, server_launch_started=1, server_launch_timeout=2`

The smoke proved the TSF DLL can start the installed product-owned server, but
the first cold input sequence still captured and committed too early for a
fresh server. The smoke's own new-log-line evidence did not see
`candidate_update` or `commit_text` before the capture. This is a smoke harness
gap around the intended product behavior: launch-triggering keystrokes can be
eaten, and later keystrokes should connect after readiness.

Follow-up fix in this branch:

- added a shared `Wait-YuneWindowsProductOwnedServerReady` helper that polls the
  installed server process and new structural log lines for `server_launch_ready`
  or `candidate_update`;
- changed Notepad and Chromium smokes to send a product-owned server launch
  probe, wait for readiness, reset the target, re-verify the profile is active,
  then type the real `ngohaig` commit input;
- added the exact evidence key
  `product_owned_server_ready_observed`;
- updated `tools/test-product-owned-server-smoke-contract.ps1` so the smokes
  cannot regress to one-second fixed-sleep cold typing.

Verification after the harness fix:

- `tools/test-product-owned-server-smoke-contract.ps1` passed after first
  failing RED on the missing readiness evidence key;
- focused smoke contracts passed:
  `tools/test-cold-profile-selection-contract.ps1`,
  `tools/test-start-server-readiness-contract.ps1`, and
  `tools/test-tsf-server-cold-start-readiness-contract.ps1`;
- the non-elevated build/smoke/contract suite from the active P2-WIN02 plan
  passed;
- `tools/audit-p2-win01-closeout.ps1` wrote an incomplete audit, as expected;
- `git diff --check` passed.

Cleanup scheduled delayed deletes under
`C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme` and requires sign-out or
reboot before another live closeout attempt. Structured cleanup result:

- `requires_reboot: true`
- `pending_delete_scheduled: true`
- locked module holders recorded:
  `claude`, `Codex`, `explorer`, `L-Connect 3`, `NVIDIA Overlay`
- pending-delete paths are all under the approved install root.

Do not mark P2-WIN02 or dogfood readiness complete from this run. The next live
step is sign-out/reboot, verify the install directory and pending-delete entries
are gone, then rerun one approved full live closeout with the patched smoke
readiness gate.
