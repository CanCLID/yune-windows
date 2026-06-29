# P2-WIN01 Windows Product Implementation Plan

**Goal:** maintain the first usable Yune-only Yune Windows IME product path in
the public `CanCLID/yune-windows` repo.

**Architecture:** Yune Windows owns the Windows product and consumes packaged
Yune through the opt-in Yune Windows profile ABI. The product uses a shared
server/IPC process model, native TSF integration, and a native first candidate
window. The legacy Weasel-derived implementation is reference material only.

## Current Facts

- This repo is the renamed public Windows product repo.
- Old private evidence captured before the rename is intentionally omitted from
  the clean initial commit.
- Yune is the only runtime engine.
- The Yune package command is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-yune-windows.ps1
```

- The Windows build command is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

## Non-Negotiable Gates

- No librime runtime fallback.
- No default Yune ABI widening.
- Yune Windows profile behavior stays behind
  `rime_get_yune_windows_profile_api()`.
- Elevated TSF registration, installer, AppVerifier, PageHeap, registry,
  unregister, and cleanup steps require explicit user approval before
  execution.
- Machine-state changes must record before/after evidence.
- The first inline candidate window is native.
- Sensitive TSF contexts suppress learning, AI staging, and typed-content logs.
- Product claims require Windows product evidence.
- Dogfood readiness does not close with a measured blocker.

## Public Rename Tasks

- [x] Rename public product identity to Yune Windows.
- [x] Rename runtime binaries to `YuneWindowsTSF.dll`,
  `YuneWindowsServer.exe`, `YuneWindowsProfileTool.exe`, and
  `YuneWindowsCandidateWindowSmoke.exe`.
- [x] Rename IPC pipe to `\\.\pipe\yune-windows-ime`.
- [x] Rename install root to `%LOCALAPPDATA%\Yune\WindowsIme`.
- [x] Constrain approved installer and uninstaller file operations to the
  `LocalAppData\Yune` boundary; verify with
  `tools\test-install-dir-safety-contract.ps1`.
- [x] Use fresh TSF identity constants:
  - text service CLSID `{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}`
  - profile GUID `{3AE69B8D-19B4-4267-8F21-E239666D6632}`
- [x] Consume the Yune Windows package from
  `target\yune-windows-native\x86_64-pc-windows-msvc\dist`.
- [x] Consume `rime_yune_windows_profile_api.h`,
  `RimeYuneWindowsProfileApi`, and
  `rime_get_yune_windows_profile_api()`.
- [x] Omit old private evidence from the public initial commit.
- [x] Push a clean initial `main` commit to `CanCLID/yune-windows`.

## Non-Elevated Verification

Run before publishing:

```powershell
# Scan the tree, excluding .git, for old product-name strings.
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-host-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-ipc-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-install-dir-safety-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-machine-state-approval-gates.ps1
```

## Safety And Evidence Contract Manifest

These contract scripts remain in the public repo even though old private
evidence is omitted:

- `tools\test-tsf-server-query-timeout-contract.ps1` verifies bounded
  shared-server pipe I/O so stalled IPC cannot hang a foreground target app.
- `tools\test-live-smoke-preflight-readiness-gate.ps1` verifies live preflight
  readiness is checked before profile-probe build, install, registration, or
  app automation.
- `tools\write-p2-win01-approval-brief.ps1` and
  `tools\test-approval-brief-contract.ps1` maintain the operator approval
  brief path at `docs\evidence\p2-win01-installer\approval-brief.md`.
- `tools\clear-yune-windows-machine-residue.ps1` and
  `tools\test-approved-machine-cleanup-contract.ps1` maintain approval-gated
  cleanup evidence paths:
  `docs\evidence\p2-win01-installer\machine-cleanup-approval.md`,
  `docs\evidence\p2-win01-installer\machine-cleanup-before.json`,
  `docs\evidence\p2-win01-installer\machine-cleanup-after.json`, and
  `docs\evidence\p2-win01-installer\machine-cleanup-result.md`.
- `tools\collect-p2-win01-compatibility-environment.ps1` and
  `tools\test-compatibility-environment-evidence.ps1` regenerate
  `docs\evidence\p2-win01-installer\compatibility-environment.json`.
- `tools\test-product-hardening-evidence-contract.ps1` checks regenerated
  compatibility and signing docs at
  `docs\evidence\p2-win01-installer\compatibility-matrix.md` and
  `docs\evidence\p2-win01-installer\signing-decision.md`.
- `tools\test-webview2-feasibility.ps1` checks regenerated settings evidence
  at `docs\evidence\p2-win01-settings\webview2-spike.md`.
- `tools\test-live-smoke-preflight-evidence.ps1` checks regenerated preflight
  evidence at `docs\evidence\p2-win01-installer\live-preflight.json` and
  `docs\evidence\p2-win01-installer\install-preflight.json`.
- `tools\test-chromium-smoke-plan-exact-structural-evidence.ps1` checks the
  regenerated Chromium smoke plan at
  `docs\evidence\p2-win01-tsf-smoke\chromium-smoke-plan.md`.

## Post-Publish Dogfood Evidence

With fresh explicit approval, run the full live path under the Yune Windows
names and record evidence for:

- fresh install target and packaged Yune inputs;
- TSF registration and Yune Windows profile activation;
- `ngohaig` typed into Notepad through Yune;
- candidate display and candidate commit;
- one Chromium-based text-field smoke;
- diagnostics/log export;
- uninstall and cleanup;
- proof that no install directory, TSF DLL, server process, TSF profile, or
  machine residue remains.

## Current Closeout Status

P2-WIN01 has the core Yune Windows development path working: packaged Yune,
the TSF shell, native candidate display, Notepad input, Chromium input,
diagnostics export, and recovered cleanup have post-rename evidence. Manual
dogfood also works after starting the shared server explicitly and activating
the profile.

The milestone should not be declared dogfood-ready yet. The current manual path
exposed two product gaps:

- `YuneWindowsServer.exe` must be started explicitly before typing; otherwise
  the TSF DLL receives keystrokes but logs `server_query_failed` and cannot
  show candidates.
- Cleanup can be blocked while apps keep `YuneWindowsTSF.dll` loaded, so the
  operator path needs better unload detection, guidance, or cleanup recovery.

## Next Milestone

**P2-WIN02 - Server Lifecycle And Cleanup Hardening**

Deliverables:

- product-owned shared-server startup or a per-user broker/autostart design;
- bounded first-query retry/readiness behavior from the TSF path;
- structural logs that distinguish server-not-running, server-timeout, and
  invalid-response failures;
- installer/uninstaller cleanup that reports DLL holders and reliably reaches a
  no-residue state after normal app shutdown;
- one fresh full live run proving install, registration, activation, Notepad,
  Chromium, diagnostics export, uninstall, and cleanup without manual server
  startup.
