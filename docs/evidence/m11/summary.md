# M11 UI Modernization + Cantonese Localization Evidence

Status: non-elevated implementation evidence complete. Live visual proof remains approval-gated because it would require loading the TSF DLL in real desktop hosts and visually checking the glass toolbar over app content.

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
- Glass toolbar shell:
  - A `GlassSurface` abstraction owns the toolbar presentation path above the
    existing Direct2D content renderer.
  - The documented host backdrop brush path is represented first:
    `DWMWA_USE_HOSTBACKDROPBRUSH` + WinRT `Windows.UI.Composition`
    `Compositor.CreateHostBackdropBrush` + `WS_EX_NOREDIRECTIONBITMAP`.
  - Fallback paths are represented in order: undocumented
    `SetWindowCompositionAttribute` `ACCENT_ENABLE_ACRYLICBLURBEHIND`, DWM
    transient acrylic, then static translucent tint. The fallback preserves the
    M08 no-activate/drag/device-loss invariants and avoids a hollow bar.

## Verification Results

Passed non-elevated on 2026-07-03:

- `git diff --check`
- `tools\test-tsf-shell-build.ps1`
- `tools\test-m08-modern-toolbar-contract.ps1`
- `tools\test-m09-settings-panel-contract.ps1`
- `tools\test-m11-ui-modernization-contract.ps1`
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
