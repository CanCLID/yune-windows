# P2-WIN01 Compatibility Matrix

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: pending-approved-live-run

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
| fresh install | install result and pre/post install snapshots | pending approved live run |
| TSF registration | registered Yune Windows profile state | pending approved live run |
| profile activation | active Yune Windows profile state | pending approved live run |
| Notepad | committed non-raw Yune candidate text | pending approved live run |
| Chromium | one Chromium text field commits through Yune | pending approved live run |
| diagnostics export | structural support bundle without typed-content logs | pending approved live run |
| uninstall | approved uninstaller transcript | pending approved live run |
| cleanup verification | no install dir, TSF DLL, server process, TSF profile, or machine residue remains | pending approved live run |

This matrix does not close P2-WIN01. It prepares the dogfood evidence target
for the approved live path.
