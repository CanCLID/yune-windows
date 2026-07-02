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
- **Candidate anchoring rejects bad `GetTextExt`, then falls back to
  `GetScreenExt`.** The anchor edit session takes a clipped/zero-size `GetTextExt`
  rect as "no text ext" and, when it has none, falls back to `GetScreenExt`
  (view/field rect, top-left, sized 24×24) —
  `src/tsf/yune_windows_tsf.cpp:936-954`. Consequence: in a host where
  `GetTextExt` misbehaves (common in web/Electron fields), the candidate window
  still **shows but mis-anchors** to the field/window corner instead of the caret,
  rather than not showing at all — a prime thing to observe. (This corrects an
  earlier note that said the fallback was removed entirely.)
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

- **No full cold-start / broker build** (a per-user broker/autostart that keeps
  the server warm across the whole session and works in AppContainer hosts); that
  remains its own milestone. M06 *does* take the bounded subset in F2 — server
  resilience so a slow op cannot kill the server, plus an async warm-up + capped
  key-path wait so cold launch never hard-freezes the foreground app — but not the
  autostart/broker/AppContainer work.
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
  - **Paging keys are unshifted-only.** The `-`/`=` candidate-paging block
    (`OnKeyDown`, `VK_OEM_MINUS`/`VK_OEM_PLUS`, `src/tsf/yune_windows_tsf.cpp:1216`)
    must match only the **unshifted** keys, so Shift+`-` / Shift+`=` reach the
    punctuation path (forwarding `_` / `+`) instead of being swallowed as
    page-prev/next while composing. Mid-composition, treat them like composing
    punctuation (commit the current candidate first, then insert).
- **This is what the "Shift+= → =" / "no ——" report was.** Forwarding the shifted
  char is the whole fix: the deployed `default.yaml` punctuator already maps input
  `_` → `——`, `+` → `＋` (first candidate), and `=` → `＝` (see
  `../yune/apps/yune-web/public/schema/build/default.yaml:185-193`; the Windows
  server deploys the same `default.yaml`). So Shift+= must forward `+` (→ `＋`, not
  `=`) and Shift+- must forward `_` (→ `——`). **No schema change needed** — this is
  purely the Windows-side shift-awareness bug; the Chinese-keyboard glyphs come
  from Rime, matching yune-web.
- **Verify:** in Chinese mode, Shift+/ → ？, Shift+1 → ！, Shift+; → ：,
  Shift+' → ＂, **Shift+= → ＋** (not `=`), **Shift+- → ——**, and `,`/`.`/`\`
  produce their Rime-mapped full-width forms; Shift+letter still types a capital and
  does **not** toggle 中/英; English mode still yields half-width. `-`/`=` still page
  candidates while composing (unshifted). Add a source/behavior contract asserting
  `PunctuationInput` is shift-differentiated (OEM_2 and OEM_PLUS shifted ≠ unshifted;
  a digit is empty unshifted and non-empty shifted).
- **Layout note:** this preserves the existing hard-coded **US-layout** assumption.
  A layout-correct derivation via `ToUnicodeEx` is a possible follow-up but carries
  dead-key / `OnTestKeyDown` side-effect risk; out of scope unless a non-US layout
  need appears.

### F2 — Toggling back to Chinese freezes the IME for seconds to ~30s

- **Symptom:** after typing in English and hitting Shift to return to Chinese, the
  IME is unresponsive for a few seconds up to ~30s — no keys register — then it
  recovers. Recurs during a session, not just on first use.
- **Root cause (two compounding faults):**
  1. **A single request-level failure kills the server, forcing a full cold
     restart.** `ServeOnce` (`src/server/yune_windows_server.cpp:867-888`) rethrows
     on any failure — including `Require(WriteFile…)` / `Require(FlushFileBuffers…)`
     — and `wmain` (`:915-921`) exits the process on it. The DLL's own query timeout
     (`kServerQueryTimeoutMs = 5000`, `src/tsf/yune_windows_tsf.cpp:57`) cancels I/O
     and closes the pipe when a response is slow, so the server then fails its write
     to the now-closed pipe and terminates. The server does **not** idle-exit (the
     `do { ServeOnce } while(!args.once)` loop, `:909-911`, is persistent), so the
     recurrence is death-by-exception, not idle shutdown.
  2. **Cold start blocks the UI/key thread through a full Rime deploy.** The
     `YuneRuntime` constructor runs a synchronous full deploy
     (`start_maintenance`/`join_maintenance_thread`/`deploy_config_file`/
     `deploy_schema`/`deploy`, `:498-524`) and only *then* is the pipe created
     (`ServeOnce`, after `runtime(args)` in `wmain:908`). The DLL launches the
     server and blocks the key thread in `WaitForSharedServerPipe(
     kServerLaunchReadyWaitMs = 15000)` (`:390`) plus `5000ms × up to 3` query
     timeouts, so the foreground app freezes until deploy finishes — which for a
     cold jyut6ping3 build can exceed the 15s budget.
  - Combined: a slow op kills the server (fault 1); the relaunch pays the full
    synchronous deploy on the key thread (fault 2) → the recurring freeze.
- **Fix:**
  - **F2a (server resilience — clear M06 bug):** a per-request failure must never
    terminate the server. Wrap the per-connection work so the serve loop catches
    and logs per-request exceptions / pipe-I/O errors and **continues serving**;
    only a fatal `YuneRuntime` construction/deploy failure should exit. A client
    that timed out and disconnected mid-response must be a no-op, not a
    server-killer.
  - **F2b (responsiveness mitigation — bounded, M06):** stop hard-freezing the key
    thread on cold launch.
    - **Warm the server asynchronously** on `ActivateEx` / first focus: a
      background thread calls `RequestSharedServerLaunch` (already mutex+cooldown
      guarded) so the deploy runs before the user types. Guard it with **one
      in-flight warm-up flag** (no thundering herd of launch threads) and have the
      thread **hold a DLL lifetime ref** (`DllAddRef`/`DllRelease`) so the module
      cannot unload while it runs.
    - **Cap the synchronous key-path wait** so a not-yet-ready server never blocks
      the foreground app for many seconds. **Decide pass-through vs. eaten in
      `OnTestKeyDown` and keep `OnKeyDown` consistent:** if the test reported the
      key eaten, `OnKeyDown` must eat/drop it on a server-not-ready failure rather
      than leak the same key into the host; if the test reported not-eaten, both
      pass it through. Never a 15s launch-wait on the UI thread; the next keystroke
      retries against the now-warming server.
- **Boundary:** the *complete* elimination of cold start — a per-user
  broker/autostart keeping the server warm across the whole session and working in
  AppContainer hosts — stays the separate **Non-blocking cold-start / broker**
  milestone. F2 is only the subset that stops the freeze blocking daily typing.
- **Verify:** (1) force a slow/failed response (e.g. client disconnects mid-reply)
  and confirm the server process **survives** and answers the next request; (2)
  after an English stretch, toggling En→Cn does **not** hard-freeze the foreground
  app (worst case a brief no-candidate moment, not a dead keyboard). Add a server
  contract asserting a client disconnect during response does not exit the server
  and a subsequent request on the same process succeeds.

### F5 — Lone-Shift 中/英 toggle never works in Telegram (+ intermittent freeze)

- **Symptom:** in Telegram Desktop, hitting Shift **never** toggles 中/英. Typing
  sometimes works and sometimes the IME is frozen.
- **Two parts:**
  - **The freeze is F2.** The "sometimes frozen" is the F2 cold-start / server-death
    freeze — Telegram sitting idle during an English chat is a prime trigger — and
    F2's fix covers it.
  - **Lone-Shift never toggling is the anticipated key-up delivery failure, now
    confirmed in a real Tier-1 host.** Telegram Desktop is a Qt app; the TSF key
    sink is not receiving the `VK_SHIFT` key-**up** that the lone-Shift state machine
    (`OnKeyUp`, `src/tsf/yune_windows_tsf.cpp:1292`) needs, so the toggle never
    fires. This is exactly the risk M06 flagged for non-Win32 hosts.
- **Fix — implement the `WH_KEYBOARD_LL` low-level keyboard-hook fallback**
  (promoted from reactive to **required**: Telegram confirms a Tier-1 host fails
  without it). This is the approach Weasel and other IMEs use. Design constraints:
  - **Process singleton, focus-gated.** Install one process-wide hook (not one per
    `TextService`), and only act on the toggle when a Yune `TextService` is the
    focused/active service — so a background instance never toggles.
  - **Do no COM/TSF/server work in the hook callback.** An `LL` hook must return
    fast and runs off the service's apartment thread. On detecting a lone-Shift
    key-up, **post/defer** the toggle onto the owning TSF thread (e.g. a posted
    message) which then runs the existing `op=set-option` path.
  - **Physical-key double-toggle guard.** In Win32 hosts the normal `OnKeyUp`
    (`src/tsf/yune_windows_tsf.cpp:1287`) *and* the hook may both see the lone-Shift
    key-up. Guard with a physical-key event token (e.g. debounce on the key event's
    identity/time) so exactly one toggle fires.
  - The lone-Shift detection must still honor the F5 guards: Shift+other-key never
    toggles; autorepeat/hold does not re-arm.
- **Verify:** in Telegram (and every Tier-1 host) a lone Shift toggles 中/英;
  Shift+letter still capitalizes with no toggle; no double-toggle in Win32 hosts
  where both the sink and the hook see the key-up. **Confirm the hook actually
  resolves Telegram** (rule out Telegram intercepting Shift itself); if a host
  swallows Shift entirely, record it as a host-limit. Note any interaction with an
  OS / other-IME "Shift to switch language" setting. Extend the hotkey contract for
  the hook path.

### F6 — Enter should commit the raw typed letters, not a Chinese candidate

- **Symptom:** while composing Chinese, pressing Enter to commit the typed letters
  as-is (e.g. `caksi`) instead commits the first Chinese candidate — there is no way
  to output the literal romanization.
- **Root cause:** `OnKeyDown` handles `VK_SPACE` and `VK_RETURN` in **one branch**
  (`src/tsf/yune_windows_tsf.cpp:1251-1274`) that commits `response.commit_text` or
  the first candidate. Enter has no distinct "commit the raw input" behavior.
- **Fix — split Enter from Space.** **Space** keeps committing the selected / first
  candidate (Chinese). **Enter** with a non-empty composition commits the **current
  composition buffer** (the romanization the user typed), then clears — in the
  current model `CommitText(context, <widened buffer_>)`, no conversion and no
  candidate. Enter with an empty buffer still passes through as a newline.
  - **Precision:** `buffer_` is already **normalized to lowercase** on input
    (`LowerAscii`, `src/tsf/yune_windows_tsf.cpp:1138`), so Enter commits the
    lowercased romanization (`caksi`), not original physical casing. Preserving
    typed case would require storing the raw case in the buffer — out of scope for
    F6; call it out if it matters.
- **Verify:** in Chinese mode, type `caksi` + Enter → the host receives literal
  `caksi` (not 測試); Space still commits 測試; Enter with no composition still
  inserts a newline. Add a contract for the split Enter/Space commit behavior.
- **M07 note:** M07 rewrites the key/commit path (inline composition); it must
  **preserve** this Enter = commit-raw-input behavior against the persistent
  session's raw input.

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
- Lone-Shift delivery (item 6) is already folded in as **F5** — the
  `WH_KEYBOARD_LL` fallback is required (Telegram); implement it here with its
  contract rather than treating it as a discovered finding.
- **Prioritize the remaining discovered findings by likelihood (from Current
  Facts):**
  - **Candidate anchoring in web/Electron fields (items 1–2).** If `GetTextExt`
    yields no/clipped anchor, the window currently falls back to `GetScreenExt`
    (field/window corner, `:944-954`) — so it shows but mis-anchors away from the
    caret. If the observation pass finds this jarring, improve the fallback (e.g.
    the host caret via `GUITHREADINFO`, or a better composition-range ext) — keep a
    principled fallback, do not regress to a whole-screen top-left corner.
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
  symbols, make the `-`/`=` paging block unshifted-only (so Shift+=/Shift+- reach
  punctuation), add the shift-differentiation contract; re-verify Shift+/ → ？,
  Shift+= → ＋, Shift+- → ——.
- [ ] **F2a (server resilience):** the serve loop catches per-request / pipe-I/O
  failures and continues; a client timeout/disconnect no longer kills the server;
  add the server-survives-disconnect contract.
- [ ] **F2b (responsiveness):** async server warm-up on activation/focus; cap the
  synchronous key-path wait so cold launch never hard-freezes the foreground app.
- [ ] **F5 (Telegram lone-Shift):** implement the `WH_KEYBOARD_LL` lone-Shift
  fallback (confirmed required by Telegram), guarded against double-toggle where
  both the sink and hook fire; extend the hotkey contract; confirm it resolves
  Telegram. (The Telegram freeze is covered by F2.)
- [ ] **F6 (Enter commits raw):** split Enter from Space — Enter commits the raw
  typed letters verbatim, Space commits the candidate; add the commit-split contract.
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
- **Lone-Shift fallback (resolved → required, tracked as F5):** Telegram (Qt)
  confirms a Tier-1 host where lone-Shift never toggles, so the `WH_KEYBOARD_LL`
  fallback is in scope. Open sub-question: a single process-wide hook, or a
  per-thread hook installed/removed with focus? And how to guard against a
  double-toggle in Win32 hosts where both the sink and the hook see the key-up.
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
- Every **folded-in typing-blocker fix** (F1, F2, and any later Fn) is
  implemented, has a contract, and is live-verified:
  - **F1:** in Chinese mode Shift+/ → ？, Shift+1 → ！, **Shift+= → ＋** (not `=`),
    **Shift+- → ——**, and the other shifted symbols map correctly; `-`/`=` still
    page candidates while composing (unshifted); Shift+letter still capitalizes and
    English mode stays half-width.
  - **F2:** a client timeout/disconnect no longer kills the server (it answers the
    next request), and toggling En→Cn after an English stretch does not hard-freeze
    the foreground app. Full broker/autostart stays deferred.
  - **F5:** a lone Shift toggles 中/英 in **Telegram** and the other Tier-1 hosts
    (via the `WH_KEYBOARD_LL` fallback), with no double-toggle in Win32 hosts and
    Shift+letter still capitalizing.
  - **F6:** in Chinese mode, Enter commits the raw typed letters (`caksi`) verbatim
    while Space still commits the candidate (測試); Enter with no composition is a
    newline.
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
