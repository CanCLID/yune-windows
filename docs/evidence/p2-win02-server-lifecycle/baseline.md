# P2-WIN02 Baseline

Status: planned

Known blocker from P2-WIN01: manual dogfood requires a separate
`tools\start-yune-windows-server.ps1` command before typing. Without the shared
server, the TSF DLL receives keystrokes but logs `server_query_failed` and does
not show candidates.

P2-WIN02 closes when:

- the installed TSF DLL starts or connects to `YuneWindowsServer.exe` without a
  separate operator server-start command;
- Notepad and Chromium smokes pass from a fresh install without manual server
  startup;
- uninstall writes structured cleanup evidence and reaches no-residue state
  after normal app shutdown or after an explicitly recorded sign-out/reboot
  when delayed delete is required for locked install-root files;
- closeout evidence remains under Yune Windows names only.
