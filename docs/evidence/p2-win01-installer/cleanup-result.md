# Cleanup Result

Date: 2026-06-30T21:02:07.9683487-07:00

Status: passed

Uninstall script: `tools\uninstall-yune-windows-ime.ps1`.

Uninstall result: `uninstall-result.json`.

Requires reboot: True

Cleanup state snapshot: `post-cleanup-state.json`.

Cleanup validation: `cleanup-validation.json`.

Pass: True

Recovery: delayed-delete cleanup was validated after reboot.

Review criteria:

- install directory removed unless `-KeepFiles` was used;
- installed `YuneWindowsProfileTool.exe` removed;
- no `YuneWindowsServer.exe` process remains;
- YuneWindows TSF profile state is absent or inactive;
- machine-state registry and PendingFileRenameOperations residue were checked;
- no YuneWindows filesystem leftovers remain in machine-level Windows directories.
