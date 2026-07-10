# M12 - Skin Platform

> **Status:** planned; blocked on installed acceptance of the current hash-pinned
> M10 + M11 tree. Do not change the server, TSF DLL, settings executable, or
> built-in skin files while that acceptance build is under test.

## Goal

Ship a bounded, manifest-only V1 skin platform with more than one built-in skin,
transactional user-skin installation, one validated catalog shared by the
server, TSF DLL, and settings app, and stable revisioned IPC. This milestone does
not change the Yune engine ABI or migrate the candidate renderer; M13 consumes
the completed catalog.

## Locked V1 boundaries

- A skin is one JSON manifest containing colors, typography, geometry, segment
  labels, and candidate styling. V1 accepts no PNG, SVG, executable content,
  asset paths, includes, or network references.
- Built-in skins are package-owned. Add an equal-sized dark/static built-in skin
  named `midnight` to exercise same-size acrylic/static toolbar switching.
- User manifests live only at
  `%LOCALAPPDATA%\Yune\WindowsIme\skins-user\<canonical-id>\theme.json`.
- Normal uninstall/reinstall deliberately deletes `skins-user`. Non-elevated
  development DLL/server swaps leave it intact.
- Skin identity is ASCII case-insensitive to match Windows path identity. After
  syntax validation, ASCII-fold IDs to lowercase for catalog keys, storage
  directories, counting, IPC, and active state. Built-in canonical IDs are
  reserved; invalid, missing, or deleted active skins fall back atomically to
  `default`.
- Preserve M10's effective-backdrop schema: `glass_mechanism` and consumed
  `glass_fallback=static_tint` remain valid; the removed inert `glass_tint`,
  `glass_tint_opacity`, `blur_amount`, and `highlight_intensity` fields remain
  unknown and rejected.
- No animated skin engine, WebView2, Electron, HTML, executable extension,
  candidate ordering/paging change, or Yune ABI change. `disable_learning`
  remains forced.

## Implementation order

### 1. Shared definition and strict parser

1. Add dependency-free shared `SkinDefinition` and `SkinCatalog` code used by
   the server, TSF DLL, and settings executable.
2. Parse the complete input and require `schema_version: 1`; trailing content is
   an error.
3. Reject malformed or truncated JSON, duplicate keys, unknown keys, missing
   required fields, and a whole manifest when any field is invalid.
4. Enforce all of the following before a manifest can enter the catalog:
   - IDs match `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`;
   - each manifest is at most 64 KiB;
   - the display name is valid UTF-8 with at most 128 Unicode scalar values,
     and each segment label has at most 16 Unicode scalar values;
   - at most 32 valid user skins are admitted;
   - every geometry value is finite and within its documented bound; and
   - every color is a valid RGBA value.
5. Derive the lowercase canonical ID before collision checks. Reserve every
   built-in ID case-insensitively and reject a user manifest that collides with
   one. Reject Windows reserved device basenames (`con`, `prn`, `aux`, `nul`,
   `com0`-`com9`, and `lpt0`-`lpt9`). Treat two externally supplied user
   manifests whose IDs ASCII-fold to the same value as a catalog collision.
   Reject the entire user-catalog candidate and preserve the previously
   published catalog; on first load publish built-ins only. Never let directory
   enumeration choose a winner or partially recover a colliding manifest.
6. Derive a stable `skin_revision` from canonical validated content, not file
   timestamps or directory enumeration order.
7. If external state contains more than 32 otherwise valid user manifests,
   reject the user-catalog candidate as a unit rather than selecting an
   enumeration-dependent subset. Preserve the previously published catalog; on
   first load, publish built-ins only and fall back to `default`.

### 2. Transactional user-skin installation

The native settings app provides an explicit **Import skin manifest** action.
V1 imports exactly one selected `theme.json`; it does not import a directory or
copy referenced assets.

1. Read no more than 64 KiB plus one sentinel byte from the selected source and
   validate it completely with the shared parser before creating or changing the
   destination.
2. Derive the destination only from the validated lowercase canonical ID.
   Never accept a destination path from the manifest, follow manifest-relative
   paths, or pass an arbitrary source path through IPC. Re-importing `Foo` and
   `foo` addresses the same canonical `foo` skin and replacement path.
3. Resolve the destination beneath `skins-user`, reject path escape and reparse
   points in the managed destination path, and create only the one safe-ID
   directory needed for `theme.json`.
4. Build the prospective user catalog with this ID inserted or replaced before
   touching the destination. Reject the import if it would exceed 32 valid user
   skins, collide, or make the candidate catalog invalid.
5. Write the validated original bytes to a unique temporary file in the target
   directory, flush and close it, then atomically replace `theme.json` with a
   write-through rename. Re-importing the same user ID replaces the prior
   manifest atomically. A validation, write, flush, or replace failure leaves the
   previous installed manifest and active catalog unchanged.
6. Remove abandoned temporary files best-effort without deleting a prior valid
   manifest. Never delete or overwrite a built-in skin.
7. After a successful replace, request one catalog reload and select the skin
   only after the rebuilt catalog reports the imported ID and revision. Import
   success does not implicitly make an unconfirmed skin active.
8. A reload/IPC failure after the atomic file replacement reports
   `installed_reload_pending`: the new manifest remains installed on disk, while
   the previously published catalog and active selection remain authoritative
   until a later successful reload. Do not claim that the prior manifest remains
   on disk after the replacement commit point.

External deletion or corruption is detected on the next reload and triggers the
same atomic `default` fallback if the removed skin was active. A separate
skin-removal UI is not required for V1.

### 3. Catalog IPC, state, and settings

1. Add `op=list-skins`, returning each valid skin's lowercase canonical ID,
   display name, origin (`built_in` or `user`), and content revision.
2. Add `op=reload-skins`, rebuilding the complete validated catalog from the
   package and user roots. Invalid files are excluded with bounded diagnostic
   reasons; a partial manifest never enters the catalog. Build the candidate
   catalog off to the side and publish it atomically only after the complete
   rebuild succeeds. Overflow of the 32-user limit rejects the user candidate as
   specified above.
3. Make `op=set-skin` ASCII-fold a syntactically valid ID, then reject unknown,
   invalid, or reserved-collision IDs and return the canonical active ID.
4. Add `skin_revision` to state responses as the stable fingerprint for the
   active skin's validated content.
5. Update the settings picker and preview to use catalog responses rather than a
   hard-coded list. Preserve protocol IDs separately from localized labels.
6. Cache parsed definitions by `{skin_id, skin_revision}` so toolbar and key
   updates never reread an unchanged manifest. A catalog reload invalidates only
   entries whose content revision changed or disappeared.
7. Keep the server authoritative for active-skin state and fallback. The TSF DLL
   and settings executable must not read or write `state\ime-state.json`
   directly.

## Non-elevated verification

### Parser and catalog security

- Reject malformed, truncated, oversized, duplicate-key, unknown-key, missing,
  non-finite, out-of-range, invalid-RGBA, unsafe-ID, built-in-ID collision, and
  path-escape manifests. Reject over-length display names and segment labels as
  whole-manifest failures, with length measured in Unicode scalar values.
- Prove `default`/`Default` built-in reservation and `Foo`/`foo` user identity,
  replacement, counting, list, reload, and `set-skin` behavior are consistent
  with one canonical directory and catalog entry.
- Reject every Windows reserved device basename case-insensitively, including
  `com0`-`com9` and `lpt0`-`lpt9`, before any destination directory is created.
- Prove the 64 KiB cap, 32-user-skin limit, reserved IDs, whole-manifest
  rejection, deterministic enumeration, and content-stable `skin_revision`.
- Prove a same-fold external collision rejects the user-catalog candidate as a
  unit, preserves the previous catalog, and publishes built-ins only on first
  load.
- Prove invalid or deleted active skins fall back atomically to `default` with
  no transient unknown active ID.

### Import and lifetime

- Prove first import, atomic replacement of an existing user ID, and successful
  reload/select using the reported revision.
- Inject validation, short-write, flush, rename, reparse-point, and destination-
  collision failures before the replacement commit point; the previous
  manifest/catalog/active state must remain intact.
- Inject catalog-reload and IPC failure after replacement; the new file remains
  installed, the previous published catalog/active state remains authoritative,
  and a later successful reload converges to the installed revision without
  implicit selection.
- Prove normal uninstall/reinstall deletes user skins while non-elevated dev
  swaps preserve them.

### IPC and consumers

- Prove `list-skins`, `reload-skins`, `set-skin`, and state-response behavior
  across server, TSF, settings, and dev-REPL paths.
- Prove `default` and `midnight` are selectable, equal-sized switching does not
  recreate the toolbar HWND, and unchanged `{skin_id, skin_revision}` updates do
  not reread or reparse a manifest.

## Completion gates

- The strict shared parser and catalog pass every bounded/security case.
- `default`, `midnight`, and one valid transactionally imported user manifest
  are selectable through revisioned catalog IPC.
- Failed pre-commit import/replacement and invalid/deleted active-skin cases
  preserve an atomic valid state; post-commit reload failure follows the
  explicit installed-but-not-published contract above.
- Storage, uninstall/reinstall deletion, and dev-swap preservation rules are
  proven.
- Evidence lands under `docs/evidence/m12/`, roadmap and decisions are
  reconciled, and no Yune engine ABI change is introduced.
