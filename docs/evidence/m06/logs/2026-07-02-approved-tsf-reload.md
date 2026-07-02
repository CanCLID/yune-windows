# 2026-07-02 Approved TSF Reload

Scope: user-approved, non-elevated M06/M07 installed TSF DLL reload with
Explorer restart enabled. No elevated install/register/unregister/cleanup,
AppVerifier, PageHeap, or registry steps were run.

## Preflight

- Command:
  `tools\dev\dev-live-closeout-preflight.ps1 -RestartExplorerPlanned`
- Result: passed.
- Installed TSF DLL:
  `C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll`
- All holders: none.
- Blocking holders: none.

## TSF DLL Reload

- Command: `tools\dev\dev-reload-tsf.ps1 -RestartExplorer`
- Result: passed.
- Build output root:
  `C:\Users\laubonghaudoi\AppData\Local\Temp\yune-windows\dev-reload-tsf-11928-b72d8d2c\build`
- Installed DLL backup:
  `C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll.dev-backup-20260702-091308`
- The script copied `YuneWindowsTSF.dll` into the installed path and validated
  that the installed hash matched the scratch build.
- The script started dev-owned Notepad PID 21524 with state file
  `C:\Users\LAUBON~1\AppData\Local\Temp\yune-windows\dev-test-window.json`.

## Post-swap Snapshot

- `tools\collect-m06-compatibility-environment.ps1` refreshed
  `docs\evidence\m06\environment.json`.
- Installed `YuneWindowsTSF.dll` SHA-256:
  `280AC71822F213528B05B18D88BB37B18ABA0EE7B8EA914978B94CC831559771`.
- Installed `YuneWindowsServer.exe` SHA-256:
  `0964658B40BF5B04C3FA959922B83FE1F1C0681CED21F85A1A5E63531266A9F5`.
- `YuneWindowsProfileTool.exe --state` reported the profile registered but not
  active at environment capture time.
- `tools\capture-m06-tsf-events-window.ps1 -Label m06-m07-post-tsf-swap`
  captured `docs\evidence\m06\logs\m06-m07-post-tsf-swap-tsf-events.md`.

## Remaining Proof

- This reload proves the current build is installed in the TSF DLL path, but it
  does not fill the M06 host matrix or M07 live checklist.
- The next operator step is to select Yune Windows in the dev Notepad or target
  host, then record the M06 Tier-1 host matrix and M07 inline composition
  checklist.
