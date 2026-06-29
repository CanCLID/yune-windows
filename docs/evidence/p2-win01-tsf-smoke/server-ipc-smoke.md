# P2-WIN01 Server IPC Smoke

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-ipc-smoke.ps1
```

Result: passed.

Observed facts:

- `YuneWindowsServer.exe` was rebuilt against the current packaged Yune output.
- Product data was prepared from the Yune schema directory.
- The smoke used a process-specific Yune Windows pipe.
- Response reported `schema_id=jyut6ping3`.
- Response reported `candidate_count=5`.
- Response returned a non-raw commit for `ngohaig`.

This is non-elevated preflight evidence only. It does not prove TSF
registration, foreground Notepad input delivery, or profile activation.
