# M11D - IME Activation, Toggle, and Toolbar Visibility Reliability

> **Status:** next stop-the-line implementation slice. The installed M11C
> clone/drag sub-gate passed, but activation, lone-Shift state transition, and
> eligible-host toolbar visibility are not deterministic. M10 remains blocked.

## Why this is separate from the clone repair

The approved 2026-07-09 PT live run proved that a visible toolbar can remain one
foreground-owned HWND through repeated movement. It also exposed a different
failure before the four-host gate could close:

- Chromium required nine Shift attempts before its existing toolbar appeared;
- Explorer required five attempts and then eleven attempts on a repeat;
- several Shift taps produced no `ascii_mode` transition; and
- Claude loaded the current TSF DLL and received foreground composer focus, but
  no toolbar appeared after twelve attempts.

Clone topology and activation reliability are independent gates. M11D owns the
latter without reopening the native M11C renderer or moving candidate rendering
out of M10.

## Goal

One intended action must produce one observable result:

1. Activating the Yune profile makes the focused eligible TSF service current.
2. One lone-Shift press causes exactly one acknowledged `ascii_mode` transition.
3. A current, eligible, foreground-owned service shows exactly one toolbar
   without repeated toggles.
4. Focus loss hides the old toolbar within 250 ms and cannot let a late reply
   reclaim visibility.

## Non-goals and boundaries

- No Yune engine ABI change and no librime fallback.
- No `YuneWindowsUiHost.exe`, WebView2, Electron, or HTML toolbar.
- No M10 skin catalog, user import, or candidate-restyle work.
- No weakening of the fail-closed owner and foreground guards.
- No foreground key-path wait on server launch or an unbounded IPC retry.

## State model to make explicit

M11D must stop treating these as one implicit Boolean:

| Layer | Authoritative question | Evidence needed |
| --- | --- | --- |
| Windows profile | Is the Yune keyboard profile active for the intended session/thread? | profile activation/sink event |
| TSF focus | Which `TextService` generation owns the focused document/context? | PID/TID, generation, context present |
| Shift detector | Did this physical lone-Shift sequence already dispatch or toggle? | process-local sequence/token |
| Server state | Was one `set-option` request acknowledged with the expected revision/value? | bounded request result |
| Toolbar eligibility | Is the service current, owner valid, owner root foreground, and state fresh? | explicit show/hide reason |

Only the last layer may call `ShowWindow`. A stale service, stale generation,
unacknowledged state request, or invalid owner fails closed.

## Implementation order

### 1. Add privacy-safe activation tracing

- Extend structural events with event name, PID/TID, focused-service generation,
  context availability, root-owner HWND, foreground-match result, server request
  outcome, toggle sequence, and show/hide reason.
- Never record window titles, typed text, composition text, or arbitrary key
  sequences.
- Add a read-only capture helper that correlates activation events with
  `capture-language-bar-topology.ps1` output.

This instrumentation lands first so every later change can be checked against
the installed Chromium/Explorer/Claude failure.

### 2. Make focused-service eligibility identity-authoritative

- A service is eligible only when it is the current process-global focused
  service at the same activation generation.
- Superseding a service clears its focused eligibility and cached show request
  on its TSF apartment before or with hiding; a late server response cannot
  reclaim visibility.
- Focus/context recovery records whether the owner came from the explicit
  context, `ITfThreadMgr::GetFocus` -> `ITfDocumentMgr::GetTop`, or the valid
  contextless cache.
- Profile activation/deactivation and TSF focus notifications schedule one
  idempotent reconciliation instead of relying on a later Shift press.

### 3. Route lone Shift exactly once

- Give each low-level-hook press/release sequence a monotonically increasing
  token and post that token to the current hook window/service generation.
- Reject stale, duplicate, non-foreground-owner, shortcut-modified, mouse-drag,
  and already-handled TSF key-sink tokens.
- Keep one hook and one hook message target per process, but prove that hooks in
  background TSF processes cannot toggle the shared server state for a foreground
  host.
- Preserve `Ctrl+Shift+2`, `Ctrl+Shift+3`, ordinary shortcut, and key-up
  pass-through behavior.

### 4. Acknowledge or retry the state transition safely

- Do not treat an `ExistingServerOnly` failure as a completed toggle.
- If the server is warming or temporarily unavailable, queue at most one
  generation-bound desired transition, warm asynchronously, then retry with a
  short bounded timeout after readiness.
- Apply the toolbar state only from an acknowledged server response. Clear the
  pending token on focus loss, generation replacement, timeout, or deactivation.
- Coalesce repeated input while one transition is pending; never replay a stale
  toggle in a newly focused host.

### 5. Centralize toolbar show reconciliation

- Replace scattered show attempts with one `ReconcileLanguageBarVisibility`
  decision that consumes current service identity, focus/context, profile,
  owner/foreground, fresh server state, and capture/finalizer state.
- Record a stable reason code for every show, hide, or fail-closed decision.
- Keep process-local and cross-process arbitration plus the 250 ms watchdog as
  safety layers; they do not substitute for deterministic eligibility.
- Hidden per-thread toolbar HWNDs are allowed, but no hidden instance may retain
  eligibility to re-show after supersession.

## Non-elevated verification

Add focused tests for:

- profile activation before and after a host creates its first TSF context;
- focus arriving while the server is cold, warming, ready, or temporarily busy;
- 100 lone-Shift sequences producing exactly 100 acknowledged state changes;
- duplicate TSF-key-sink plus low-level-hook detection producing one change;
- multiple TSF services in one process and current services in multiple
  processes, including background hooks;
- stale generation replies, focus loss during retry, owner destruction, and
  activation/deactivation during retry;
- 50 Notepad <-> Chromium <-> Explorer <-> Electron focus cycles;
- at most one visible foreground-owned toolbar throughout; and
- all existing M08/M09/M11/M11C drag, click, focus, and topology contracts.

## Approval-gated installed acceptance

Run fresh Notepad, Chromium, Explorer, and Claude (or another explicit Electron
host) with the current installed hash. Accept only when:

- profile activation plus focusing an eligible text field makes the toolbar
  visible without a sacrificial Shift press;
- each of 50 lone-Shift presses changes `ascii_mode` exactly once and the toolbar
  reflects the acknowledged state within 250 ms;
- 50 rapid four-host focus cycles show at most one toolbar, always owned by the
  foreground root, and hide the previous host within 250 ms;
- the existing clone gate remains green: stable HWND during drag, no visual
  copies/afterimages, no focus steal, no segment misclick, and no stuck capture;
- Explorer and Electron complete installed drag coverage; and
- the final toolbar position survives focus changes and a host restart.

## Publishing and milestone order

Publish implementation, non-elevated evidence, and machine-state evidence as
separate scoped commits on `main`. Do not archive M11/M11C/M11D until the full
installed gate passes.

Execution order is fixed:

1. M11D activation/toggle/visibility reliability.
2. Complete four-host installed proof and archive M11/M11C/M11D together.
3. Begin M10 skin breadth and candidate-window work.
