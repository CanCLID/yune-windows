# M11D - IME Activation, Toggle, and Toolbar Visibility Reliability

> **Status:** implementation fixed; approval-gated installed proof pending. The
> installed M11C clone/drag sub-gate passed. Boot-ID/revision CAS, bounded
> operation I/O, token/parity arbitration, identity-authoritative dispatch, and
> the settings DPI/resize/scroll repair now pass non-elevated gates. The combined
> hash-pinned four-host proof remains open, so M10 stays blocked.

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

## Goal and input semantics

One paced intended action must produce one observable result:

1. Activating the Yune profile makes the focused eligible TSF service current.
2. One paced lone-Shift press causes exactly one acknowledged, durably committed
   `ascii_mode` transition.
3. A current, eligible, foreground-owned service shows exactly one toolbar
   without a sacrificial toggle.
4. Focus loss hides the old toolbar within 250 ms and cannot let a late reply
   reclaim visibility.

"Exactly once" is not a license to silently discard a rapid second press. The
input contract distinguishes two cases:

| Input class | Required disposition |
| --- | --- |
| Paced lone Shift (the next press starts after the prior aggregate intent reaches a terminal outcome) | Every accepted token commits one revision and one Boolean transition. |
| Rapid burst while one intent is active | Accepted presses update a bounded, generation-scoped parity accumulator. Each detector report receives an admission/rejection disposition; the aggregate intent receives one terminal outcome. Final state equals initial state XOR accepted-press parity. |
| Autorepeat, modified chord, mouse/capture conflict, background owner, duplicate detector report, stale generation, or capacity overflow | Do not send IPC. Record one explicit rejection reason; never fail silently. |

The existing 250 ms `TryAcquireLoneShiftToggle` time guard is retired after the
token/dispatcher matrix is covered. Duplicate suppression is identity-based, not
elapsed-time-based, so a legitimate fast second press is not discarded merely
because it arrives within 250 ms.

## Non-goals and boundaries

- No Yune engine ABI change and no librime fallback.
- No `YuneWindowsUiHost.exe`, WebView2, Electron, or HTML toolbar.
- No M10 skin catalog, user import, or candidate-restyle work.
- No weakening of the fail-closed owner and foreground guards.
- No foreground key-path wait on server launch, worker join, or unbounded IPC
  retry.
- No claim that every intermediate visual state in a rapid burst must paint;
  paced exactly-once transitions and burst parity are separate acceptance lanes.

## State model to make explicit

M11D must stop treating these as one implicit Boolean:

| Layer | Authoritative question | Evidence needed |
| --- | --- | --- |
| Windows profile | Is the Yune keyboard profile active for the intended session/thread? | profile activation/deactivation event |
| TSF focus | Which `TextService` generation owns the focused document/context? | PID/TID, dispatcher identity, generation, context present |
| Shift detector | Which physical press/release token was seen, and what admission or rejection disposition did each detector assign? | process-start nonce, sequence, detector/disposition |
| Server state | Did one compare-and-set action commit against the expected server boot and revision? | boot ID, revision, desired value, outcome |
| Toolbar eligibility | Is the service current, owner valid, owner root foreground, state fresh, and capture/finalizer idle? | explicit show/hide reason |

Only the last layer may call `ShowWindow`. A stale service, stale generation,
unacknowledged state result, dead dispatcher, or invalid owner fails closed.

## Implementation order

### 1. Add privacy-safe multi-process activation tracing

- Give every event both a UTC timestamp and a monotonic timestamp, PID/TID, a
  process-start nonce, and a process-local sequence. Preserve the existing
  `tsf-events.log` diagnostics contract, but append each complete line with one
  cross-process-safe `FILE_APPEND_DATA` write so host records cannot interleave.
- Add focused-service generation, dispatcher identity, context availability,
  root-owner HWND, foreground-match result, hook health, server action/outcome,
  toggle token/disposition, and show/hide reason.
- Never record window titles, typed text, composition text, or arbitrary key
  sequences.
- Add a read-only capture helper that merges the timestamped process records
  with `capture-language-bar-topology.ps1` output.

This instrumentation lands first so every later change can be checked against
the installed Chromium/Explorer/Claude failure. Trace writing occurs after the
hook callback posts work; the low-level hook itself performs no file I/O.

### 2. Make focused-service eligibility identity-authoritative

- A service is eligible only when it is the current process-global focused
  service at the same activation generation.
- Supersession first publishes the new current service/generation and makes the
  old identity ineligible. Cleanup and hiding on the old apartment are best
  effort; late replies/messages must revalidate identity, and the foreground
  watchdog remains the bounded visibility fallback.
- Focus/context recovery records whether the owner came from the explicit
  context, `ITfThreadMgr::GetFocus` -> `ITfDocumentMgr::GetTop`, or the valid
  contextless cache.
- Profile activation/deactivation and TSF focus notifications schedule one
  idempotent reconciliation instead of relying on a later Shift press.
- Before dispatching a toggle and again before consuming its completion, require
  the same current service/generation plus a valid cached owner whose root equals
  the foreground root. This foreground-owner predicate rejects background host
  hooks before they can mutate shared server state.

### 3. Route lone Shift through one hook/sink dispatcher matrix

Use one physical token namespace per process start. Correlate the TSF key-sink
and low-level-hook reports for the same press/release sequence without using a
wall-clock dedupe window.

| Observation | Dispatcher path | Required result |
| --- | --- | --- |
| Current service receives the TSF sink sequence | Mark the token sink-handled on that service STA and dispatch it once if the foreground-owner predicate passes. |
| Hook sees a valid sequence that the current sink did not handle | Post the token and published service generation to the current hook dispatcher; the service STA revalidates identity, generation, owner, and foreground before accepting it. |
| Both sink and hook report the same sequence | The shared token receives one accepted disposition; the other detector is an explicit duplicate with no IPC. |
| A hook in a background process reports the sequence | The service dispatcher rejects it as `background_owner`; it cannot toggle the shared server. |
| Dispatcher is retired, destroyed, replaced, or belongs to another generation | Drop through the dead/stale-dispatcher escape, release message ownership, and perform no IPC or UI work. |

The low-level hook callback must stay lock-free and bounded: update fixed-size
atomics, read an atomically published dispatcher/generation snapshot, and make at
most one `PostMessage`. It performs no mutex acquisition, allocation, logging,
COM call, pipe I/O, `SendMessage`, or service `AddRef`. Hook install/uninstall,
target migration, last-callback/last-post health, and failure are observable from
the service STA. If hook health is bad, the TSF sink remains primary; hook
reinstallation is scheduled on an eligible service STA, never inside the hook.

The existing service message window remains the apartment boundary. Dispatcher
retirement first makes the generation ineligible; cleanup on the old apartment
is best effort and cannot prevent the new registration from becoming current.
A dead apartment may retain one harmless process-lifetime reference, but it
cannot retain eligibility, mutate state, or show a toolbar. No time-based
duplicate guard remains after the token matrix passes.

### 4. Commit state with boot-epoch/revision CAS

The current `op=set-option` request computes a value from a TSF-local cache and
the server currently truncates `ime-state.json` after mutating memory. M11D adds
an internal Windows IPC CAS path; it does not change the Yune engine ABI.

- Each server start creates a boot identity exposed by the internal protocol as
  `boot_id`. The persisted state carries a monotonic `revision`. Every state and
  error response returns the boot ID, revision, and current values.
- A Shift action sends `expect_boot_id`, `expect_revision`,
  `name=ascii_mode`, and the desired Boolean. The shared serial server is the
  only CAS authority.
- Define explicit server outcomes:

  | Outcome | Meaning |
  | --- | --- |
  | `applied` | CAS matched, state changed, durable commit succeeded, and revision advanced once. |
  | `unchanged` | CAS matched and the requested value was already current; no write or revision advance. |
  | `rejected` + `reason=revision_conflict` | Boot matched but revision differed; current state is returned. |
  | `rejected` + `reason=epoch_conflict` | Server restarted; current boot/state is returned and the stale CAS is not replayed unchanged. |
  | `persist_failed` | Durable replacement failed; memory, revision, and acknowledged value remain unchanged. |
  | `invalid` | Malformed/unsupported request; no state change. |

- Persist-temp-then-commit: construct a proposed state/revision snapshot,
  write a temp file in the state directory, flush and close it, atomically replace
  the live state file, and only then publish the proposed in-memory state and
  return `applied`. On failure, best-effort remove the temp file and keep the old
  in-memory/on-disk tuple. Reuse the transactional persistence helper for existing
  state mutations only where required to keep the shared revision truthful; do
  not change their user-visible semantics.
- A transport timeout is `outcome_unknown`, never permission to blind-retry.
  Mark the local state stale and perform a bounded `get-state` reconciliation.
  If the confirmed value already equals the generation-bound desired value, the
  intent converged; otherwise issue a fresh CAS from the confirmed tuple, up to
  the fixed total-attempt budget. A stale retry with its original tuple can only
  conflict, never apply twice. When the budget expires, emit an explicit
  unresolved disposition and never replay into a new focus generation.

Paced verification does not generate the next press until the current aggregate
intent reaches a terminal outcome. Runtime still accepts rapid valid presses and
folds them into the same generation-scoped parity intent, then recomputes the
desired value from confirmed server state.

### 5. Bound operation IPC and keep reconciliation on the TSF apartment

- Operation IPC uses a heap-owned worker, cancellable overlapped write/read, and
  one absolute deadline. The owning STA waits at most 100 ms for focus refresh or
  200 ms for a key-path CAS; after timeout the worker owns and drains
  `CancelIoEx` cleanup without exposing its buffers/handles to the STA.
- A state mutation performs at most one CAS in the key callback. Timeout marks
  state stale; the 250 ms focused-service watchdog performs the bounded
  `get-state` and at most one follow-up CAS per tick on the owning TSF apartment.
- Neither the operation worker nor the existing warm-up worker carries a
  `TextService*`, `ITfContext*`, COM interface, renderer object, or UI work. Only
  the owning service STA parses a completed operation response and reconciles
  apartment state.
- No service apartment launches the server, joins a worker, sleeps, performs an
  unbounded pipe transaction, or replays pending intent after its generation is
  superseded.

### 6. Centralize toolbar show reconciliation

- Replace scattered show attempts with one `ReconcileLanguageBarVisibility`
  decision that consumes current service identity/generation, focus/context,
  profile, owner/foreground, last confirmed server state, and capture/finalizer
  state.
- Record a stable reason code whenever the effective show/hide/fail-closed reason
  changes.
- Keep process-local and cross-process arbitration plus the 250 ms foreground
  watchdog as safety layers; they do not substitute for deterministic
  eligibility.
- Hidden per-thread toolbar HWNDs are allowed, but no hidden instance may retain
  eligibility to re-show after supersession.

## Non-elevated verification

Add focused tests for:

- timestamped multi-process trace schema, atomic record append, and privacy exclusions;
- profile activation before and after a helper creates its first TSF context;
- focus arriving while the server is cold, warming, ready, busy, or restarted;
- 100 paced lone-Shift sequences producing exactly 100 applied revisions;
- rapid bursts of odd/even lengths preserving final parity, assigning every
  detector report an admission/rejection disposition and the aggregate intent a
  terminal outcome, without relying on the retired 250 ms guard;
- duplicate sink/hook observation, modified/autorepeat/mouse rejection, hook
  failure/reinstall, and a lock-free hook callback contract;
- CAS `applied`, revision/epoch conflict, persistence failure,
  timeout-after-commit reconciliation, and bounded unresolved timeout;
- stale generations, dead-dispatcher handoff, focus loss during retry, and owner
  destruction;
- the foreground-owner predicate in same-process and cross-process cases; and
- all existing M08/M09/M11/M11C drag, click, focus, and topology contracts.

The current non-elevated concurrency smoke runs two independent clients against
an isolated server and proves one CAS apply plus one revision conflict, then runs
the process-local token/parity core in separate processes. It does not constitute
multiprocess TSF activation, dispatcher, hook, foreground-owner, or toolbar
proof. Those integration paths remain covered by focused language-bar/static
contracts and the approval-gated installed host matrix.

## M11 settings-panel closeout

This is M11 UI completion work, not M11D activation semantics and not M10. The
repair is implemented and non-elevated-smoke-covered:

- size the initial window from a DPI-aware desired client rectangle;
- make the panel resizable with a functional minimum client size;
- use live-DPI `WM_GETMINMAXINFO` and `WM_DPICHANGED` relayout plus horizontal/
  vertical scroll access whenever the fixed design canvas exceeds the client or
  monitor work area; larger windows may add whitespace and need no responsive
  redesign;
- extend the settings smoke/contract across the minimum size, a larger size, and
  100-200% DPI.

Installed visual/usability proof at the exercised DPI and constrained size is
still required before final hashes close. Do not change settings layout or
binaries midway through that approval-gated gate.

## Approval-gated installed acceptance

After M11D and the settings implementation land, build once, deploy once,
record the installed TSF/server/settings/default-skin hashes, and verify every
holder maps that build. Then run fresh Notepad, Chromium, Explorer, and Claude
(or another explicit Electron host). Accept only when:

- profile activation plus focusing an eligible text field makes the toolbar
  visible without a sacrificial Shift press;
- each of 50 lone-Shift presses, paced so the prior aggregate intent reaches a
  terminal outcome first, changes `ascii_mode` exactly once and the toolbar reflects
  the acknowledged state within 250 ms;
- short odd/even rapid bursts finish at the parity-correct state with no silent
  token loss or extra transition;
- 50 rapid four-host focus cycles show at most one toolbar, always owned by the
  foreground root, and hide the previous host within 250 ms;
- the existing clone gate remains green: stable HWND during drag, no visual
  copies/afterimages, no focus steal, no segment misclick, and no stuck capture;
- Explorer and Electron complete installed drag coverage;
- the final toolbar position survives focus changes and a host restart; and
- the settings panel opens without cutoff, resizes at the minimum and a larger
  size, and remains usable at the exercised DPI.

The 50 real four-host focus cycles belong only to this approval-gated installed
proof. Helper-process cycles are non-elevated implementation evidence, not a
substitute for the live host matrix.

## Publishing and milestone order

Publish independently buildable implementation slices and non-elevated
documentation/evidence on `main`; machine-state evidence remains a separate
commit after the approved installed run. Do not archive M11/M11C/M11D until the
full installed gate passes.

Execution order is fixed:

1. Complete the M11 settings and M11D runtime/non-elevated gate.
2. Pass the non-elevated settings, CAS, concurrent-client/process-local core, TSF, toolbar,
   and existing regression gates.
3. Build the combined tree once, deploy it, and pin installed hashes.
4. Complete the approval-gated four-host proof and archive M11/M11C/M11D
   together.
5. Begin M10 skin breadth and candidate-window work.
