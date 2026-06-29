# Manual Dogfood Server Start Finding

Date: 2026-06-29

Context: after a manual install, profile activation reported registered and
active, but typing through the IME produced no visible output.

Observed state:

- `YuneWindowsServer.exe` was not running.
- `YuneWindowsProfileTool.exe --state` later reported the profile as
  `registered=true` and `active=false`, so activation can be lost between the
  setup command and the target text field.
- `%LOCALAPPDATA%\Yune\WindowsIme\logs\tsf-events.log` showed
  `profile_activate` followed by repeated `server_query_failed` entries for
  increasing buffer lengths.
- The TSF code path connects to `\\.\pipe\yune-windows-ime`; it does not launch
  the shared server when the pipe is missing.
- The Notepad and Chromium smoke scripts pass because they call
  `tools\start-yune-windows-server.ps1` before app automation.

Recovery used:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\start-yune-windows-server.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -InstallDir "$env:LOCALAPPDATA\Yune\WindowsIme" -WaitForReady
$tool = "$env:LOCALAPPDATA\Yune\WindowsIme\YuneWindowsProfileTool.exe"
& $tool --activate
& $tool --state
```

Result: the server process started from the install directory, profile state
returned `registered=true` and `active=true`, and manual Notepad dogfood worked.

Follow-up: P2-WIN02 should make shared-server lifecycle product-owned and rerun
the full live closeout without requiring a separate operator server-start
command.
