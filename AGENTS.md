# Repository Guide

**Yune Windows** is the Yune-first Windows IME product repo. It owns Windows
Text Services Framework integration, the Windows process model, product UI,
packaging, installer behavior, diagnostics, and dogfood evidence.

This repo does **not** own Yune engine internals. Yune remains the runtime
engine and is consumed through a packaged Windows ABI surface.

## Current State

- This public baseline is the renamed Yune Windows product tree.
- Fresh post-rename live evidence exists for install/register, Notepad,
  Chromium, diagnostics, uninstall, and post-reboot cleanup. The next product
  gate is P2-WIN03 Development Inner Loop.
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
- [docs/plans/active/README.md](./docs/plans/active/README.md) - active plan status.
- [docs/plans/history/](./docs/plans/history/) - completed implementation plans.
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
- Treat full live IME runs as reboot-prone machine-state tests, not routine
  verification. Do not run canonical install/register/profile activation/
  Notepad/Chromium/diagnostics/uninstall/cleanup loops after ordinary changes
  unless the active task is a live closeout gate, the bug cannot be reproduced
  with non-elevated/temp-build checks, or the user explicitly asks for that run
  after being told it may require sign-out or reboot.
- Prefer non-elevated contracts, temp-build TSF/server smokes, Yune package
  checks, IPC tests, and candidate-window smokes for the normal development
  loop. If dev-only per-run install roots are used for live iteration, label
  their evidence as non-closeout evidence and do not use them to close dogfood
  readiness.
- If a live run schedules delayed delete for locked `YuneWindowsTSF.dll` or
  install-root files, stop further canonical live attempts until sign-out/reboot
  and post-cleanup verification prove the install directory and pending-delete
  entries are gone.
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

## Publishing

- Default to direct-to-`main` publishing for this repo. After scoped review and
  verification, stage only the intended files, commit on `main`, and push
  `origin/main`; do not create feature branches, PRs, or branch handoff steps
  unless the user explicitly asks for them.
- Before a direct `main` publish, refresh safely with `git fetch origin` and a
  fast-forward check/merge, preserve unrelated worktree changes, and verify the
  final status and pushed commit.

## Verification

Docs-only changes:

```powershell
git diff --check
```

Implementation changes should include focused build and non-elevated smoke
commands before live registration. Run the reboot-prone full live path only for
approved live closeout or an explicitly justified live-only bug. Elevated TSF
installation and verifier commands need fresh user approval.
