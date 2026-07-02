# M07 Persistent Composition and Candidate Selection Implementation Plan

> **Status:** active (next milestone, planned 2026-07-01). Selected after F3 was
> found to be an architecture gap rather than a small fix. **M06 remains the
> current focus**; M07 is captured here and starts once M06 lands (or in parallel
> on the server side, which does not need a DLL swap).

**Goal:** make the IME support real incremental composition — typing a
multi-syllable input that is not a single lexicon entry (e.g. `dungdatkyut` →
東突厥) and picking the characters one at a time (東, then 突, then 厥) — with the
composition *advancing* through the input instead of committing the first
candidate and discarding the rest. This is the core "compose a phrase from parts"
capability every IME has. It also makes the **input visible inline at the caret**
while composing (the preedit, e.g. `cak si`), matching yune-web — today the host
field shows nothing until commit.

**The bugs this fixes (F3 + F4):**
- **F3 — selection does not advance the composition.** Picking a candidate for a
  partial input commits only that candidate and clears the whole buffer, throwing
  away the remaining syllables.
- **F4 — the input is not shown inline at the caret.** While composing, the typed
  romanization (`caksi`) is displayed **nowhere** in the host app — the field stays
  empty and only the floating candidate list appears — whereas yune-web shows the
  preedit (`cak si`) inline at the cursor. The caret should show exactly what was
  typed.

Both share one architectural root cause: there is no inline `ITfComposition`, and
no composition state with a lifetime longer than one keystroke — selection never
goes through Rime, and the preedit is never rendered at the caret. F3 is the
*selection* half and F4 is the *display* half of the same missing feature.

**Architecture change:** move from the current **stateless per-keystroke** model
(server replays the whole buffer and destroys the session each call; the DLL fakes
selection by committing candidate text and clearing `buffer_`) to a **persistent
per-client Rime session** driven by incremental operations, with the TSF DLL
rendering Rime's live preedit as a real **inline `ITfComposition`** and committing
to the host app only when Rime commits. This is also the documented prerequisite
for a future learning/userdb milestone (still out of scope here — see Non-Goals).

**Tech Stack:** the shared server + pipe IPC (extended with a session token and
incremental verbs), the linked Rime-compatible `RimeApi` (already exposes
everything needed — no ABI change), and TSF `ITfComposition`/`ITfCompositionSink`.
Iterate via the M03 dev loop.

---

## Current Facts (grounded)

- **The engine already exposes candidate selection and composition — no Yune ABI
  change is needed.** The linked `RimeApi` (`rime_get_yune_windows_profile_api()
  ->upstream`) defines `create_session`, `process_key`, `get_context`
  (`RimeContext` with the composition/preedit and the candidate menu),
  `get_commit`, `select_candidate` and `select_candidate_on_current_page`, and
  `candidate_list_from_index` (`../yune/crates/yune-rime-api/src/abi.rs:279`,
  `:284`, `:289`, `:339`, `:342`, `:348`). Yune's own frontend-client tests
  exercise the full persistent-session composition/selection flow —
  `crates/yune-rime-api/tests/frontend_client/composition_dictionary_userdb.rs`
  and `input_editing_runtime.rs` — and are the **reference contract** M07 should
  mirror.
- **A selection can commit *and* keep composing (critical for F3).** Yune's oracle
  test proves selecting a candidate returns the committed segment while the
  composition stays active with the remaining input:
  `yune_web_select_candidate` returns `commits: [東]`, `context.input: "datkyut"`,
  `status.is_composing: true`, then each further select commits the next segment
  until input is empty (`../yune/crates/yune-rime-api/tests/yune_web.rs:2103-2142`).
  So the frontend must handle three cases per response — commit + remaining preedit,
  preedit-only advancement, and final commit — and must **not** treat any commit as
  "composition ended."
- **The Windows server is stateless per keystroke.** `ProcessInput`
  (`src/server/yune_windows_server.cpp:741-804`) does `create_session` → replay
  **all** keys from `request.input` → read commit/context → `destroy_session`,
  every request. It never calls `select_candidate*`, and its `Require()` presence
  list (`:481-496`) does not yet include the selection/`candidate_list_from_index`
  slots (they must be added).
- **The DLL has no real composition and fakes selection.** There is no
  `ITfComposition`; the typed romanization lives only in `buffer_` and is rendered
  **nowhere inline** in the host app — the composing field stays empty (F4). The
  native candidate window carries only the candidate list: `CandidateWindowState`
  (`src/candidate_window/yune_windows_candidate_window.h:18-26`) has no input /
  preedit field, so it cannot show what was typed either. Pressing a number to
  "select" a candidate takes `last_candidates_[index].text`, inserts it via
  `InsertTextEditSession`, and clears `buffer_`/candidates
  (`src/tsf/yune_windows_tsf.cpp:1224-1243`). Nothing is routed to Rime, so a
  partial selection cannot advance the composition (F3).
- **The pipe is one request/response per connection.** `ServeOnce`
  (`src/server/yune_windows_server.cpp`) accepts one client, reads one request,
  writes one response, disconnects. Persistent composition therefore needs a
  **session token** carried in each request (server maps token → live
  `RimeSessionId`), not a persistent socket — this fits the existing one-shot pipe.
- **Depends on / interacts with M05 and M06.** Applied option/schema state (M05)
  must be set on the persistent session. The server must not die mid-session and
  must survive client disconnects (M06 F2a server resilience) — otherwise a live
  composition is lost. Land M06 F2 first or alongside.

## Non-Goals

- **No learning / userdb.** Persistent sessions are the prerequisite for learning,
  but `disable_learning` stays **forced** this milestone (D-05 privacy). Learning,
  select-index feedback persistence, and secure-context suppression are a separate
  later milestone.
- **No Yune engine or default `rime_get_api()` ABI change** — selection is already
  exposed.
- No AI/prediction/associated-phrase features.
- No always-on language bar / broker work (those are their own milestones).

## Slice Map (sequence)

1. **Slice A — Server: persistent per-client session + incremental protocol**
   (server, fast `dev-reload-server` loop).
2. **Slice B — TSF: inline `ITfComposition` + Rime-driven selection/commit**
   (DLL, holder-free `dev-reload-tsf` swap).
3. **Slice C — Verification + evidence** (dev loop + holder-free live proof).

Slice A is server-only and iterates instantly; it can proceed in parallel with
M06's DLL work. Slice B is the larger change (replaces the buffer/candidate-only
model with a real composition).

## Design Details

### Slice A — Server: persistent per-client session + incremental protocol

- **Session lifetime.** Introduce a server-side map `token → { RimeSessionId,
  last_used }`. A `begin` op creates a Rime session, applies M05 state
  (schema + options, `disable_learning` forced), returns a token. Subsequent ops
  carry `session=<token>`. Idle sessions are garbage-collected after a bounded TTL
  (and on explicit `end`). Cap the number of live sessions.
- **Every compose response returns three independent things** (this is the crux —
  see Current Facts: a select can commit *and* keep composing): `committed_text`
  (text to insert into the host doc **this step**, may be empty), the remaining
  `composition`/`input` + `is_composing` (the preedit to keep showing, may be
  non-empty even when `committed_text` is set), and the current `candidates`. Never
  conflate "has `committed_text`" with "composition ended" — read `is_composing`
  (from `get_status`) / empty input for that.
- **Incremental verbs** (extend `ParseRequest`/`Process`):
  - `op=compose-begin` → `{ token, composition, candidates, state }`.
  - `op=compose-key\nsession=<t>\nkey=<vk-or-char>\n.` — feed one key; after it,
    read `get_commit` (→ `committed_text`), `get_context` (→ preedit + candidates),
    `get_status` (→ `is_composing`). Return all three.
  - `op=compose-select\nsession=<t>\nindex=<i>\n.` —
    `select_candidate_on_current_page(session, i)`, then the same read-back.
  - `op=compose-commit-raw\nsession=<t>\n.` — commit the **raw input** verbatim for
    F6 (Enter): read the raw input (e.g. `get_input`) and return it as
    `committed_text`, then clear the session. **Do not** use `commit_composition`
    for this — that commits the *candidate* composition, not the raw letters
    (`../yune/crates/yune-rime-api/src/lib.rs:1258`).
  - `op=compose-commit` (Space: commit the selected/first candidate) /
    `op=compose-back` / `op=compose-page` / `op=compose-cancel` / `op=compose-end`.
  - Every response carries the M05 state block (consistency with the protocol).
- **Return the composition, not just candidates.** Read `RimeContext.composition`
  (preedit, cursor, selection) so the DLL can render an inline preedit; keep the
  existing candidate extraction (`candidate_list_begin/next/end`, plus
  `candidate_list_from_index` for paging beyond the first page).
- Add `select_candidate_on_current_page`, `candidate_list_from_index` (and any
  compose slots used) to the server `Require()` list.
- **Verify:** a dev harness (extend `dev-repl`) drives `begin` → `compose-key`×N
  for `dungdatkyut` → `compose-select 0` (東) → observe the composition advance to
  `datkyut` with 突-family candidates → select again → `厥` → final commit yields
  東突厥. All on the fast `dev-reload-server` loop. Add a server contract mirroring
  Yune's `frontend_client` composition test.

### Slice B — TSF: inline composition + Rime-driven selection/commit

- **Real composition.** Implement `ITfComposition` via
  `ITfContextComposition::StartComposition` and an `ITfCompositionSink`. On each
  key, call `op=compose-key`, then set the composition range's text to Rime's
  preedit (with the composing display attribute / underline) and place the caret
  per Rime's cursor. Keep the native candidate window for the menu, anchored to the
  composition as today (M04 caret anchoring).
- **Selection routes to Rime — and every response is handled in three cases.**
  Number keys (and later, clickable candidates) send `op=compose-select index=<i>`.
  For **every** compose response (key or select), do both, independently:
  1. if `committed_text` is non-empty, **insert it into the host doc now** (it may
     be a partial segment like 東); and
  2. if `is_composing` is still true, **keep/update the inline composition** to the
     remaining preedit and refresh candidates; only when `is_composing` is false /
     input is empty do we **end** the composition.
  So a select can *both* commit 東 *and* keep composing `datkyut` — that is exactly
  the F3 flow (see Current Facts / the `yune_web` oracle). **Never** treat a
  non-empty `committed_text` as "composition ended."
  - Backspace → `compose-back`; Esc → `compose-cancel`.
  - **Space** → `compose-commit` (commit the selected/first candidate, Chinese).
  - **Enter** → `compose-commit-raw` (F6: commit the raw typed letters), then end.
- **Replace the fake-selection path.** Remove the "grab `last_candidates_[index]`
  + clear `buffer_`" logic (`:1224-1243`); `buffer_` as a raw-romanization store
  goes away in favor of the server-held session + the composition preedit.
- **Composes with existing features:** ascii-mode pass-through (no composition when
  ascii), the lone-Shift/preserved-key toggles (M05), punctuation (M04), and the
  **M06 fixes must all be preserved in the new model** — F1 (Shift-aware
  punctuation forwarding), F5 (`WH_KEYBOARD_LL` lone-Shift), and especially **F6
  (Enter commits the raw letters, Space commits the candidate)**, which now maps to
  `op=compose-commit-raw` (raw input via `get_input`) on Enter — **not**
  `commit_composition`. Toggling mid-composition commits or cancels the composition
  first (reuse `CommitOrClearCompositionBeforeStateChange`).
- **Verify live:** holder-free swap; the `dungdatkyut` → 東 → 突 → 厥 flow inline in
  a real app, plus regression of single-word commit, punctuation, paging, toggles.

### Slice C — Verification + evidence

- Record the persistent-composition proof under `docs\evidence\m07\` (summary +
  contract mirroring the M05/M06 shape), including the multi-syllable compose flow
  and the regression set. Update roadmap/README/decisions (record: persistent
  per-client session is the new composition model; learning still deferred).

## Tasks

### Task 1: Slice A — server session + protocol
- [ ] Session token map + lifecycle (`begin`/`end`, idle GC, cap), applying M05
  state with `disable_learning` forced.
- [ ] `compose-*` verbs returning composition + candidates + commit; add the
  selection/`candidate_list_from_index` slots to `Require()`.
- [ ] `dev-repl` compose harness + a server contract mirroring Yune's
  `frontend_client` composition test. Verify on `dev-reload-server`. Commit to
  `main`.

### Task 2: Slice B — TSF inline composition + selection
- [ ] `ITfComposition` + `ITfCompositionSink`; render Rime preedit; route
  key/select/back/cancel/commit to the session; commit only on Rime commit.
- [ ] Remove the fake-selection/`buffer_`-commit path; keep ascii pass-through,
  toggles, punctuation working (commit/cancel composition on toggle).
- [ ] Contracts + build; holder-free live-verify. Commit to `main`.

### Task 3: Slice C — evidence + docs
- [ ] `docs\evidence\m07\` summary + contract; roadmap/README/decisions updates.
  Move this plan to history. Commit to `main`.

## Reviewer Questions (for the user / Codex)

- **Session identity:** a session token carried in each one-shot request (fits the
  current pipe) vs. a persistent per-client pipe connection (bigger IPC change)?
  Token is the leaner default.
- **Session GC:** idle TTL and max-live-session policy, and how it composes with
  M06 F2a (server resilience) — a dropped client must not leak or lose sessions.
- **Composition editing depth for M07:** minimal (append key, select, backspace,
  Esc, commit) vs. full caret movement / mid-composition editing? Recommend
  minimal first, matching the reported bug.
- **Preedit display:** full segmented preedit with per-segment highlight, or a
  single underlined preedit string? Recommend the simpler underlined string first.

## Completion Gates

- Typing `dungdatkyut` and selecting 東, then 突, then 厥 composes 東突厥 — the
  composition **advances** through the input (does not clear after the first pick)
  — and the final result is committed as the full phrase.
- **(F4)** While composing, the input romanization is shown **inline at the caret**
  via `ITfComposition` (Rime's preedit, e.g. `cak si`) — parity with yune-web — not
  an empty field with only a floating candidate list. Text reaches the host app
  only on Rime commit; single-word commit, phrase commit, punctuation, paging, and
  the M05/M06 toggles all still work.
- The server holds a persistent per-client session with bounded lifetime, survives
  client disconnects (M06 F2a), and applies M05 state with `disable_learning`
  forced.
- No Yune ABI widening; learning/userdb remains deferred. Live DLL-side proof
  captured under `docs\evidence\m07\`.
