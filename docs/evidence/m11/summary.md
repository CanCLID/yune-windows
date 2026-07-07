# M11 UI Modernization + Cantonese Localization Evidence

Status: Slices A (native theming + Cantonese), B (Win11 DWM polish), and C
(DirectComposition glass toolbar) are implemented non-elevated. Slice C ports the
language-bar toolbar off `WS_EX_LAYERED` + `UpdateLayeredWindow` and onto a
native DirectComposition + Direct2D surface over DWM Desktop Acrylic. Live visual proof remains approval-gated and human-gated because it requires loading the TSF DLL in real desktop hosts and visually checking clone-free drag plus glass.

## Implemented Scope

- Settings panel modernization:
  - `YuneWindowsSettings.exe` embeds a common-controls v6 manifest with the
    modern `PerMonitorV2` DPI element.
  - Native controls use `Microsoft JhengHei UI`, are registered for DPI relayout,
    and recreate/apply the font on `WM_DPICHANGED`.
  - Windows 11 DWM polish is build-gated: dark mode, rounded corners, and Mica
    are attempted only through guarded `DwmSetWindowAttribute` calls. Windows 10
    stays on the clean themed native fallback.
- Cantonese localization:
  - User-visible settings strings are centralized in
    `src/tools/yune_windows_ui_strings.*`.
  - The panel title, sections, status line, disabled scaffold controls, refresh
    action, preview fallback, and error dialogs are Cantonese.
  - Output/schema/skin combo label/value split keeps visible labels separate from server value IDs, so
    localized display text is not sent in `op=` payloads.
- Toolbar glyphs and skin defaults:
  - Toolbar literals were updated from `EN` to `英`, `繁` to `傳`, `臺` to `台`,
    and `拼` to `朙`.
  - `luna_pinyin_octagram` is explicit and maps to `朙`; unknown schemas no
    longer fall through to the first Latin character.
  - `skins/default/theme.json` uses CJK segment glyphs and adds glass metadata
    with back-compatible compiled-in defaults.
- Glass toolbar:
  - `LanguageBarWindow` now creates a no-activate native popup with
    `WS_EX_NOREDIRECTIONBITMAP` instead of `WS_EX_LAYERED`.
  - `GlassSurface` owns the DirectComposition stack: D3D11 BGRA device,
    `ID2D1DeviceContext` fixed to 96 DPI, `IDCompositionTarget`/visual/surface,
    and a DComp surface present path that reuses `DrawLanguageBarContent`
    unchanged.
  - The DComp DXGI surface is wrapped as an `ID2D1Bitmap1` with
    `D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW`, matching the
    validated spike and avoiding the known `E_INVALIDARG` blank-render failure.
  - DWM Desktop Acrylic is requested with `DwmExtendFrameIntoClientArea`,
    `DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_TRANSIENTWINDOW`, and rounded corners.
    Windows 10 remains a flat/no-backdrop fallback.
  - Device-loss handling discards and recreates the D3D/D2D/DComp stack, then
    retries one render.
  - Live visual confirmation of repeated clone-free drag and frosted glass over a
    real host was not run by Codex; it remains the human gate for the slice.
- Localization note: `luna_pinyin_octagram` intentionally renders as
  `朙月拼音（八股文）` (fully Cantonese, user-confirmed — a pun on
  "Octagram" ≈ "8-gram" ≈ 八股) rather than yune-web's Latin
  `朙月拼音 + Octagram` (see M11 plan appendix).

## Verification Results

Passed non-elevated on 2026-07-03:

- `git diff --check`
- `tools\test-tsf-shell-build.ps1`
- `tools\test-m08-modern-toolbar-contract.ps1`
- `tools\test-m09-settings-panel-contract.ps1`
- `tools\test-m11-ui-modernization-contract.ps1`
- `tools\test-m11c-dcomp-glass-toolbar-contract.ps1`
- `tools\test-language-bar-window-contract.ps1`
- `tools\test-language-bar-smoke.ps1`
- `tools\test-settings-window-smoke.ps1`
- `tools\test-settings-ime-state-contract.ps1`

## Approval-Gated Steps Not Run

- Elevated install/register/unregister, registry mutation, AppVerifier/PageHeap,
  verifier cleanup, and full Notepad/Chromium live IME loops remain skipped.
- Live visual proof of the host backdrop brush over real app content remains
  pending approval. The non-elevated implementation keeps static translucent tint
  as the guaranteed non-hollow fallback until that visual check is approved.
