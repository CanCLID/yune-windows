# M10 Native UI Presentation Closeout

> **Status:** corrective candidate `589bc3d` deployed; restart and installed acceptance
> pending.
>
> M10 is the canonical milestone for the native Cantonese UI, toolbar
> presentation, and settings-window usability work previously planned and
> evidenced under M11/M11C, plus only the settings DPI/resize/scroll portion of
> M11D. Implementation last changed at `589bc3d`; the older pre-rebaseline
> source/evidence baseline remains `337b9bd`. The durable candidate manifest is
> recorded and its measured non-elevated preflight passes, but no post-restart
> or installed acceptance proof exists yet for this candidate.

## Outcome

Close the first-party native presentation layer with two independently recorded
installed results:

1. a foreground-owned toolbar that remains one stable, clone-free visual while
   it is shown and dragged; and
2. a localized settings window whose complete fixed design canvas remains
   reachable at the exercised DPI and constrained window size.

M10 judges presentation and usability after a toolbar is eligible to appear. It
does not judge whether profile activation, lone-Shift state transitions, or
cross-host visibility become deterministic; those are the redefined M11.

## Frozen closeout build

Implementation last changed at `589bc3d`; `337b9bd` remains historical
pre-rebaseline provenance. At deployment time, pin the clean source
commit actually used to build the TSF DLL, server, settings executable, and
default skin, then record their installed hashes before either live gate begins.
If that source is a documentation/evidence-only descendant of `589bc3d`, record the
diff proving no product build input changed. Verify that loaded TSF holders map
the pinned DLL.

Do not change the source, settings layout, skin, toolbar fallback, or installed
binaries midway through a gate. Any corrective change creates a new candidate:
rerun the focused non-elevated checks, freeze the new source and artifact hashes,
and rerun the affected M10 installed gates. If that candidate is also used for
M11, its M11 gates run separately. Documentation, test-contract, or evidence-
only edits that change no product build or package input do not invalidate a
candidate, but their diff from the pinned source must be recorded. Final
evidence may not combine verdicts from incompatible TSF, server, settings,
default-skin, or package artifact sets.

The approved 2026-07-09 PT clone/drag observation used the older source commit
`1f419837b0575dc1ea47dba2785cbb6949b7e73c`. It proved that the then-installed
toolbar could retain one foreground-owned HWND in Notepad and Chromium without
fresh user-observed copies or afterimages. It is useful regression evidence, but
it is not installed acceptance for the current implementation baseline.
Candidate `7622305` was post-restart verified and produced a controlled,
clone-free 20-drag Notepad capture, but ordinary Notepad/Chromium focus movement
exposed a stale per-process toolbar position before the shared server state
converged. That failed the position-persistence gate, so its capture remains
regression/repro evidence only. Corrective candidate `589bc3d` keeps a hidden
toolbar latched closed until an existing-server refresh confirms current state
for the foreground owner. It is deployed with restart required and has not yet
been post-restart verified or visually exercised.

## In scope

### Native Cantonese surface

- Common-controls v6 and Per-Monitor-V2 settings behavior.
- `Microsoft JhengHei UI` typography and DPI-aware relayout.
- Centralized Cantonese strings for settings, dialogs, status text, and toolbar
  glyphs, with display labels kept separate from server protocol values.
- Guarded Windows 11 Mica, rounded-corner, and dark-mode polish with the existing
  flat native fallback on unsupported systems.

### Toolbar presentation

- Native DirectComposition + Direct2D presentation in the existing per-process
  TSF architecture.
- Fail-closed root ownership: no ownerless or foreground-mismatched toolbar may
  be visible.
- Process-local and cross-process visible-window arbitration sufficient to keep
  the presented surface singular.
- Movement-only drag, stable HWND identity, deferred render/resource work, and
  one final position persist/render flush.
- Effective-backdrop tracking, build-22621 system-backdrop gating, and an opaque
  fallback when the requested backdrop is unavailable.
- Privacy-safe topology capture sufficient to distinguish real HWND duplication
  from compositor trails.

### Settings-window usability

- DPI-aware initial client sizing.
- A resizable functional minimum window size.
- Live-DPI `WM_GETMINMAXINFO` and `WM_DPICHANGED` handling.
- Horizontal and vertical scrolling whenever the fixed design canvas exceeds
  the client area or monitor work area.
- Reachability of every existing control without introducing a responsive
  redesign or new functional settings.

## Explicitly out of scope

- **M11 — activation, state, and toolbar-visibility reliability:** profile and
  TSF focus identity, hook/sink token arbitration, boot-ID/revision CAS,
  operation-IPC reconciliation, deterministic eligible-host show/hide, paced
  lone-Shift acknowledgement, rapid-burst parity, and four-host focus cycling.
  M10 must preserve those implementation changes but cannot use their
  non-elevated evidence to claim their installed result.
- **M12 — skin platform:** additional built-ins, manifest catalog/import,
  validation, revisioning, caching, and catalog-backed settings behavior.
- **M13 — candidate presentation:** DirectComposition candidate migration,
  skin-driven candidate visuals, latency comparison, and first-show fallback.
- Yune engine ABI changes, a librime fallback, WebView2/Electron/HTML UI, a
  per-user UI host, animated skins, or new settings functionality.

## Execution boundary with M11

M10 may use its own approval-gated, hash-pinned deployment after the M10
preflight passes. That run can close only presentation and settings usability;
it is not M11 activation/state evidence. The remaining direct-TSF M11
pre-deployment matrix is required before a run is graded as M11, not before an
M10-only presentation run.

The milestones may reuse one exact candidate when no product or package input
changes. If later M11 work changes such an input, every affected M10 regression
gate must be rerun on the new combined candidate before downstream work,
including installed settings gate B whenever settings or shared UI inputs
change.
If M11 cannot make a toolbar visible in one of M10's required hosts, that M10
host remains `not_exercised`; separation never converts absence into proof.

## Legacy evidence crosswalk

The published evidence keeps its original labels and factual claims. This plan
references it; it does not retroactively relabel an older build as M10 proof.

| Legacy evidence | M10 use | Boundary |
| --- | --- | --- |
| `docs/evidence/m11/summary.md` and `summary.json` | Native theming/localization implementation, non-elevated checks, and the older installed clone/drag observation | Its installed hashes belong to `1f419837`, not the current closeout candidate; its activation findings belong to new M11. |
| `docs/evidence/m11c/summary.md` | Ownership, topology, movement-only drag, backdrop fallback, and legacy clone-repair result | It is presentation history, not fresh current-hash acceptance and not activation reliability proof. |
| Settings-related portions of `docs/evidence/m11d/summary.md` and `summary.json` | DPI sizing, resize, minimum-size scrolling, and non-elevated settings smoke | Token/CAS/dispatcher/visibility material belongs to new M11. No installed settings-usability proof was captured there. |

Legacy test and evidence names may continue to contain `m11`/`m11c`/`m11d`;
the names record implementation lineage rather than changing this milestone
boundary.

## Required non-elevated preflight

Before deployment, rerun the focused build and presentation/settings regressions
against the frozen source tree:

- TSF shell build;
- language-bar and settings-window smokes;
- M08 toolbar and M09 settings-panel contracts;
- legacy M11 UI-modernization and M11C DirectComposition toolbar contracts;
- language-bar window/topology diagnostics; and
- settings IME-state and server-response contracts, so localized display values
  remain separate from protocol values;
- the expanded multiprocess server reliability smoke, as a regression guard for
  the shared candidate rather than an M11 acceptance claim; and
- the M10 evidence/deployment safety contracts that bind the final verdict to
  one clean build, installed hashes, and a proven post-deployment session
  boundary.

The settings layout/self-test coverage must exercise 100%, 125%, 150%, and 200%
DPI calculations, minimum and larger client sizes, and constrained-work-area
scroll reachability. Those calculations support the live result but do not
claim visual crispness at an installed DPI that was not actually exercised.

Record commands, results, source hash, and artifact hashes. These checks prove
implementation readiness only; they do not substitute for the installed gates.

## Installed gate A — toolbar presentation

Exercise the pinned build in fresh Notepad, Chromium, Explorer, and one explicit
Electron host. Perform at least 20 repeated grip/settings-segment drags in each
host, with topology captured before, during, and after the sequence. M11 may be
needed to make appearance deterministic, but once a toolbar is visible M10
acceptance requires:

- at most one toolbar HWND visible system-wide;
- every visible toolbar has a valid owner whose root is the foreground root;
- each drag retains the same HWND from capture through finalization;
- grip and settings-segment drags move the window without segment activation,
  focus theft, stuck capture, duplicate position persistence, or mid-move
  rendering;
- no real duplicate window, painted copy, trail, or afterimage is visible;
- no English toolbar label remains, including the ASCII-active and octagram
  schema glyph states, and terminology matches the established Cantonese
  `uiText.yue` vocabulary;
- the final position survives ordinary focus movement and a host restart; and
- the installed topology capture, hashes, drag counts, and user visual verdict
  are recorded without window titles or typed text.

Deterministic first-show behavior and the number of activation/toggle attempts
belong only to M11. M11 also grades the previous-host 250 ms hide deadline, but
M10 still rejects any topology sample containing more than one visible toolbar
or a toolbar whose owner root is not foreground. If the toolbar cannot be made
visible at all, gate A is **not exercised** and M10 remains pending rather than
converting that absence into presentation proof.

### Deterministic toolbar fallback

Clone-free behavior outranks glass:

1. Retain acrylic only if the current pinned build shows exactly one real HWND
   and produces no visual trail.
2. If topology remains singular but acrylic trails, make opaque static-tint
   DirectComposition the default and defer acrylic.
3. If static DirectComposition also trails, use a normally redirected opaque
   native D2D HWND, without `WS_EX_NOREDIRECTIONBITMAP` and without the toolbar
   DirectComposition path.

A fallback source or manifest change invalidates the current candidate hash. It
must land as a new implementation change and rerun the affected M10 gates on a
newly frozen candidate. M11 runs only if or when that same candidate is graded
for M11; do not record a failed run as accepted with an unpinned live adjustment.

## Installed gate B — settings usability

Launch the pinned `YuneWindowsSettings.exe` directly and record this gate
separately from toolbar activation. At the exercised monitor DPI:

- the initial client area exposes a usable viewport rather than a clipped,
  immovable dialog;
- the window resizes from its functional minimum to a larger size;
- horizontal and vertical scrolling make every control on the fixed design
  canvas reachable at the minimum/constrained size;
- labels, controls, group boxes, preview, and status text remain legible and do
  not overlap during resize or DPI relayout;
- native controls use the intended JhengHei/Segoe typography and remain crisp at
  the installed DPI values actually exercised;
- rounded corners, dark-mode attributes, and guarded Mica/DWM polish behave
  correctly in both Windows light and dark themes, with the flat native
  fallback remaining usable when an effect is unsupported;
- no English remains in the panel, window title, dialog captions or bodies,
  status text, or preview labels; terminology matches the established
  Cantonese `uiText.yue` vocabulary, and combo display labels do not leak into
  protocol values; and
- close/reopen behavior remains stable without focus theft or an orphaned
  settings process.

Record the monitor DPI, initial/minimum/larger client sizes, installed settings
hash, screenshots or an equivalent visual checklist, scrolling/reachability
result, and user usability verdict. Non-elevated 100–200% calculations remain
supporting coverage; do not claim unexercised installed DPI values as visually
proven.

## Verdicts and archival

Gate A and gate B receive independent `pass`, `fail`, or `not_exercised`
verdicts against the same pinned candidate. A new-M11 activation failure does
not erase a completed M10 settings result or a presentation result that was
actually exercised. Conversely, old clone evidence cannot compensate for an
unexercised current-hash presentation gate.

M10 closes only when both installed gates pass on one frozen candidate and the
evidence records the exact source/artifact hashes. Then publish an M10 evidence
summary under `docs/evidence/m10/` that links the legacy M11/M11C/M11D material
without rewriting its original claims, move this plan to history, and leave M11
active until its own activation/state/visibility acceptance passes. M12 and M13
remain future work under their independent plans and evidence gates.

## Last Updated

- 2026-07-10: Rejected candidate `7622305` after its installed focus-movement
  check exposed a transient stale cross-host toolbar position. Published and
  deployed corrective candidate `589bc3d`; its full measured non-elevated
  preflight passes, while restart verification and both installed gates remain
  pending.
- 2026-07-10: Aligned the D-22 rerun rule with the decision record: rerun every
  affected M10 gate, including installed settings gate B when its inputs change.
- 2026-07-10: Recorded candidate `7622305` as deployed with exact hashes and a
  required restart; post-restart verification and both installed verdicts remain
  pending.
