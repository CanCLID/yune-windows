# P2-WIN01 Candidate Window Build Preflight

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1
```

Result: passed.

Observed artifacts:

- `YuneWindowsTSF.dll`
- `YuneWindowsServer.exe`
- `YuneWindowsProfileTool.exe`
- `YuneWindowsCandidateWindowSmoke.exe`

The native candidate-window self-test reported `candidate window smoke passed`.
This proves the native candidate-window code builds and its local smoke runs.
It does not prove live TSF positioning, foreground display, or app commit
behavior. Those remain pending approved Notepad and Chromium smokes.
