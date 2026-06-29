# Cleanup Result

Date: 2026-06-29T18:39:51.3661764-07:00

Status: passed

Uninstall script: `tools\uninstall-yune-windows-ime.ps1` followed by approved
manual cleanup after the TSF DLL was unloaded.

Cleanup state snapshot: `post-cleanup-state.json`.

Cleanup validation: `cleanup-validation.json`.

Pass: True

Review criteria:

- install directory removed unless `-KeepFiles` was used;
- installed `YuneWindowsProfileTool.exe` removed;
- no `YuneWindowsServer.exe` process remains;
- YuneWindows TSF profile state is absent or inactive;
- machine-state registry and PendingFileRenameOperations residue were checked;
- no YuneWindows filesystem leftovers remain in machine-level Windows
  directories.
