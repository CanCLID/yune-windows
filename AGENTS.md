# Repository Guide

**Yune Windows** is the Yune-first Windows IME product repo. It owns Windows
Text Services Framework integration, the Windows process model, product UI,
packaging, installer behavior, diagnostics, and dogfood evidence.

This repo does **not** own Yune engine internals. Yune remains the runtime
engine and is consumed through a packaged Windows ABI surface.

## Current State

- This public baseline is the renamed Yune Windows product tree.
- Old pre-rename evidence is intentionally omitted from the clean initial
  commit; regenerate post-rename live evidence before dogfood or production
  installer work.
- The legacy Weasel-derived implementation remains useful reference material
  for TSF, server, IPC, installer, candidate-window positioning, and smoke
  harness behavior.
- Yune exposes the Windows package/profile ABI through
  `rime_get_yune_windows_profile_api()`.

## Canonical Docs

- [README.md](./README.md) - repo purpose and quick start.
- [docs/roadmap.md](./docs/roadmap.md) - current product track dashboard.
- [docs/requirements.md](./docs/requirements.md) - requirement gates.
- [docs/decisions.md](./docs/decisions.md) - standing product decisions.
- [docs/plans/active/p2-win01-plan-windows-product.md](./docs/plans/active/p2-win01-plan-windows-product.md) - active implementation plan.
- [docs/reference/yune-engine-contract.md](./docs/reference/yune-engine-contract.md) - Yune package/API boundary.
- [docs/reference/weasel-reference-boundary.md](./docs/reference/weasel-reference-boundary.md) - how to use the legacy reference safely.

## Hard Boundaries

- Yune is the only runtime engine.
- Do not add a librime runtime fallback.
- Do not widen Yune's default `rime_get_api()` ABI.
- Yune Windows profile-only behavior stays behind named Yune Windows profile
  surfaces.
- Any new Yune engine requirement must become a named Yune proposal with tests
  before this repo depends on it.
- Product/frontend performance evidence does not close Yune engine gates.
- Yune engine evidence does not close Windows product gates.
- Usable Windows IME readiness requires fresh install, TSF registration,
  profile activation, Notepad smoke, Chromium smoke, diagnostics export,
  uninstall, and cleanup evidence captured under the Yune Windows names.

## Windows Safety

- Do not run elevated install, unregister, registry, AppVerifier, PageHeap, or
  verifier cleanup steps without explicit user approval in the current session.
- Keep machine-state evidence separate from implementation commits.
- Record installed IME state before and after any TSF registration experiment.
- Preserve unrelated files in the legacy reference checkout.

## Development Direction

- Prefer a fresh Yune-first product architecture.
- Reuse the smallest proven slices from the legacy Weasel-derived reference
  implementation only when they reduce TSF/IPC/installer risk.
- Use a shared server/IPC process model by default unless a spike proves
  in-process TSF-per-app loading is safer.
- Keep the first inline candidate window native.
- Treat WebView2 as a settings/dictionary-panel candidate, not the first
  latency-critical candidate renderer.

## Verification

Docs-only changes:

```powershell
git diff --check
```

Implementation changes should include focused build and non-elevated smoke
commands before live registration. Elevated TSF installation and verifier
commands need fresh user approval.
