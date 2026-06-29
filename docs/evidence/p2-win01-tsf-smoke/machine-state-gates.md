# P2-WIN01 Machine-State Approval Gates

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-machine-state-approval-gates.ps1
```

Result: passed.

Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs.

Covered scripts:

- `install-yune-windows-ime.ps1`
- `uninstall-yune-windows-ime.ps1`
- `clear-yune-windows-machine-residue.ps1`
- `run-notepad-smoke.ps1`
- `run-chromium-smoke.ps1`
- `run-p2-win01-live-smoke.ps1`

The scripts refuse machine-state work without `ApprovedMachineStateChange`.
Install and registration are blocked before registration. Notepad automation, Chromium automation, full live-sequence orchestration, and machine residue cleanup are also blocked before approval.

The scripts also reject blank or approval-brief placeholder approval notes without `ApprovalNote`. The full live sequence rejects blank or approval-brief placeholder approval notes before post-approval context checks, command transcript writes, or cleanup.
