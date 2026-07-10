# Active Plans

The 2026-07-10 rebaseline removes the historical "M11 before M10" inversion.
See `docs/reference/m10-m13-rebaseline.md` for the complete old-to-new scope and
evidence map.

- `m10-native-ui-presentation-closeout.md` - **implementation complete;
  installed acceptance pending.** Owns the native Cantonese surface,
  DirectComposition toolbar presentation, clone-free ownership/drag/backdrop
  behavior, and settings DPI/resize/scroll usability. The older installed
  clone result remains regression evidence; the current implementation baseline
  still needs hash-pinned toolbar-presentation and settings-usability verdicts.
- `m11-activation-state-reliability.md` - **implementation complete; focused
  non-elevated checks pass; expanded pre-deployment verification and installed
  acceptance remain pending.** Owns profile/focus
  identity, lone-Shift token/parity routing, boot-ID/revision CAS, bounded IPC,
  privacy-safe tracing, and deterministic toolbar eligibility. Its four-host
  gate requires visible-without-sacrificial-toggle behavior, 50 paced exact
  transitions, rapid-burst parity, and previous-host hiding within 250 ms.
- `m12-skin-platform.md` - **planned; blocked on M10 + M11 installed
  acceptance.** Owns the strict manifest-only skin definition/catalog, built-in
  `midnight`, transactional user-manifest import, revisioned catalog IPC,
  caching, lifetime rules, and settings integration.
- `m13-candidate-presentation.md` - **planned; blocked on M12.** It begins with
  a reproducible GDI baseline, which blocks renderer migration. M13 owns the generalized composition lifecycle, complete
  skin-driven native candidate restyle, opaque/static DirectComposition path,
  normally redirected GDI fallback, behavior preservation, `頁 n/N`, and cold/
  warm performance gates.

M10 and M11 may share one approved, hash-pinned deployment, but they receive
separate verdicts. Both must pass before M12 begins; M13 follows M12 and starts
with its baseline slice. Their live execution is a paired closeout: if M11 cannot
make a toolbar eligible in a required host, that M10 host gate is not exercised.
Legacy plans now live in `docs/plans/history/`, and existing `m11*` evidence/test names
remain unchanged as implementation provenance.

Later / unplanned, noted so the settings panel is designed for them:

- Server `customize`+`deploy` path to actually apply the deploy-time **engine
  prefs** (completion/correction/sentence/prediction).
- **Schema import** (bring a new schema; needs the customize/deploy path).
- **Userdb + learning** (import/export + on-device learning; gated by D-05 privacy).
- Per-user `YuneWindowsUiHost.exe` with a single always-on toolbar + animated skins,
  only if native Direct2D skins prove insufficient.

M01 through M09 and the pre-rebaseline source plans are in
`docs/plans/history/`; see `docs/roadmap.md` for the product sequence and other
candidate milestones (cold-start/broker, dogfood packaging).
