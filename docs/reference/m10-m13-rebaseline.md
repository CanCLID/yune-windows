# M10-M13 Milestone Rebaseline

On 2026-07-10, the roadmap was reordered around the actual dependency chain.
The former M10 plan had not started, while the later-numbered M11 repair work
had become its prerequisite. The new numbering removes that backwards
dependency and gives presentation, activation, skin infrastructure, and
candidate rendering separately owned acceptance stories.

## Canonical mapping

| Pre-rebaseline scope | Canonical owner | Boundary |
| --- | --- | --- |
| Former M11 localization/settings polish, DirectComposition toolbar, and M11C ownership/clone/drag/backdrop repair | M10 - Native UI Presentation Closeout | Judges the toolbar once shown and the installed settings-window usability. |
| Settings DPI/resize/scroll portion of former M11D | M10 - Native UI Presentation Closeout | The settings repair is presentation/usability work, not activation semantics. |
| Activation, focus identity, lone-Shift token/parity, CAS, bounded IPC, tracing, and visibility portion of former M11D | M11 - Activation and State Reliability | Judges whether the correct toolbar appears and state changes exactly once across real hosts. |
| Former M10 shared skin definition/catalog, built-in breadth, import, IPC, revisioning, caching, and settings integration | M12 - Skin Platform | Begins only after the frozen M10 + M11 installed closeout passes. |
| Former M10 candidate baseline, renderer migration, complete styling, fallback, behavior, and performance work | M13 - Candidate Presentation | Begins after M12 with Slice 0 baseline capture; renderer migration waits for that baseline to be reproducible. |

The canonical active plans are:

- `docs/plans/active/m10-native-ui-presentation-closeout.md`;
- `docs/plans/active/m11-activation-state-reliability.md`;
- `docs/plans/active/m12-skin-platform.md`; and
- `docs/plans/active/m13-candidate-presentation.md`.

## Historical-plan and evidence policy

The superseded source plans move to `docs/plans/history/` with their original
milestone labels and a rebaseline notice. Their internal wording remains a
record of the plan state before this decision; it is not the current execution
order.

Existing evidence roots remain in place:

- `docs/evidence/m11/` and `docs/evidence/m11c/` are legacy provenance for
  current M10 presentation work;
- the settings portion of `docs/evidence/m11d/` maps to current M10; and
- the activation/state/visibility portion of `docs/evidence/m11d/` maps to
  current M11.

Those directories, JSON `milestone` values, test filenames, commits, hashes,
and recorded observations are not renamed or reinterpreted. Rebaseline notes
may identify current ownership, but they must not claim that an old installed
build passed a new current-hash gate.

Fresh closeout evidence uses `docs/evidence/m10/` for current M10 and
`docs/evidence/m11-activation/` for current M11. The distinct M11 path avoids
overwriting the preserved pre-rebaseline `docs/evidence/m11/` record. M12 and
M13 use `docs/evidence/m12/` and `docs/evidence/m13/` respectively.

## Execution order

1. Record `eb262fa` as the current implementation commit and `337b9bd` as the
   older pre-rebaseline source/evidence baseline.
2. At deployment time, pin the clean source commit and the TSF, server,
   settings, and skin artifact hashes actually built and installed. If the
   source descends from `eb262fa` without a new product change, record the diff
   proving the intervening changes are planning/contracts only.
3. Publish separate verdicts: M10 presentation/settings and M11
   activation/state. M10 may deploy and close first. M11 may reuse that exact
   candidate only if product/package inputs remain unchanged and its remaining
   pre-deployment matrix passes.
4. Keep either milestone open when its own gate fails or is not exercised; one
   passing verdict does not erase the other lane's failure. Any product build
   or package input change before M11 invalidates candidate reuse and requires
   the affected M10 regression gates on the new candidate.
5. Begin M12 only after both M10 and M11 pass. Begin M13 after M12 with Slice 0
   GDI baseline capture; begin renderer migration only after that baseline is
   recorded and reproducible.

M10 and M11 are separate diagnostic and evidence verdicts. Their installed
execution may share one exact candidate but need not occur in one session. M10
still cannot exercise a host's presentation gate if the current implementation
cannot make the toolbar eligible there. In that case M10 is `not_exercised`,
not passed. A duplicate
or foreground-invalid stale toolbar may legitimately fail both M10 topology and
M11 handoff timing.

Machine-state evidence remains separate from implementation and planning
commits. No elevated installation, registration, holder termination, or
cleanup action is authorized by this documentation decision.
