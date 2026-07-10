# Historical Plans

Completed and superseded implementation plans live here for auditability.

- `m01-plan-windows-product.md` - Windows product baseline and live
  closeout path.
- `m02-plan-server-lifecycle-cleanup-hardening.md` - product-owned server
  lifecycle and structured cleanup hardening.
- `m03-plan-dev-inner-loop.md` - non-elevated development inner-loop
  tooling: dev REPL, server reload, TSF DLL reload, and watch wrapper.
- `m04-plan-candidate-window-typing-quality.md` - candidate comment
  hygiene, caret anchoring implementation, owner/no-orphan lifecycle hardening,
  candidate paging, and punctuation/full-width input.
- `m05-plan-ime-toggles-language-bar-settings.md` - server-owned IME state,
  toggle hotkeys, focus-scoped mini language bar, and native settings
  entrypoint.
- `m06-plan-host-compatibility-pass.md` - host compatibility relief, server
  resilience, bounded foreground key-path IPC, punctuation forwarding, and
  low-level Shift fallback.
- `m07-plan-persistent-composition-selection.md` - server-owned persistent
  composition sessions and TSF inline composition.
- `m08-plan-modern-toolbar.md` - Direct2D/DirectWrite floating toolbar,
  skin-manifest architecture, no-activate drag, and server-owned toolbar
  position/skin state.
- `m09-plan-skins-and-picker.md` - toolbar settings segment, native Win32
  settings panel, skin picker, shared-renderer preview, and disabled future
  engine/dictionary/schema sections.

## Pre-rebaseline source plans

D-21 reordered the active work on 2026-07-10. These files preserve their
original labels and internal scheduling language for auditability; their
current owners are recorded in `docs/reference/m10-m13-rebaseline.md`.

- `m10-plan-skin-breadth-candidate-window.md` - unstarted former M10 plan, now
  split between canonical M12 Skin Platform and M13 Candidate Presentation.
- `m11-plan-ui-modernization-cantonese.md` - former M11 presentation and
  localization plan, now owned by canonical M10.
- `m11c-dcomp-glass-toolbar-handoff.md` - former M11C ownership/clone/drag/
  backdrop handoff, now canonical M10 implementation history.
- `m11d-ime-activation-toolbar-visibility.md` - former M11D plan; activation,
  state, and visibility now belong to canonical M11, while its settings
  DPI/resize/scroll subsection belongs to canonical M10.
