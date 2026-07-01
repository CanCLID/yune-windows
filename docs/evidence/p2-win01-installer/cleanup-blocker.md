# P2-WIN02 Live Cleanup Blocker

Date: 2026-06-29T22:20:31.6034440-07:00

Machine state changed: true

Status: live-closeout-failed

The approved P2-WIN02 live closeout started from a clean elevated preflight,
packaged Yune inputs, and a clean install target. The live install/register
step succeeded, but the run failed before text-field smoke automation because
profile activation raced TSF profile propagation.

The live failure exposed two concrete issues:

1. The harness attempted `YuneWindowsProfileTool.exe --activate` immediately
   after install. `post-install-state.json` recorded durable machine
   registration, but the profile-tool state still reported
   `registered=false`; activation failed with `0x80004005`.
2. A later profile-tool check showed the profile had become registered and
   activation/deactivation then worked, confirming a bounded wait was required
   before activation. The source now adds that wait and a focused contract.

## Cleanup Outcome

The post-failure cleanup retry completed the unregister parts of cleanup:

- `profile_deactivated=true`
- `machine_registration_absent=true`
- `server_processes_stopped=true`
- current `server_process_count=0`
- current machine residue arrays are empty

Cleanup did not remove the install directory because the installed
`YuneWindowsTSF.dll` remains loaded by unrelated GUI processes. The first
post-failure cleanup result reported:

```text
MoveFileEx delayed delete failed for C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll: Win32 error 3
```

After the delayed-delete fix, the patched approved cleanup path was rerun. It
reported:

- `pending_delete_scheduled=true`
- `requires_reboot=true`
- `pending_delete_paths`:
  - `C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll`
  - `C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme`

`PendingFileRenameOperations` now contains the two Yune Windows delete entries.
The closeout cannot proceed until sign-out/reboot processes those pending
deletes and a fresh cleanup verification proves the install root is gone.

The remaining installed path is now only:

```text
C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll
```

## Module Holders

The elevated cleanup result reported these `YuneWindowsTSF.dll` holders after
the bounded removal attempts, and the current-state snapshot confirmed the
remaining holders:

```text
chrome[3472]
claude[10428]
Codex[5336]
explorer[11280]
NVIDIA Overlay[15276]
Signal[17360]
steamwebhelper[13980]
```

The cleanup flow intentionally did not kill these unrelated applications.

## Current Gate

The refreshed prep preflight is not ready for another live smoke:

- `ready_for_live_smoke=false`
- `install_dir_exists=true`
- `server_process_count=0`
- `machine_state_issues=[]`
- `filesystem_leftovers=[]`

Cleanup validation is also not clean:

- `pass=false`
- issue: `Install directory still exists`
- issue: `Installed YuneWindowsProfileTool.exe still exists` in the live-run
  cleanup snapshot before the post-failure retry removed it
- issue: `YuneWindows TSF profile is still registered` in the live-run cleanup
  snapshot before the post-failure retry unregistered it
- registry residue issues in the live-run cleanup snapshot before the
  post-failure retry removed machine registration

Because the profile tool has already been removed, profile state cannot be
verified again until the install root is cleaned and a fresh install/register
sequence runs.

The uninstaller source has also been tightened after this live attempt:

- profile activation now waits for the TSF profile to become visible before
  calling `--activate`;
- delayed-delete scheduling now uses explicit `MoveFileExW` with a null
  target and schedules reboot cleanup before `Remove-Item` touches a known
  locked TSF DLL. The patched cleanup result confirms this path now records
  `requires_reboot=true`.

Those source fixes are covered by:

- `tools/test-live-smoke-profile-registration-wait-contract.ps1`
- `tools/test-uninstall-locked-module-delayed-delete-contract.ps1`

## Evidence

- Elevated preflight launch:
  `docs/evidence/p2-win01-installer/elevated-preflight-launch-result.json`
- Elevated preflight transcript:
  `docs/evidence/p2-win01-installer/elevated-preflight-transcript-20260629-215720.txt`
- Prep preflight:
  `docs/evidence/p2-win01-installer/live-preflight.json`
- Post-failure prep preflight:
  `docs/evidence/p2-win01-installer/live-preflight-after-failed-cleanup.json`
- Elevated live launch:
  `docs/evidence/p2-win01-installer/elevated-live-smoke-launch-result.json`
- Elevated live transcript:
  `docs/evidence/p2-win01-installer/elevated-live-smoke-transcript-20260629-215801.txt`
- Live result:
  `docs/evidence/p2-win01-installer/result.md`
- Live command transcript:
  `docs/evidence/p2-win01-installer/commands.txt`
- Live uninstall result:
  `docs/evidence/p2-win01-installer/uninstall-result.json`
- Post-failure cleanup result:
  `docs/evidence/p2-win01-installer/post-failure-cleanup-result.json`
- Post-failure cleanup transcript:
  `docs/evidence/p2-win01-installer/post-failure-cleanup-transcript-20260629-220111.txt`
- Reboot-required cleanup launch:
  `docs/evidence/p2-win01-installer/post-reboot-required-cleanup-launch-result.json`
- Reboot-required cleanup result:
  `docs/evidence/p2-win01-installer/post-reboot-required-cleanup-result.json`
- Reboot-required cleanup transcript:
  `docs/evidence/p2-win01-installer/post-reboot-required-cleanup-transcript-20260629-221935.txt`
- Current state after live failure:
  `docs/evidence/p2-win01-installer/current-state-after-live-failure.json`
- Current state after reboot-required cleanup:
  `docs/evidence/p2-win01-installer/current-state-after-reboot-required-cleanup.json`
- Cleanup validation:
  `docs/evidence/p2-win01-installer/cleanup-validation.json`
- Closeout audit:
  `docs/evidence/p2-win01-closeout/audit.md`

## Next Required Fix

Sign out/reboot so Windows processes the scheduled delayed deletes, then verify
the install directory is gone before rerunning the approved live closeout from
the patched harness. Do not mark dogfood-ready until the closeout audit passes
after a clean install/register/type/diagnostics/uninstall/cleanup path.
