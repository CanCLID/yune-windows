# M11D Activation, Toggle, Visibility, and Settings Repair Evidence

Status: implementation fixed and non-elevated gates passed on 2026-07-09 PT;
approval-gated installed proof is pending. This evidence does not close M11 or
unblock M10.

## Implemented reliability repair

- The server publishes a per-start `boot_id` and persisted monotonic `revision`.
  State mutations use paired compare-and-set expectations, temp-write/flush/
  atomic-replace persistence, explicit applied/unchanged/rejected/failure
  outcomes, and no revision advance for accepted no-ops.
- Raw TSF operation I/O runs on a capped heap-owned worker. The service STA uses
  one absolute wait deadline and never owns cancellation drain state. COM/UI/
  service objects stay on the originating apartment.
- Focus publication commits one global service/generation pair. Superseded,
  stale, wrong-apartment, and late-reply paths fail closed; final toolbar show is
  serialized against that committed identity.
- Hook and sink reports share an event-time-correlated physical token. A bounded
  ledger records consumed modifier/mouse state and rejects duplicates, stale
  generations, and expired delayed reports without a time-based dedupe guard.
- Pending rapid presses preserve generation-scoped parity, have a 1.5 s absolute
  deadline, and reconcile CAS conflicts or outcome-unknown replies without blind
  replay. The watchdog performs at most one CAS drive per tick.
- Toolbar eligibility requires state acknowledged for the current focus
  generation, a valid foreground-root owner, and current global identity. The
  steady visible path performs no periodic DComp render; eligible-but-hidden
  windows are reconciled.

## Settings cutoff repair

- Initial outer size is derived from a DPI-scaled design client and destination
  monitor work area, including scrollbar metrics.
- The native window is resizable with live-DPI work-area-capped minimum tracking.
  Horizontal/vertical scrolling keeps the fixed design canvas reachable on
  constrained displays and after `WM_DPICHANGED`.
- Settings mutations require a valid CAS mutation envelope. Raw named-pipe work
  is isolated on two capped heap-owned workers; the UI waits at most 750 ms and
  remains safe if a server transaction stalls.

## Current non-elevated verification

Passed from the combined working tree:

- `tools\build-tsf-shell.ps1`
- `tools\test-server-ime-state-protocol-contract.ps1`
- `tools\test-settings-window-smoke.ps1`
- `tools\test-language-bar-smoke.ps1`
- `tools\test-m06-key-path-fixes-contract.ps1`
- `tools\test-m11-ui-modernization-contract.ps1`
- `tools\test-m11c-dcomp-glass-toolbar-contract.ps1`
- `tools\test-m11d-activation-reliability-contract.ps1`
- `tools\test-m11d-activation-trace-contract.ps1`
- `tools\test-m11d-reliability-smoke.ps1`
- `tools\test-m11d-multiprocess-reliability-smoke.ps1`

The last smoke proves concurrent CAS arbitration using two independent clients
and runs the token/parity core in separate processes. It is not multiprocess TSF
activation, hook, dispatcher, foreground-owner, or toolbar proof.

## Remaining installed gate

After fresh approval, build/deploy once, record installed hashes, and verify
Notepad, Chromium, Explorer, and one Electron host. Acceptance still requires
visible-without-sacrificial-toggle activation, 50 paced exactly-once toggles,
rapid-burst parity, one foreground-owned toolbar, previous-host hiding within
250 ms, retained clone-free dragging, restart position persistence, and settings
usability at the exercised DPI/constrained size. Machine-state evidence must land
separately; until then M11/M11C/M11D remain active and M10 remains blocked.
