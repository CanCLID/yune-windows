# M08 Modern Floating Toolbar Evidence

Status: non-elevated implementation complete and verified with build, contract,
server, and window-smoke evidence. Live dogfood visual/interactive proof in real
TSF hosts is still pending and requires explicit approval for the live-machine
path.

What landed:

- Replaced the GDI language bar render path with a `WS_EX_LAYERED |
  WS_EX_NOACTIVATE` Direct2D/DirectWrite toolbar presented through
  `UpdateLayeredWindow`.
- Added shared `D2DSurface`, toolbar geometry/clamp helpers, and a conservative
  skin-manifest loader with compiled-in fallback.
- Added the repo-owned default skin manifest under `skins/default/` and
  build/install/dev deployment wiring.
- SVG asset rendering is deferred to M09 or a later skin-renderer slice; M08
  ships manifest segment glyph labels only and does not ship inert image assets.
- Added manual grip drag with click-vs-drag threshold, monitor clamping, and no
  `HTCAPTION`.
- Added server-owned `op=set-toolbar-position` and `op=set-skin` state persisted
  under `state\ime-state.json` and returned in every server state block.
- Kept the candidate window behavior unchanged except for linking the shared
  renderer scaffolding.

Verification run:

- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m08-modern-toolbar-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-window-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-ime-state-protocol-contract.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-ime-state-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-repl-ime-state-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-response-validation-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-build-output-isolation-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-reload-no-reregister-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-tooling-safety-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-test-window-state-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-install-fresh-target-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-install-rollback-contract.ps1`
- `git diff --check`

Live-machine boundary:

- Elevated install/register/unregister/cleanup, AppVerifier/PageHeap, registry
  mutation, and full Notepad/Chromium live IME loops were not run. They require
  explicit current-session approval and are separate dogfood/live-readiness
  evidence.
- Live dogfood visual/interactive inspection of the toolbar in real TSF hosts was
  not run for the same approval boundary.
