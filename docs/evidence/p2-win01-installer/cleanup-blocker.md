# P2-WIN01 Cleanup Blocker

Date: 2026-06-27T14:56:19.7070338-07:00

Resolved: 2026-06-29T18:39:51.3661764-07:00

Machine state changed: true

Status: recovered-after-manual-dll-unload

The approved live run installed and registered Yune Windows, completed the
Notepad smoke, completed the Chromium smoke, exported diagnostics, then failed
during cleanup validation because the install directory still existed.

## Passed Before Cleanup

- Install and TSF registration completed.
- Notepad smoke passed: `docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md`.
- Chromium smoke passed: `docs/evidence/p2-win01-tsf-smoke/chromium-smoke-result.md`.
- Diagnostics export passed:
  `docs/evidence/p2-win01-settings/registered-session-diagnostics/yune-windows-diagnostics-20260627-144052.zip`.
- Profile state after cleanup failure was verified as `registered=false` and
  `active=false`.
- `YuneWindowsServer.exe` process count after cleanup failure was zero.
- Machine residue arrays after cleanup failure were empty.

## Remaining Residue

Remaining path:

```text
C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme\YuneWindowsTSF.dll
```

Cleanup failed with:

```text
Failed to remove YuneWindows install directory after 20 attempts: Access to the path 'YuneWindowsTSF.dll' is denied.
```

The uninstaller reported these module holders:

```text
chrome[21132]
claude[17452]
Codex[11324]
explorer[13772]
GitHubDesktop[24976]
NVIDIA Overlay[4280]
Signal[25736]
steamwebhelper[23524]
Telegram[9708]
```

Because the current Codex process was one of the module holders, the original
live run could not verify complete install-directory removal while staying
open.

## Recovery

On 2026-06-29, the locked `YuneWindowsTSF.dll` was manually removed after the
DLL was unloaded. The remaining `logs` directory under
`C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme` was then removed under
the approved cleanup verification flow.

Recovery evidence:

- install directory exists: `false`
- TSF DLL exists: `false`
- `YuneWindowsServer.exe` process count: `0`
- cleanup validation: `pass=true`
- profile state: `registered=false`, `active=false`
- machine residue arrays: empty

## Evidence

- Live result: `docs/evidence/p2-win01-installer/result.md`
- Cleanup result: `docs/evidence/p2-win01-installer/cleanup-result.md`
- Cleanup validation: `docs/evidence/p2-win01-installer/cleanup-validation.json`
- Current state snapshot:
  `docs/evidence/p2-win01-installer/current-state-after-cleanup-failure.json`
- Post-DLL-removal snapshot:
  `docs/evidence/p2-win01-installer/current-state-after-manual-dll-removal.json`
- Final cleanup snapshot:
  `docs/evidence/p2-win01-installer/post-cleanup-state.json`
- Elevated transcript:
  `docs/evidence/p2-win01-installer/elevated-live-smoke-transcript-20260627-144002.txt`
