# M11 UI Modernization + Cantonese Localization Evidence

Status: Slices A (native theming + Cantonese) and B (Win11 DWM polish) are implemented non-elevated. Slice C (glass toolbar) is **scaffolding only** — the toolbar still renders flat; the real WinRT composition host-backdrop backend is **deferred** to an on-device follow-up (see "Glass toolbar" below). Live visual proof remains approval-gated because it would require loading the TSF DLL in real desktop hosts and visually checking the toolbar over app content.

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
- Glass toolbar — **scaffolding only; real glass deferred**:
  - **The toolbar is unchanged and still renders flat.** It stays on the existing
    `WS_EX_LAYERED` + `UpdateLayeredWindow` Direct2D path; `GlassSurface` is
    currently a thin wrapper over `D2DSurface`, not a composition renderer.
  - What landed is metadata + a mechanism-dispatch scaffold: `glass_mechanism`,
    `glass_tint`/opacity/blur/highlight skin fields (back-compatible defaults), and
    an `ApplyToolbarGlassBackdrop` switch. **The default skin uses
    `glass_mechanism = host_backdrop`, whose `ApplyHostBackdropBrush` only sets the
    `DWMWA_USE_HOSTBACKDROPBRUSH` flag — a no-op without a WinRT composition tree —
    so there is NO visible glass yet.** The `accent_acrylic` and `dwm_acrylic`
    branches are opt-in stubs (not default); accent-acrylic on a layered window
    would blur the whole window rectangle (a rectangular halo behind the rounded
    pill), which is exactly the limitation the composition path is meant to solve.
  - **Deferred to an on-device Slice C follow-up:** the real WinRT
    `Windows.UI.Composition` host-backdrop backend — `Compositor.CreateHostBackdropBrush`,
    dropping `WS_EX_LAYERED` for `WS_EX_NOREDIRECTIONBITMAP`, a rounded composition
    clip, and click-through hit-testing. It is **not implemented** here because it
    cannot be visually verified without a live TSF host (approval-gated), and
    landing it blind would risk the working toolbar. The static-tint/layered path
    remains the guaranteed non-hollow, no-activate, draggable fallback, preserving
    the M08/M09 clone-trail + no-activate + drag invariants.
- Localization note: `luna_pinyin_octagram` intentionally renders as
  `朙月拼音（八卦）` (fully Cantonese) rather than mirroring yune-web's Latin
  `朙月拼音 + Octagram`, to keep the panel free of Latin text per the
  all-Cantonese goal (see M11 plan appendix).

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
