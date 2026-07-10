# M11 Activation and State Reliability Plan

> **Status:** implementation complete; focused non-elevated checks pass;
> expanded pre-deployment verification and installed acceptance remain pending.
> Implementation last changed at `f67b9c1`; the older pre-rebaseline
> source/evidence baseline remains `337b9bd`. Pin the clean source and artifact
> hashes used for deployment and record that provenance. No installed result
> for this baseline is claimed yet. M12 and M13 remain blocked until both the redefined
> [M10 native UI presentation closeout](m10-native-ui-presentation-closeout.md)
> and this M11 pass their separate acceptance gates.

## Purpose

Make Windows profile activation, focused-service identity, lone-Shift state
transition, and toolbar show eligibility deterministic across real TSF hosts.
One paced intended action must produce one observable, durably acknowledged
result without relying on a sacrificial toggle, stale local state, or an
unbounded foreground wait.

This scope is distinct from toolbar presentation and clone repair. The approved
2026-07-09 PT run proved that the earlier build could retain one
foreground-owned toolbar HWND through repeated drag without visual copies. The
same run separately found that Chromium required nine Shift attempts, Explorer
required five and then eleven, several taps did not change `ascii_mode`, and an
Electron host showed no toolbar after twelve attempts. M10 owns the native UI,
settings sizing, toolbar presentation, and clone-free interaction invariants;
M11 owns the activation and acknowledged-state path that decides whether that
toolbar is eligible to appear.

## Milestone boundary

M11 owns:

- Windows profile and TSF focus-generation identity;
- sink/hook correlation for physical lone-Shift input;
- generation-scoped rapid-input parity and terminal dispositions;
- server boot-ID/revision compare-and-set and transactional persistence;
- deadline-bounded operation IPC and outcome-unknown reconciliation;
- privacy-safe activation tracing; and
- deterministic, fail-closed toolbar show eligibility and old-host hiding.

M11 does not own:

- M10 Cantonese localization, settings theming, DPI-aware initial sizing,
  resizing, scrolling, or installed settings usability;
- M10 DirectComposition/Acrylic presentation, static visual fallback,
  movement-only drag, clone-free HWND topology, or toolbar position behavior;
- M12 skin catalog, user import, manifest breadth, or revisioned skin content;
- M13 candidate-window restyling, localization, fallback, or performance; or
- a Yune engine ABI change, librime fallback, WebView2, Electron/HTML UI, or a
  `YuneWindowsUiHost.exe` process.

M11 consumes M10's native toolbar as an already-defined surface. It must retest
the affected M10 ownership, clone, drag, no-focus-steal, and persistence
invariants on the frozen combined build, but those checks remain M10 regression
evidence and are not absorbed into M11 scope. Any product build/package input
change after M10 proof requires the affected M10 regressions to be rerun before
that new candidate can close M11 or unblock M12; documentation/test/evidence-
only changes follow the provenance rule in M10.

No Yune engine ABI change is introduced.

## Required behavior

1. Activating the Yune profile and focusing an eligible text field publishes the
   correct current `TextService` generation and shows its toolbar without a
   sacrificial Shift press.
2. One paced lone-Shift press causes exactly one acknowledged, durably committed
   `ascii_mode` transition.
3. A rapid valid burst is not silently deduplicated: accepted presses fold into
   a bounded, generation-scoped parity intent whose final state equals the
   initial state XOR accepted-press parity.
4. Only a current service with fresh acknowledged state and a valid owner whose
   root is foreground may show the toolbar.
5. Focus loss makes the old generation ineligible immediately, hides its toolbar
   within 250 ms, and prevents late messages or replies from reclaiming
   visibility.

| Input class | Required disposition |
| --- | --- |
| Paced lone Shift, after the prior aggregate intent reaches a terminal outcome | One accepted token, one durable revision, one Boolean transition. |
| Rapid presses while an intent is active | Record every detector report's admission or rejection; fold accepted presses into generation-scoped parity and produce one terminal aggregate outcome. |
| Autorepeat, modified chord, mouse/capture conflict, duplicate detector report, background owner, stale generation, expired intent, or capacity overflow | Send no mutation IPC and record an explicit rejection reason. |

Duplicate suppression is token- and generation-based, never a wall-clock guard
that can discard a legitimate fast second press.

## Explicit state model

| Layer | Authoritative question | Required evidence |
| --- | --- | --- |
| Windows profile | Is the Yune profile active for the intended session and thread? | activation/deactivation event |
| TSF focus | Which service generation owns the focused document/context? | PID/TID, dispatcher identity, generation, context availability |
| Shift detector | Which physical token did the sink and hook observe, and how was each report disposed? | process nonce, token/sequence, detector, disposition |
| Server state | Did the desired value commit against the expected server boot and revision? | boot ID, revision, desired value, explicit outcome |
| Toolbar eligibility | Is identity current, state fresh, owner valid, owner root foreground, and capture/finalization safe? | stable show/hide/fail-closed reason |

Only the final layer may request a show. A stale generation, dead dispatcher,
unacknowledged state result, invalid owner, or foreground mismatch fails closed.

## Implemented reliability contract

### Focus-generation authority

- Focus activation publishes one process-global service/generation pair before
  best-effort retirement of the old apartment.
- Every dispatcher message and late server response revalidates that exact
  identity before mutating state or reconciling visibility.
- Context recovery records whether the owner came from the explicit context,
  `ITfThreadMgr::GetFocus` -> `ITfDocumentMgr::GetTop`, or the last valid
  focused cache.
- Profile/focus notifications schedule idempotent reconciliation; visibility no
  longer depends on a later Shift press.
- Before dispatch and before completion consumption, the service must still be
  current and its cached owner root must equal the foreground root.

### Physical-token arbitration

- The TSF key sink is primary and the low-level hook is a fallback observation
  path; both report into one process-start token namespace.
- A shared bounded ledger gives one accepted disposition to a physical token and
  marks the other detector report as a duplicate without IPC.
- The hook callback stays lock-free and bounded: fixed-size atomic state, one
  published dispatcher/generation snapshot, and at most one `PostMessage`. It
  performs no allocation, logging, mutex, COM, pipe I/O, `SendMessage`, or
  service `AddRef`.
- Hook health and target migration are observable on the owning STA. A failed
  hook is reinstalled from an eligible service STA while the sink remains
  primary.
- Retired or dead dispatchers cannot retain eligibility, mutate shared state, or
  show a toolbar. A pending parity intent has a 1.5-second absolute deadline and
  never crosses into a new focus generation.

### Boot-ID/revision CAS

- Every server start publishes a `boot_id`; persisted state carries a monotonic
  `revision`. State and error responses return the current tuple.
- A mutation sends paired `expect_boot_id` and `expect_revision` fields. The
  serial server is the only compare-and-set authority.
- `applied` means a durable state change and one revision advance; `unchanged`
  performs no write or advance; revision/epoch conflicts return current state;
  `persist_failed` and `invalid` change nothing.
- Persistence constructs a proposed snapshot, writes and flushes a temporary
  file, atomically replaces the live file, and only then publishes the new
  in-memory tuple.
- A timeout is `outcome_unknown`, never permission for a blind retry. The STA
  performs bounded `get-state` reconciliation and may issue a fresh CAS only
  from the confirmed tuple and within the fixed attempt budget.

### Bounded IPC and reconciliation

- Heap-owned workers perform cancellable overlapped operation I/O with one
  absolute deadline. The owning STA waits at most 100 ms for focus refresh or
  200 ms for a key-path CAS; timed-out workers own cancellation drain state.
- A key callback performs at most one CAS. The 250 ms focused-service watchdog
  performs bounded reconciliation and at most one follow-up CAS per tick.
- Workers carry no `TextService*`, `ITfContext*`, COM interface, renderer, or UI
  work. Parsing and service-state reconciliation remain on the originating STA.
- No service apartment launches the server, joins a worker, sleeps, performs an
  unbounded pipe transaction, or replays intent after supersession.

### Visibility and diagnostics

- One `ReconcileLanguageBarVisibility` decision consumes current identity,
  focus/context, profile state, owner/foreground, confirmed server state, and
  capture/finalizer state.
- Process-local/cross-process arbitration and the 250 ms foreground watchdog are
  safety layers, not substitutes for deterministic eligibility. The steady
  visible watchdog path performs no periodic DComp render.
- Hidden per-thread toolbar HWNDs are allowed, but no hidden stale instance may
  remain eligible to re-show.
- Trace records use UTC and monotonic timestamps, PID/TID, process-start nonce,
  process-local sequence, focus generation, dispatcher/context/owner state,
  hook health, action/outcome, token/disposition, and show/hide reason.
- Each line is appended with one cross-process-safe `FILE_APPEND_DATA` write.
  The trace never records window titles, typed text, composition text, or
  arbitrary key sequences; the hook callback itself performs no file I/O.

## Non-elevated evidence and remaining pre-deployment matrix

The `f67b9c1` implementation baseline passes these focused build, state,
token/parity, trace, visibility, and concurrency checks:

- `tools/build-tsf-shell.ps1`;
- `tools/test-server-ime-state-protocol-contract.ps1`;
- `tools/test-m06-key-path-fixes-contract.ps1`;
- `tools/test-m11d-activation-reliability-contract.ps1`;
- `tools/test-m11d-activation-trace-contract.ps1`;
- `tools/test-m11d-reliability-smoke.ps1`; and
- `tools/test-m11d-multiprocess-reliability-smoke.ps1`.

The expanded concurrency smoke also proves 100 paced server CAS transitions,
timeout-after-commit reconciliation, persistence-failure rollback/recovery,
and boot-epoch rejection. It does not prove multiprocess TSF activation, hook,
dispatcher, foreground-owner, or toolbar behavior. The remaining helper and
approval-gated installed host matrices remain authoritative for those paths.

Before a deployment is graded as **M11 acceptance**, expand or add non-elevated
coverage for the cases required by the legacy M11D design but not fully closed
by the current core/concurrency smokes:

- helper profile activation before and after its first TSF context;
- focus while the server is cold, warming, ready, busy, and restarted;
- 100 paced end-to-end Shift actions producing 100 applied revisions, not only
  100 token-arbiter claims;
- odd/even rapid bursts, sink/hook duplicates, modified/repeat/mouse rejection,
  hook failure/reinstall, and explicit terminal dispositions;
- CAS applied/revision-conflict/epoch-conflict/persistence-failure/
  timeout-after-commit reconciliation and bounded unresolved timeout; and
- stale generations, dead dispatchers, owner destruction, focus loss during
  retry, foreground-owner rejection, and trace privacy/atomic append.

These are required M11 pre-deployment verification gaps. An M10-only
presentation/settings deployment may proceed under the M10 plan, but it cannot
claim any M11 result. Do not promote the current process-local core and
isolated-server CAS/fault smoke into a claim that they are already end-to-end
multiprocess TSF proof.

M11 also reruns M10's language-bar, DComp/backdrop, drag, click, ownership, and
topology regressions. Passing them protects the dependency; it does not move
their implementation or acceptance ownership into M11.

## Approval-gated installed acceptance

Build and deploy a frozen M11 candidate; it may reuse an already deployed M10
candidate only when the exact source and artifact hashes are unchanged. Record
source and installed TSF/server hashes, verify every holder maps that build,
and use fresh Notepad, Chromium, Explorer, and one explicit Electron host such
as Claude.
Accept M11 only when:

- profile activation plus eligible text focus shows the toolbar without a
  sacrificial toggle;
- each of **50 paced lone-Shift presses**, with the next starting only after the
  prior aggregate intent is terminal, changes `ascii_mode` exactly once and the
  toolbar reflects the acknowledged value within 250 ms;
- short odd/even rapid bursts finish in the parity-correct state without a
  silent token loss or extra transition;
- 50 rapid four-host focus cycles retain at most one visible toolbar, always
  owned by the foreground root, and hide the previous host within 250 ms;
- profile activation, toolbar show/hide reconciliation, every lone-Shift action,
  and every focus cycle leave typing focus in the intended text field and never
  activate the toolbar or settings window;
- stale/late replies, focus loss during reconciliation, server restart, and host
  restart cannot restore an ineligible generation; and
- the activation trace assigns stable reasons and terminal outcomes without
  collecting prohibited content.

The same frozen run must regression-check M10's stable HWND during drag, absence
of copies/afterimages, no focus steal or segment misclick, no stuck capture, and
position persistence across focus and host restart in the hosts required by the
M10 presentation gate. The four-host M11 matrix expands activation and
visibility coverage; it does not silently expand or absorb M10's presentation
host matrix. M10 regression results close or preserve M10 gates, not M11
presentation scope. M10's settings visual/usability proof is likewise recorded
under M10 and is not part of the M11 verdict.

## Completion and downstream order

M11 closes only when the frozen baseline passes its four-host installed
acceptance and machine-state evidence under `docs/evidence/m11-activation/`
records exact hashes and verdicts without overwriting the preserved legacy
`docs/evidence/m11/` summary.
The legacy M11D source plan remains in history as implementation provenance;
move this canonical M11 plan to history only after the installed gate passes.
Do not treat non-elevated helper processes as installed proof.

M10 and M11 have separate verdicts and may share one frozen deployment/evidence
session. Neither M12 skin breadth/catalog work nor M13 candidate-presentation
work begins until **both M10 and M11 pass**. M11 provides reliable revisioned
state transport to M12, while M10 provides the reusable native presentation
foundation to M13; neither downstream milestone may borrow the other lane's
evidence.
