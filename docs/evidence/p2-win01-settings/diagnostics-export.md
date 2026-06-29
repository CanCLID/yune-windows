# P2-WIN01 Diagnostics Export Preflight

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: diagnostics export tooling exists; registered-session export evidence
is pending approved live run.

Evidence:

- `tools\export-yune-windows-diagnostics.ps1`
- `tools\test-diagnostics-export.ps1`
- `tools\test-diagnostics-export-log-privacy.ps1`
- `tools\test-live-smoke-diagnostics-bundle-validator.ps1`

Live closeout requires a support bundle under
`docs\evidence\p2-win01-settings\registered-session-diagnostics` after the
profile is installed, registered, active, and app smoke has produced structural
candidate and commit events. The bundle must include structural diagnostics
logs only and must not contain typed content.
