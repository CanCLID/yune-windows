# M06 Host Compatibility Pass Implementation Plan

> **Status:** active. Selected 2026-07-01 as the milestone after M05. This is a
> verification-first milestone: prove the M04/M05 typing controls hold across the
> real desktop hosts the user types Cantonese in every day, fix what breaks, and
> capture host-matrix evidence.

**Goal:** turn the single-Notepad live proof from M04/M05 into broad,
recorded confidence. Verify caret-anchored candidates, no-orphan behavior,
paging, punctuation, the lone-Shift 中/英 toggle, preserved-key toggles, English
pass-through, the focus-scoped language bar, live settings changes, cross-app
state reconciliation, and the native Windows input-mode indicator across a tiered
host matrix (Chromium, an Electron editor, a chat app, rich-edit, console). Fix
the in-scope defects that surface — most likely the deferred `WH_KEYBOARD_LL`
lone-Shift fallback — and defer host classes that genuinely need another
milestone (sandboxed/AppContainer hosts belong to the cold-start / broker work).

**Nature of this milestone (read first):** M02–M05 were code + non-elevated
contracts. M06 is **operator-driven live verification** with a small amount of
supporting tooling. The bulk of the work is a human typing into each host and
recording what happens; the code work is (a) a repeatable evidence harness and
(b) fixes for whatever breaks. The central logistics constraint is the
**TSF DLL-holder problem**: every GUI host that receives input loads and *locks*
`YuneWindowsTSF.dll`, so a DLL re-swap needs a holder-free session. The plan is
sequenced to **swap once, observe everything, then batch fixes** so we pay the
holder/reboot cost as few times as possible.

M06 also **absorbs known typing-blocker bugs the user is already hitting** — not
just defects discovered during the observation pass. These are enumerated in
*Folded-in Typing-Blocker Fixes* below and are fixed in the same batch and
verified in the same holder-free session as the Slice B/C work, so a single swap
covers both verification and the known fixes.

**Architecture:** no new runtime architecture. We exercise the existing installed
path (shared server + TSF DLL + native candidate/language-bar windows +
`YuneWindowsSettings.exe`) and add verification tooling under `tools\` plus
evidence under `docs\evidence\m06\`. Any product fixes land in the existing DLL /
server code and are re-proven on the M03 dev loop.

**Tech Stack:** the M03 dev loop (`dev-reload-server` instant; `dev-reload-tsf`
holder-free swap), PowerShell evidence collectors modeled on
`tools\collect-m01-compatibility-environment.ps1`, the TSF diagnostic log
`tsf-events.log` (`src/tsf/yune_windows_tsf.cpp:206`), and manual operator
verification in each host.

---

## Current Facts (grounded)

- **M04/M05 are only proven in one dev-owned Notepad window.** The M05 closeout
  (`docs/evidence/m05/summary.md`, "Holder-free Live Proof") manually confirmed
  `ngohaig` input, lone-Shift 中/英 toggle, English pass-through, PageUp/PageDown
  paging, punctuation, and the settings entrypoint — all in **Notepad only**.
  Chromium cross-app, native input-mode indicator observation, and multi-host
  language-bar/settings breadth are explicitly listed as follow-up coverage in
  both `docs/evidence/m04/summary.md` and `docs/evidence/m05/summary.md`.
- **The lone-Shift `WH_KEYBOARD_LL` fallback is NOT implemented** (M05 "Deferred").
  Lone-Shift 中/英 relies on TSF key-sink delivery of `VK_SHIFT` key-up. This is
  the single most likely thing to be flaky in non-Win32 hosts (Chromium/Electron
  route keyboard input differently), and M06 is where we get the evidence to
  decide whether the fallback becomes real work.
- **M04 removed the candidate-window fallback anchor.** The M04 review deleted the
  old top-left fallback and now *rejects* clipped or zero-size `GetTextExt`
  anchors (`docs/roadmap.md`, M04 section). Consequence: in a host where
  `ITfContextView::GetTextExt` misbehaves (common in web/Electron fields), the
  candidate window may **mis-anchor or fail to show** rather than fall back — a
  prime thing to observe.
- **The native candidate window and language bar are focus-scoped GDI popups**
  (`WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW|WS_EX_TOPMOST`) with owner-window and
  foreground guards (M04/M05). Cross-app focus models differ; orphan/stale/
  duplicate behavior must be observed per host.
- **State reconciliation** is: server returns the state block on *every* response,
  and the DLL sends `op=get-state` on `OnSetFocus(TRUE)`/`ActivateEx` as a short
  existing-server-only query (M05). Cross-app drift should therefore self-correct
  on focus — this is directly testable by toggling mode in host A and switching to
  host B.
- **The native 中/英 indicator** is driven via the registered input-mode
  compartment (`GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT`,
  `src/tsf/yune_windows_tsf.cpp:1461`). Whether Windows actually paints it varies
  by host and by the language-bar/notification-area settings.
- **Cold start is still synchronous** (`kServerLaunchReadyWaitMs = 15000`). The
  first keystroke after a cold server can freeze the foreground app. This is a
  **separate milestone**; in M06 we note it when observed but do not fix it, and
  we warm the server before timing-sensitive checks.
- **A compatibility-environment collector already exists**
  (`tools\collect-m01-compatibility-environment.ps1`) writing a JSON snapshot of
  OS/build/arch — the exact template for a per-run M06 environment capture.
- **Holder evidence tells us which hosts the user runs.** The M03 TSF-reload
  safe-abort recorded holders: Chrome, Claude, Codex, Explorer, GitHub Desktop,
  Notepad, NVIDIA Overlay, and **Telegram** (`docs/roadmap.md`, M03 section). So
  Chromium and Telegram are confirmed daily hosts; WeChat was not observed.

## Non-Goals

- **No cold-start / broker work** (`kServerLaunchReadyWaitMs`); that is its own
  milestone. Observe and record the freeze; do not fix it here.
- **No sandboxed / AppContainer host support** (UWP, Store apps, some Electron
  sandboxes, Start-menu search). Those need the per-user broker; in M06 we
  *document* their behavior as expected-limitation, not as M06 bugs to fix.
- No Yune engine change and no default `rime_get_api()` ABI widening.
- Keep `disable_learning` forced on every session (D-05 privacy).
- No production signing, packaging, or WebView2 settings work.
- Tooling must **never force-close non-dev holder apps** or mutate live IME
  machine state without explicit current-session approval (M03 rule).

## Host Matrix (tiers)

Confirm/adjust Tier 1 to match your actual daily apps (see Reviewer Questions).

- **Tier 1 — must verify (daily Cantonese typing):**
  1. **Notepad** — Win32 baseline / regression anchor (already proven; re-confirm).
  2. **Chromium browser** (Chrome or Edge) — address bar, a plain `<input>`, and a
     `contenteditable`/rich web editor (e.g. a webmail compose or Google Docs-like
     field). This is where most typing happens and where `GetTextExt` and key
     delivery most often differ.
  3. **Electron editor** — VS Code (or the user's daily editor), including the
     editor pane and the integrated find box.
  4. **Chat app** — Telegram (confirmed installed). Message compose box.
- **Tier 2 — should verify (breadth):**
  5. **Rich edit** — WordPad, or Word if installed.
  6. **Windows Terminal / console** — different text-input model; expect reduced
     candidate/anchoring fidelity, record what works.
  7. **File Explorer** rename field + a **non-UWP** search/address box.
  8. **WeChat** — only if the user installs it (not observed in holder evidence).
- **Tier 3 — observe & document as expected-limitation (defer to broker):**
  9. UWP / AppContainer hosts: Start-menu search, a Microsoft Store app, any
     sandboxed Electron. Record behavior; failures here are **not** M06 blockers.

## Behavior Checklist (the columns, per host)

Each host gets a row; each item is Pass / Fail / N-A / Note. Items 1–5 are M04
typing quality; 6–12 are M05 controls.

1. **Composition + caret anchoring** — candidate window appears *at the caret*,
   not a screen corner; text composes inline.
2. **No orphan / correct lifecycle** — switching apps mid-composition hides the
   popup; no stuck/duplicate window; it follows caret movement.
3. **Paging** — PageUp/PageDown and `-`/`=` move candidate pages; page indicator
   correct.
4. **Punctuation / full-width** — punctuation commits full-width; composing
   punctuation commits the current candidate first, then inserts.
5. **Commit order** — multi-word commit inserts left-to-right (the caret-advance
   fix), not reversed.
6. **Lone-Shift 中/英 toggle** — a lone Shift press toggles; **Shift+letter still
   types a capital with no toggle**; autorepeat/hold does not spuriously toggle.
7. **Preserved-key toggles** — `Ctrl+Shift+2` cycles schema, `Ctrl+Shift+3`
   toggles full/half, and neither *also* toggles 中/英.
8. **English pass-through** — in ascii mode, latin text types straight through
   with no buffering/candidate UI.
9. **Language bar** — appears focus-scoped, segments are clickable and reflect
   state, hides on focus loss, no stale/duplicate bar across apps.
10. **Settings live-apply** — a change in `YuneWindowsSettings.exe` (schema + the
    three toggles) takes effect in the focused host without restart.
11. **Cross-app reconciliation** — toggle mode in host A, focus host B → B reflects
    the new mode (state block + `op=get-state` on focus).
12. **Native indicator** — the Windows 中/英 input-mode indicator reflects state.

## Folded-in Typing-Blocker Fixes (user-reported)

Known bugs the user hits in daily typing, fixed as part of this milestone (batched
with Slice C and verified in the same holder-free session). This list is open —
append new user-reported blockers here as they come in.

### F1 — Shift+punctuation forwards the *unshifted* character (full-width ？！：… broken)

- **Symptom:** in Chinese mode, Shift+/ commits full-width ／ instead of ？. The
  shifted forms of the other symbol keys are likewise wrong (Shift+; → ； instead
  of ：, Shift+' → ＇ instead of ＂, Shift+- , Shift+= , Shift+, , Shift+. …), and
  the shifted number-row keys (！＠＃…) are not forwarded to Rime at all — they
  leak through as half-width.
- **Root cause:** `PunctuationInput(WPARAM key)`
  (`src/tsf/yune_windows_tsf.cpp:117`) maps each virtual key to its **unshifted**
  US character and ignores the Shift modifier, so `CommitCompositionForPunctuation`
  (`:1625`) sends e.g. `/` to Rime and Rime returns the full-width of `/`. The
  number-row shifted symbols are absent from the table entirely, and
  `ShouldHandleKeyDown` (`:1580`) routes digits `1`–`9` to candidate-selection /
  passthrough regardless of Shift, so shifted digits never reach the punctuation
  path.
- **Fix — make punctuation forwarding Shift-aware and send the *actual* produced
  character to Rime:**
  - `PunctuationInput(WPARAM key, bool shift)` returns the shifted US symbol when
    `shift`: OEM_1 `;`/`:`, OEM_2 `/`/`?`, OEM_3 `` ` ``/`~`, OEM_4 `[`/`{`,
    OEM_5 `\`/`|`, OEM_6 `]`/`}`, OEM_7 `'`/`"`, COMMA `,`/`<`, PERIOD `.`/`>`,
    MINUS `-`/`_`, PLUS `=`/`+`; and for digit keys `0`–`9` return the shifted
    symbol **only** when `shift` (`1`→`!` … `9`→`(`, `0`→`)`), empty otherwise so
    unshifted digits keep their existing selection/passthrough path.
  - `IsPunctuationKey(key, shift)` = `!PunctuationInput(key, shift).empty()`.
  - Determine shift at each call site with `(GetKeyState(VK_SHIFT) & 0x8000) != 0`
    — pure, reflects the current message's state, and identical in
    `OnTestKeyDown`/`OnKeyDown`. Do **not** couple to the lone-Shift `shift_down_`
    state machine.
  - Thread `shift` through `ShouldHandleKeyDown`, the `OnKeyDown` punctuation
    branch (`:1244`), `OnTestKeyDown` (so its eaten decision matches `OnKeyDown`),
    and `CommitCompositionForPunctuation` (`:1627`). Reorder `ShouldHandleKeyDown`
    so the digit branch (`:1580`) matches **unshifted** digits only and shifted
    digits fall through to the `IsPunctuationKey` check.
  - Keep ascii-mode passthrough intact: in ascii mode with an empty buffer,
    shifted punctuation and digits still pass through as half-width.
- **Verify:** in Chinese mode, Shift+/ → ？, Shift+1 → ！, Shift+; → ：,
  Shift+' → ＂, and `,`/`.`/`\` produce their Rime-mapped full-width forms;
  Shift+letter still types a capital and does **not** toggle 中/英; English mode
  still yields half-width. Add a source/behavior contract asserting
  `PunctuationInput` is shift-differentiated (OEM_2 shifted ≠ unshifted; a digit
  is empty unshifted and non-empty shifted).
- **Layout note:** this preserves the existing hard-coded **US-layout** assumption.
  A layout-correct derivation via `ToUnicodeEx` is a possible follow-up but carries
  dead-key / `OnTestKeyDown` side-effect risk; out of scope unless a non-US layout
  need appears.

## Slice Map (sequence)

1. **Slice A — Verification harness** (tooling; non-elevated, no holder problem).
2. **Slice B — Observation pass** (one holder-free swap; operator-driven; record
   the full matrix; fix nothing yet).
3. **Slice C — Triage + fixes** (batch in-scope fixes; re-verify affected cells on
   the dev loop / a second holder-free swap).
4. **Slice D — Closeout evidence** (summary + contract + roadmap; naming contract
   stays green).

Do A first (cheap, and it makes B repeatable). B must complete for **all** hosts
before C, so fixes are batched against a full findings list rather than triggering
a reboot per bug.

## Design Details

### Slice A — Verification harness

- Add `docs\evidence\m06\` with a **host-matrix template** (`matrix.md`) encoding
  the tiers × the 12-item checklist as an empty, fillable table, plus a short
  per-host operator script ("open host, type `ngohaig`, press Shift, …") so runs
  are consistent and repeatable.
- Add `tools\collect-m06-compatibility-environment.ps1`, modeled on
  `tools\collect-m01-compatibility-environment.ps1`: capture OS caption/build/
  arch, the installed `YuneWindowsTSF.dll` / `YuneWindowsServer.exe` SHA-256 and
  versions, the active profile state (`YuneWindowsProfileTool.exe --state`), and
  the tail of `tsf-events.log`, into `docs\evidence\m06\environment.json`. This
  ties each matrix run to an exact build so evidence is not ambiguous.
- Add a tiny helper to snapshot a labeled window of `tsf-events.log` around a test
  (start marker → run → capture) so per-host anomalies (e.g. `candidate_anchor_
  failed`, key events) are attributable. Reuse existing log fields; add none.
- **No product code changes in Slice A.** Verify by running the collector and
  confirming a well-formed `environment.json`. Commit to `main`.

### Slice B — Observation pass

- **One holder-free swap.** In a holder-free session, `dev-reload-server` +
  `dev-reload-tsf` to put the current `main` build live (the M05 build is already
  live per closeout; re-confirm SHA via the collector). Warm the server first so
  the 15s cold-start does not contaminate latency observations.
- **Run the matrix top-down** (Tier 1 → 2 → 3), filling `matrix.md` for every
  host × checklist cell with Pass/Fail/N-A + a note, and capturing a
  `tsf-events.log` window per host. Capture screenshots for the visual items
  (caret anchoring, language bar) where a claim needs a picture.
- **Fix nothing during Slice B.** The output is a complete findings list. Classify
  each Fail inline as `bug` (product defect, in scope), `host-limit` (host-inherent
  / needs broker, defer), or `cosmetic`.
- **Operator-in-the-loop:** the typing is manual and only the user can do it. GPT
  prepares the exact per-host scripts and records results from the user's reports
  and the captured logs/screenshots; it does not fabricate results.
- Verify: `matrix.md` has a recorded result for every Tier-1 cell and every
  finding is classified. Commit the filled matrix + logs to `main`.

### Slice C — Triage + fixes

- **Start from the folded-in known bugs** (*Folded-in Typing-Blocker Fixes*):
  they are already root-caused and do not need the observation pass to justify
  them. Land them first (server fixes on the instant loop; DLL fixes batched into
  the holder-free swap), then move to the Slice B findings.
- **Prioritize the discovered findings by likelihood (from Current Facts):**
  - **Lone-Shift key-up delivery (item 6).** If any Tier-1 host fails to toggle on
    lone Shift, implement the deferred **`WH_KEYBOARD_LL` fallback** for lone-Shift
    detection (Weasel's approach): a per-thread/low-level hook that detects a
    lone-Shift key-up and drives the same `op=set-option` path, guarded so
    Shift+other-key never toggles and so it composes cleanly with the existing TSF
    key-sink path (no double-toggle). Add a source/behavior contract mirroring
    `tools\test-tsf-ime-state-hotkey-contract.ps1`. Note any interaction with an
    OS/other-IME "Shift to switch language" setting.
  - **Candidate anchoring in web/Electron fields (items 1–2).** If `GetTextExt`
    yields no/clipped anchor and the window mis-places or fails to show, decide a
    scoped, principled fallback (e.g. anchor to the composition range's
    `GetScreenExt`, or the host caret via `GUITHREADINFO`) — without reintroducing
    the top-left corner fallback M04 deliberately removed.
  - **Language-bar / reconciliation / indicator** fixes as findings dictate.
- Each fix: implement, add/extend a non-elevated contract, `dev-reload-server`
  (server fixes iterate instantly) or a **batched** holder-free `dev-reload-tsf`
  re-swap (DLL fixes), then re-verify only the affected host × item cells and
  update `matrix.md`. Batch DLL fixes to minimize holder-free sessions/reboots.
- **Defer explicitly** anything classified `host-limit` (record it as
  expected-limitation with the reason; do not force it in M06). Commit each fix
  directly to `main`.

### Slice D — Closeout evidence

- Write `docs\evidence\m06\summary.md` + `summary.json` in the same shape as
  `docs/evidence/m05/`: Final Status, Executed Proof (contracts/builds), the
  completed host matrix (Tier-1 fully; Tier-2/3 as far as run), Holder-free Live
  Proof (which hosts, which build SHA, on what date), Follow-up Coverage, and
  Deferred (with the lone-Shift-fallback decision recorded either way).
- Add `tools\test-m06-evidence-summary-contract.ps1` (mirror
  `tools\test-m05-evidence-summary-contract.ps1`) asserting the summary keeps
  executed proof, host matrix, live proof, follow-up, and deferred sections
  distinct and that `summary.json` parses.
- Update `docs/roadmap.md` (close the "broader M04/M05 compatibility" gate to the
  extent proven; move remaining host classes to the broker/dogfood rows),
  `README.md`, `docs/requirements.md`, and `docs/decisions.md` as needed. Record
  the lone-Shift decision in `docs/decisions.md`.
- Move this plan to `docs/plans/history/m06-plan-host-compatibility-pass.md` and
  update `docs/plans/active/README.md`.
- **Verify the whole closeout:** `git diff --check`, changed-PowerShell parser
  pass, `tools\test-m06-evidence-summary-contract.ps1`,
  `tools\test-milestone-naming-contract.ps1` (M06 additions must not trip it), and
  `summary.json` parse. Commit to `main`.

## Tasks

### Task 1: Slice A — verification harness
- [ ] Add `docs\evidence\m06\matrix.md` (tiers × 12-item checklist template +
  per-host operator scripts).
- [ ] Add `tools\collect-m06-compatibility-environment.ps1` (env + build SHA +
  profile state + `tsf-events.log` tail → `docs\evidence\m06\environment.json`).
- [ ] Add a labeled `tsf-events.log` window-capture helper.
- [ ] Run the collector; confirm well-formed output. Commit to `main`.

### Task 2: Slice B — observation pass
- [ ] One holder-free `dev-reload-server` + `dev-reload-tsf`; confirm live build
  SHA via the collector; warm the server.
- [ ] Operator runs the matrix Tier 1 → 3; GPT records every cell + captures
  per-host logs/screenshots; classify each Fail (`bug`/`host-limit`/`cosmetic`).
- [ ] Commit the filled `matrix.md` + evidence to `main`.

### Task 3: Slice C — triage + fixes
- [ ] **F1 (Shift+punctuation):** make `PunctuationInput`/`IsPunctuationKey`
  shift-aware, thread shift through the key handlers, add the digit-row shifted
  symbols, add the shift-differentiation contract; re-verify Shift+/ → ？ etc.
- [ ] Land any further folded-in typing-blocker fixes (F2, F3, …) as they are added.
- [ ] Lone-Shift: if any Tier-1 host fails item 6, implement the `WH_KEYBOARD_LL`
  fallback + contract; else record lone-Shift as confirmed reliable.
- [ ] Candidate anchoring: fix web/Electron anchoring failures with a principled
  fallback (no top-left corner regression).
- [ ] Language-bar / reconciliation / indicator fixes as findings dictate.
- [ ] Re-verify affected cells (batched holder-free re-swap for DLL fixes);
  update `matrix.md`. Commit each fix to `main`.

### Task 4: Slice D — closeout
- [ ] `docs\evidence\m06\summary.md` + `summary.json`;
  `tools\test-m06-evidence-summary-contract.ps1`.
- [ ] Update roadmap, README, requirements, decisions (record lone-Shift
  decision). Move plan to history; update active README.
- [ ] Run the closeout verification set incl. the naming contract. Commit to
  `main`.

## Reviewer Questions (for the user / Codex)

- **Tier-1 hosts:** confirm the daily set — Notepad + Chromium (Chrome or Edge?) +
  Telegram + which editor (VS Code)? Add/remove any app you actually type
  Cantonese in daily. Is WeChat installed (Tier-2), or skip it?
- **Lone-Shift fallback trigger:** implement the `WH_KEYBOARD_LL` fallback only if
  Slice B shows a Tier-1 host failing lone-Shift, or build it proactively because
  Electron/Chromium key-up delivery is known-risky?
- **Scope of anchoring fixes:** if web/Electron caret anchoring is unreliable, is a
  best-effort screen-ext/`GUITHREADINFO` fallback in scope for M06, or do we record
  it as a follow-up and keep M06 to toggles/lifecycle verification?
- **Console fidelity:** for Windows Terminal, is reduced candidate/anchor fidelity
  acceptable-and-documented, or a fix target?

## Completion Gates

- Every **Tier-1** host has a recorded result for all 12 checklist items in
  `docs\evidence\m06\matrix.md`; Tier-2/3 recorded as far as run, with Tier-3
  failures documented as expected-limitation (broker milestone), not M06 bugs.
- Every finding classified `bug` is fixed and re-verified, or explicitly deferred
  with a recorded reason.
- Every **folded-in typing-blocker fix** (F1 and any later Fn) is implemented,
  has a contract, and is live-verified — including F1: in Chinese mode Shift+/ →
  ？, Shift+1 → ！, and the other shifted symbols map correctly, with Shift+letter
  still capitalizing and English mode still half-width.
- The **lone-Shift reliability decision is recorded**: either confirmed reliable
  across Tier-1 hosts, or the `WH_KEYBOARD_LL` fallback is implemented and proven.
- Candidate anchoring works (or has a principled, non-corner fallback) in the
  Tier-1 web/Electron fields, or the limitation is recorded with rationale.
- Evidence lives under `docs\evidence\m06\` with a passing
  `tools\test-m06-evidence-summary-contract.ps1`; `docs/roadmap.md` reflects the
  proven breadth; `tools\test-milestone-naming-contract.ps1` still passes.
- No Yune ABI widening; `disable_learning` stays forced; the inline candidate
  window stays native; no cold-start/broker or sandboxed-host work smuggled in.
```
