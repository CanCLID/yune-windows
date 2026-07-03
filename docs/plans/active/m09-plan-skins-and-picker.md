# M09 Skin Picker, More Skins, and Candidate-Window Skinning Plan

> **Status:** active (next after M08). Depends on M08's shared Direct2D renderer +
> skin-manifest architecture. Turns the single-default-skin toolbar into a
> user-choosable, extensible skin system and extends the same look to the
> candidate window.

**Goal:** let the user **choose** a skin, ship a **second** built-in skin so the
system is proven with more than one, allow **user-imported** skin folders, and
**apply the shared skin to the native candidate window** so the whole IME surface
looks consistent (the bigger part of the "Sogou fancy" impression).

**Depends on M08:** the shared `D2DSurface`, the skin-manifest schema + loader,
and `op=set-skin` already exist. M09 is mostly UI (a picker) + assets + applying
the renderer to a second surface.

---

## Current Facts (grounded, after M08)

- M08 ships a Direct2D toolbar driven by a `skins/<name>/theme.json` manifest, with
  a default skin, `op=set-skin` persistence, and a reusable `D2DSurface`.
- The candidate window is still GDI (`NativeCandidateWindow::Paint`,
  `src/candidate_window/yune_windows_candidate_window.cpp:393`); it already has
  monitor-clamped positioning and an owner/foreground guard from M04.
- `YuneWindowsSettings.exe` (M05) is the natural home for a skin picker; it already
  drives server `op=` verbs.
- D-04 keeps the candidate window native for latency — Direct2D is native, so
  restyling it with the shared renderer is compatible.

## Non-Goals

- No WebView2/animated/mascot skins (that is the later `YuneWindowsUiHost.exe`
  milestone if native skins prove insufficient).
- No change to candidate ordering/paging/latency behavior — this is a render-layer
  restyle only.
- No Yune ABI change; `disable_learning` forced.

## Slice Map (sequence)

1. **Slice A — Skin picker** in `YuneWindowsSettings.exe` (choose among installed
   skins via `op=set-skin`; live preview).
2. **Slice B — Second built-in skin** (proves the manifest generalizes; e.g. a
   light and a dark skin).
3. **Slice C — User-imported skins** (a per-user skins folder; validation + safe
   fallback).
4. **Slice D — Candidate window on the shared renderer** (apply the D2D renderer +
   active skin to the candidate panel).

## Design Details

- **Skin picker (A):** enumerate `skins/` (install) + the user skins dir; show
  name/preview; selecting one sends `op=set-skin` (server persists it). **No
  server→client push exists** (M08 deferred that), so the picker renders a **live
  preview inside the settings window itself**, and the actual toolbars/candidate
  windows in other apps pick up the new skin on their **next focus / state refresh**
  (the DLL already reads the state block on `op=get-state`/focus and per-keystroke
  responses — extend it to re-load the skin when the skin name in the state block
  changes). If instant cross-app switching is ever wanted, that is the deferred
  UI-host push channel, not this milestone.
- **Second skin (B):** author a contrasting skin (e.g. dark/glass) purely as a
  manifest + assets — no code change — to prove the schema covers real variation.
  Fix any schema gaps found.
- **User-imported skins (C):** a `%LOCALAPPDATA%\Yune\WindowsIme\skins-user\`
  folder; import = drop a folder with `theme.json` + assets; strict validation
  (reject or fall back on malformed manifests or unexpected asset paths — do not
  execute anything from a skin, only load declared colors/geometry/images/SVG).
- **Candidate window (D):** move `NativeCandidateWindow` to the shared `D2DSurface`
  + active skin (rounded translucent panel, skinned highlight/comment/romanization
  rows). Keep caret anchoring, paging, and the owner/foreground guard exactly as
  M04 left them; this is render-only. Verify latency is unchanged (candidate
  appears as fast as before).

## Tasks
- [ ] Skin picker in `YuneWindowsSettings.exe` (enumerate + `op=set-skin` + preview).
- [ ] Second built-in skin (manifest + assets only); close any schema gaps.
- [ ] User skins folder + strict validation + fallback; contract for malformed
  skins.
- [ ] Candidate window on the shared D2D renderer + skin; verify latency unchanged.
- [ ] Evidence under `docs/evidence/m09/`; contracts; roadmap/decisions. Commit to
  `main`.

## Reviewer Questions
- Skin preview in the picker: static thumbnail vs. a live render of the actual bar?
- Candidate-window restyle in M09, or split to its own milestone if M08/M09 run
  long?
- User-skin trust model: how strict on asset paths / image formats (no code,
  declared assets only)?

## Completion Gates
- The user can pick among at least two built-in skins from the settings UI, which
  shows a live preview; the toolbar (and candidate window, if Slice D lands) in
  other apps adopt the skin on their next focus / state refresh.
- A user-imported skin folder loads and applies; a malformed one is rejected with a
  clean fallback to the default (no crash, nothing executed from the skin).
- The candidate window (if restyled) matches the skin and shows no latency
  regression versus M04.
- No WebView2; no Yune ABI change; `disable_learning` forced. Evidence under
  `docs/evidence/m09/`.
