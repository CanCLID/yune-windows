# P2-WIN01 Process Model

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: shared server/IPC remains the default model.

## Shape

- TSF DLL: `YuneWindowsTSF.dll`
- Server: `YuneWindowsServer.exe`
- Profile tool: `YuneWindowsProfileTool.exe`
- Candidate smoke tool: `YuneWindowsCandidateWindowSmoke.exe`
- Install root: `%LOCALAPPDATA%\Yune\WindowsIme`
- Pipe: `\\.\pipe\yune-windows-ime`
- Text service CLSID: `{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}`
- Profile GUID: `{3AE69B8D-19B4-4267-8F21-E239666D6632}`

## Rationale

The TSF text service delegates engine work to a shared server process so Yune's
runtime, session, and user data ownership stay outside per-app TSF loading.
The first inline candidate window is native. WebView2 is deferred to possible
settings or dictionary-panel work after typing evidence is proven.

## Evidence

- `tools\test-yune-server-ipc-smoke.ps1` passed with a process-specific pipe.
- `tools\test-tsf-shell-build.ps1` passed against the current packaged Yune
  output.
- Live TSF registration and foreground app smoke remain pending approval.
