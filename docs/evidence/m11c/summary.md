# M11 Slice C DirectComposition Glass Toolbar Evidence

Status: implemented non-elevated. The language-bar toolbar is ported from
`WS_EX_LAYERED` + `UpdateLayeredWindow` to a native DirectComposition + Direct2D
renderer over DWM Desktop Acrylic. This is a source/build/contract evidence
bundle only; live visual confirmation was not run by Codex.

## Implementation

- `LanguageBarWindow` creates a `WS_POPUP` with
  `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST |
  WS_EX_NOREDIRECTIONBITMAP`.
- `GlassSurface` creates the D3D11 BGRA device, D2D device/context,
  DirectComposition target/visual/surface, and commits a persistent DComp surface.
- Rendering uses the DComp surface's `IDXGISurface`, wraps it in an
  `ID2D1Bitmap1` with `D2D1_BITMAP_OPTIONS_TARGET |
  D2D1_BITMAP_OPTIONS_CANNOT_DRAW`, calls `SetDpi(96,96)`, and reuses
  `DrawLanguageBarContent` unchanged.
- Acrylic uses `DwmExtendFrameIntoClientArea`, `DWMSBT_TRANSIENTWINDOW`, and
  rounded DWM window corners. The default skin selects `dwm_acrylic` with a
  low-alpha tint and no D2D shadow padding.
- Device loss (`D2DERR_RECREATE_TARGET`, `DXGI_ERROR_DEVICE_REMOVED`,
  `DXGI_ERROR_DEVICE_RESET`, and related DXGI loss codes) discards the graphics
  stack and retries one render.

## Verification

Passed non-elevated:

- `git diff --check`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-window-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m08-modern-toolbar-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m09-settings-panel-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m11-ui-modernization-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m11c-dcomp-glass-toolbar-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-window-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-ime-state-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-ime-state-protocol-contract.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-response-validation-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-repl-ime-state-contract.ps1`

## Not Run

- Live visual confirmation was not run by Codex: repeated clone-free drag,
  frosted acrylic over a real host, no focus steal while typing, and candidate
  latency checks remain a human live gate.
- Elevated install/register/unregister, registry mutation, AppVerifier/PageHeap,
  verifier cleanup, full Notepad/Chromium live IME loops, and reboot-prone
  cleanup were not run.
