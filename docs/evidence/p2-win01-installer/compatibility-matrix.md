# P2-WIN01 Compatibility Matrix

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: covered-by-p2-win02-live-closeout

Compatibility environment source: `compatibility-environment.json`

## Target

- Target id: `P2-WIN01-WIN11-X64`
- OS: Microsoft Windows 11 Pro
- OS version: `10.0.26200`
- OS build: `26200`
- OS architecture: `64-bit`
- Process architecture: `64-bit`
- Install dir: `C:\Users\laubonghaudoi\AppData\Local\Yune\WindowsIme`
- Browser: `C:\Program Files\Google\Chrome\Application\chrome.exe`

## Required Live Coverage

| Area | Required evidence | Current status |
| --- | --- | --- |
| fresh install | install result and pre/post install snapshots | covered by `docs/evidence/p2-win01-installer/result.md`, `pre-install-state.json`, and `post-install-state.json` |
| TSF registration | registered Yune Windows profile state | covered by `docs/evidence/p2-win01-installer/result.md` and `post-install-state.json` |
| profile activation | active Yune Windows profile state | covered by `docs/evidence/p2-win01-installer/result.md`, `docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md`, and `docs/evidence/p2-win01-tsf-smoke/chromium-smoke-result.md` |
| Notepad | committed non-raw Yune candidate text | covered by `docs/evidence/p2-win01-tsf-smoke/notepad-smoke-result.md` |
| Chromium | one Chromium text field commits through Yune | covered by `docs/evidence/p2-win01-tsf-smoke/chromium-smoke-result.md` |
| diagnostics export | structural support bundle without typed-content logs | covered by `docs/evidence/p2-win01-settings/registered-session-diagnostics/yune-windows-diagnostics-20260630-203148.zip` |
| uninstall | approved uninstaller transcript | covered by `docs/evidence/p2-win01-installer/elevated-live-smoke-transcript-20260630-203015.txt` and `docs/evidence/p2-win01-installer/uninstall-result.json` |
| cleanup verification | no install dir, TSF DLL, server process, TSF profile, or machine residue remains | covered by `docs/evidence/p2-win01-installer/cleanup-validation.json` and `docs/evidence/p2-win02-server-lifecycle/live-closeout-20260630-203015.md` |

This matrix is covered by the recovered P2-WIN02 live closeout on the
`P2-WIN01-WIN11-X64` target. Dogfood package hardening remains open.
