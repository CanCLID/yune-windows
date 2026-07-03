# M10 Skin Breadth + Candidate-Window Skinning Plan

> **Status:** active (after M09). Broadens the skin system (more built-in skins,
> user-imported skins) and extends the shared Direct2D renderer + active skin to
> the candidate window, so the whole IME surface — toolbar *and* candidate panel —
> looks consistent (the larger part of the "Sogou fancy" impression).

**Goal:** prove the skin system with more than one skin, let users bring their own
skins safely, and restyle the candidate window with the same shared renderer/skin.

**Depends on M09:** skin-driven toolbar rendering (icons/labels), the skin picker
in the settings panel, and the shared `D2DSurface`.

---

## Current Facts (grounded, after M09)

- After M09 the toolbar renders skin-driven icons/labels via the shared
  `D2DSurface`, and the settings panel has a working skin picker (`op=set-skin`).
- The candidate window is still GDI (`NativeCandidateWindow::Paint`); it has
  monitor-clamped positioning + owner/foreground guard from M04.
- D-04 keeps the candidate window native for latency — Direct2D is native, so
  restyling it with the shared renderer is compatible.

## Non-Goals
- No animated/mascot skins (later `YuneWindowsUiHost.exe`).
- No candidate ordering/paging/latency change — render-layer restyle only.
- No Yune ABI change; `disable_learning` forced.

## Slice Map (sequence)
1. **Slice A — Second built-in skin** (e.g. light + dark/glass), authored as
   manifest + assets only, to prove the schema generalizes; fix any schema gaps.
2. **Slice B — User-imported skins** (`%LOCALAPPDATA%\Yune\WindowsIme\skins-user\`;
   strict validation, safe fallback, nothing executed from a skin).
3. **Slice C — Candidate window on the shared renderer** (apply the D2D renderer +
   active skin to the candidate panel; keep caret anchoring/paging/guards; verify
   no latency regression).

## Design Details
- **Second skin (A):** a contrasting skin proves the manifest covers real variation
  (colors, geometry, icons, labels). Any field the toolbar needs but the schema
  can't express is a schema gap to close here.
- **User-imported skins (B):** import = drop a folder with `theme.json` + assets;
  validate strictly (reject/fall back on malformed manifests or unexpected asset
  paths; load only declared colors/geometry/images/SVG — never execute anything).
  The settings-panel skin picker enumerates install + user skins.
- **Candidate window (C):** move `NativeCandidateWindow` onto the shared
  `D2DSurface` + active skin (rounded translucent panel; skinned
  highlight/comment/romanization rows). Preserve M04 caret anchoring, paging, and
  the owner/foreground guard exactly — render-only. Measure that candidates appear
  as fast as the GDI version (no latency regression), reusing the M04 evidence
  approach.

## Tasks
- [ ] Second built-in skin (manifest + assets only); close schema gaps.
- [ ] User skins folder + strict validation + fallback; malformed-skin contract.
- [ ] Candidate window on the shared D2D renderer + skin; latency check vs M04.
- [ ] Evidence under `docs/evidence/m10/`; contracts; roadmap/decisions. Commit to
  `main`.

## Reviewer Questions
- Candidate-window skin: full panel restyle, or start with background/highlight and
  keep text layout as-is?
- User-skin trust model: allowed asset formats (SVG/PNG only), size limits, path
  containment.

## Completion Gates
- At least two built-in skins selectable from the picker; a user-imported skin loads
  and applies; a malformed one falls back cleanly (no crash, nothing executed).
- The candidate window matches the active skin with no latency regression vs M04.
- No animated/WebView2 skin engine; no Yune ABI change; `disable_learning` forced.
  Evidence under `docs/evidence/m10/`.
