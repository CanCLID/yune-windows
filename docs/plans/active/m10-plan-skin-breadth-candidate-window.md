# M10 Skin Breadth + Candidate-Window Skinning Plan

> **Status:** blocked on M11D. The installed M11 clone/drag sub-gate passed, but
> no M10 implementation begins until profile activation, lone-Shift state
> transition, toolbar visibility, and the complete four-host installed gate are
> deterministic. M11 supplies the reusable native composition foundation; M10
> retains ownership of skin breadth, catalog/import behavior, and candidate
> rendering.

## Goal

Ship a bounded manifest-only V1 skin system with more than one built-in skin,
safe user imports, stable server/TSF/settings catalog behavior, and a fully
restyled native candidate window without changing the Yune engine ABI.

## Locked V1 boundaries

- Skins contain manifest data only: colors, typography, geometry, segment
  labels, and candidate styling. V1 accepts no PNG, SVG, executable content, or
  asset paths.
- User manifests live at
  `%LOCALAPPDATA%\Yune\WindowsIme\skins-user\<id>\theme.json`.
- Normal uninstall/reinstall deliberately deletes user skins. Non-elevated dev
  DLL/server swaps leave them intact.
- Built-in IDs are reserved. Invalid, missing, or deleted active skins
  atomically fall back to `default`.
- No animated/WebView2 skin engine, no candidate ordering/paging behavior
  change, no Yune ABI change, and `disable_learning` remains forced.

## Recommended order

### Slice A - Shared skin foundation

1. Add an equal-sized built-in dark/static skin, `midnight`, to exercise
   same-size acrylic/static switching.
2. Introduce dependency-free shared `SkinDefinition` and `SkinCatalog` code for
   the server, TSF DLL, and settings app.
3. Parse JSON with full-input validation and require `schema_version: 1`.
4. Reject duplicate keys, unknown keys, malformed/truncated JSON, and whole
   manifests containing an invalid field.
5. Enforce:
   - IDs matching `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`;
   - a 64 KiB manifest limit;
   - at most 32 user skins;
   - finite bounded geometry; and
   - valid RGBA colors.
6. Cache parsed definitions by `{skin_id, skin_revision}` so toolbar and key
   updates never reread unchanged manifests.

### Slice B - Catalog IPC and settings

1. Add `op=list-skins`, returning valid ID, display name, origin, and revision.
2. Add `op=reload-skins`, rebuilding the fully validated catalog.
3. Make `op=set-skin` reject unknown or invalid IDs.
4. Add `skin_revision` to state responses as a stable content fingerprint.
5. Update the settings picker to use catalog responses and preserve the atomic
   `default` fallback when a selected user skin disappears or becomes invalid.
6. Verify normal uninstall/reinstall deletion and dev-swap preservation without
   broadening machine-state scope.

### Slice C - Candidate renderer

1. Benchmark the existing GDI candidate window before migration: 30 cold first
   shows and 500 warm updates.
2. Generalize the DComp device/surface lifecycle independently from
   toolbar-specific drawing.
3. Add active skin ID and revision to `CandidateWindowState`.
4. Move the candidate window to an opaque/static-tint DComp surface. Candidate
   Acrylic is out of scope.
5. Apply the active skin to background, border, radius, padding, rows,
   highlight, candidate text, annotations, and page indicator.
6. Preserve caret anchoring, paging, selection, foreground/owner guards,
   no-activation behavior, sanitized comments, and numbering.
7. Localize `Page n/N` to `頁 n/N`.
8. If DComp initialization fails before first show, destroy the failed window and
   recreate a normally redirected GDI candidate window; never show a blank
   surface.

## Verification

### Catalog contracts

- Reject malformed, truncated, oversized, duplicate-key, unknown-key,
  non-finite, out-of-range, built-in-ID collision, missing, and deleted
  manifests.
- Prove the 32-user-skin limit, reserved IDs, content-stable `skin_revision`,
  whole-manifest rejection, and atomic `default` fallback.
- Prove `list-skins`, `reload-skins`, `set-skin`, and state-response behavior
  across server, TSF, settings, and dev-REPL paths.

### Candidate performance gate

Compared with the GDI baseline:

- warm median and p95 may regress by at most 10% or 1 ms, whichever allowance is
  larger; and
- cold median and p95 may regress by at most 15% or 2 ms, whichever allowance is
  larger.

### Candidate behavior gate

- The active skin/revision drives every candidate visual field.
- `頁 n/N`, caret anchoring, paging, selection, comments, numbering, ownership,
  foreground matching, and no-focus-steal behavior remain correct.
- Forced DComp first-show failure recreates the normally redirected GDI fallback
  and never exposes a blank candidate window.

## Completion gates

- `default` and `midnight` are selectable and exercise equal-sized backdrop
  switching.
- A valid user manifest loads; every invalid case is rejected atomically; normal
  uninstall/reinstall and dev-swap lifetime rules are proven.
- IPC/catalog revision behavior is stable and cached.
- The candidate restyle passes behavior and cold/warm performance gates.
- Evidence lands under `docs/evidence/m10/`, roadmap/decisions are reconciled,
  and no claim relies on M11 toolbar evidence to close M10 candidate gates.
