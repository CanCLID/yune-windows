# M10 Skin Breadth + Candidate-Window Skinning Plan

> **Status:** active. Broadens the skin system (more built-in skins,
> user-imported skins) and extends the shared Direct2D renderer + active skin to
> the candidate window, so the whole IME surface — toolbar *and* candidate panel —
> looks consistent (the larger part of the "Sogou fancy" impression).
>
> **⚠ Reconciliation with M11 (read before implementing Slice C):** M11 upgrades
> the shared renderer to a DirectComposition frosted-glass surface (`GlassSurface`).
> To avoid building the renderer twice, **Slice C's "move the candidate window onto
> the shared renderer" is superseded by M11 Slice C** — the candidate window should
> ride M11's `GlassSurface`, not a separate GDI→D2D pass. **Hard dependency:**
> candidate-window skinning therefore *waits on* M11 Slice C. Only Slices A and B
> here (second built-in skin, user-imported skins, candidate skin-schema fields +
> back-compat) are independent and can land first. See
> `m11-plan-ui-modernization-cantonese.md` → "Relationship to M10".

**Goal:** prove the skin system with more than one skin, let users bring their own
skins safely, and restyle the candidate window with the same shared renderer/skin.

**Depends on M09:** the skin picker in the settings panel, M08's skin-driven
toolbar glyph labels, and the shared `D2DSurface`. Rich icon/image asset
rendering can be added here only with a renderer path that consumes those assets.

---

## Current Facts (grounded, after M09)

- After M09 the toolbar renders skin-driven glyph labels via the shared
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
1. **Slice A — Second built-in skin** (e.g. light + dark/glass), authored as a
   manifest first and with assets only after the renderer consumes them, to prove
   the schema generalizes; fix any schema gaps.
2. **Slice B — User-imported skins** (`%LOCALAPPDATA%\Yune\WindowsIme\skins-user\`;
   strict validation, safe fallback, nothing executed from a skin).
3. **Slice C — Candidate window skinning** (first extend the skin schema with
   candidate-window fields + back-compat, then move the panel onto the shared
   renderer; keep caret anchoring/paging/guards; verify no latency regression).

## Design Details
- **Second skin (A):** a contrasting skin proves the manifest covers real variation
  (colors, geometry, glyph labels, and icons/images only if an asset renderer
  lands). Any field the toolbar needs but the schema can't express is a schema gap
  to close here.
- **User-imported skins (B):** import = drop a folder with `theme.json` + assets;
  validate strictly (reject/fall back on malformed manifests or unexpected asset
  paths; load only declared colors/geometry/images/SVG — never execute anything).
  The settings-panel skin picker enumerates install + user skins.
- **Candidate window (C) — extend the skin schema FIRST, then migrate the render.**
  The M08 skin manifest only has toolbar fields; the candidate panel needs its own.
  Step 1 (before touching `NativeCandidateWindow`): add candidate-window fields to
  `theme.json` and the loader — **panel background, corner radius, padding, row
  background, highlighted-row background + text, candidate text, comment/annotation
  text, romanization text, and page indicator** — with defaults so **existing
  toolbar-only skins still load** (back-compat: missing candidate fields fall back
  to sane derived values, e.g. from the toolbar palette). Add a contract that a
  toolbar-only skin still loads and that a skin with candidate fields drives the
  panel.
  Step 2: move `NativeCandidateWindow` onto the shared `D2DSurface` + active skin,
  rendering the rows from those fields. Preserve M04 caret anchoring, paging, and
  the owner/foreground guard exactly — render-only. Measure that candidates appear
  as fast as the GDI version (no latency regression), reusing the M04 evidence
  approach.

## Tasks
- [ ] Second built-in skin (manifest first; rendered assets only after the
  renderer consumes them); close schema gaps.
- [ ] User skins folder + strict validation + fallback; malformed-skin contract.
- [ ] Extend the skin schema with candidate-window fields (panel bg, radius,
  padding, row bg, highlight bg/text, candidate text, comment text, romanization
  text, page indicator) + back-compat defaults; contract for toolbar-only skins.
- [ ] Move the candidate window onto the shared D2D renderer + skin; latency check
  vs M04.
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
