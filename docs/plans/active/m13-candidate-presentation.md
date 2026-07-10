# M13 - Candidate Presentation

> **Status:** planned; blocked on M12 Skin Platform. The renderer migration is
> additionally blocked until this milestone records the existing GDI candidate
> baseline on the same test configuration used for comparison.

## Goal

Apply the active validated M12 skin to a fully restyled native candidate window
on an opaque/static-tint DirectComposition surface while preserving candidate
behavior, ownership, focus, and latency. This milestone does not change the Yune
engine ABI, candidate ordering, paging semantics, or learning policy.

## Locked boundaries

- The inline candidate window remains native. No WebView2, Electron, HTML, or
  out-of-process UI host enters the latency-critical candidate path.
- Candidate Acrylic is out of scope. The guaranteed presentation is opaque or
  static-tint DirectComposition with a normally redirected GDI fallback.
- M13 consumes M12 `SkinDefinition`, active skin ID, and `skin_revision`; it does
  not add another manifest parser, catalog, or filesystem reader.
- Caret anchoring, paging, selection, foreground/owner guards, no-activation
  behavior, sanitized comments, numbering, candidate order, and
  `disable_learning` remain unchanged.
- No Yune engine ABI change or librime runtime fallback is introduced.

## Implementation order

### Slice 0 - Record the GDI baseline before migration

Benchmark the existing normally redirected GDI candidate window before changing
its presentation:

- 30 cold first shows; and
- 500 warm updates.

Record median and p95 for cold first-show and warm-update latency, together with
the build hash, machine/configuration, DPI, candidate count, window dimensions,
and measurement method. Keep the baseline artifact immutable. No
DirectComposition migration begins until the baseline is reproducible and the
measurement harness passes a no-change rerun.

### Slice 1 - Generalize the composition lifecycle

1. Extract the DirectComposition device, target, visual, surface, draw, commit,
   resize, and device-recreation lifecycle independently from toolbar-specific
   drawing and backdrop behavior.
2. Keep toolbar and candidate presentation state separate: the candidate never
   inherits toolbar Acrylic, drag, segment, topmost, or position-persistence
   behavior.
3. Add active skin ID and revision to `CandidateWindowState`. An unchanged
   `{skin_id, skin_revision}` must not reread a manifest or rebuild resources
   unnecessarily.
4. Make device loss and surface recreation explicit and testable. A failed
   recreation must hide or fall back rather than expose a blank/stale surface.

### Slice 2 - Implement the opaque/static DComp candidate

1. Create an opaque/static-tint DirectComposition candidate surface using the
   generalized lifecycle.
2. Apply the active skin to every candidate visual field:
   - window background and border;
   - corner radius and outer/inner padding;
   - row height, spacing, and selection highlight;
   - candidate text and annotations; and
   - page indicator.
3. Localize the page indicator to `頁 n/N`.
4. Preserve caret anchoring, client-side PageUp/PageDown paging, number-key and
   pointer selection, foreground/root-owner validation, no focus steal,
   sanitized comments, and numbering.
5. Clamp and lay out using finite, bounded values already validated by M12; the
   renderer must not silently reinterpret invalid geometry.

### Slice 3 - Guarantee a visible GDI fallback

If DirectComposition initialization fails before the first show, destroy the
failed no-redirection candidate HWND and recreate a normally redirected GDI
candidate window. Do not reuse incompatible window styles and never show a
blank surface. A later DComp device failure follows the same fail-closed
recreate-or-hide rule without changing composition/candidate state.

## Performance gate

Compared with the recorded GDI baseline on the same configuration:

- warm median and p95 may regress by at most 10% or 1 ms, whichever allowance is
  larger; and
- cold median and p95 may regress by at most 15% or 2 ms, whichever allowance is
  larger.

Report all four before/after values and the applied absolute allowance. A
toolbar benchmark, synthetic draw-only timing, or result from a different
machine/configuration cannot close this gate.

## Behavior and fallback gates

- Active skin ID/revision drives every candidate visual field for `default`,
  `midnight`, and a valid user skin without changing candidate text or order.
- `頁 n/N`, caret anchoring, paging, keyboard/pointer selection, comments,
  numbering, ownership, foreground matching, and no-focus-steal behavior remain
  correct.
- Repeated warm updates keep a stable candidate HWND unless a documented device
  failure requires recreation.
- Forced DComp initialization and first-show failures recreate the normally
  redirected GDI window and never expose a blank surface.
- Device loss during an active composition preserves logical candidate state and
  either recreates the DComp surface or uses the GDI fallback deterministically.

## Completion gates

- The immutable 30-cold/500-warm GDI baseline and reproducibility check are
  recorded before renderer migration.
- The generalized composition lifecycle has focused creation, resize,
  device-loss, and fallback coverage independent of toolbar drawing.
- The opaque/static-tint DComp candidate applies all M12 visual fields and passes
  the complete behavior gate.
- Cold and warm median/p95 remain within the exact regression allowances.
- Evidence lands under `docs/evidence/m13/`; M13 candidate evidence remains
  independent from M10/M11 toolbar evidence; and no Yune engine ABI change is
  introduced.
