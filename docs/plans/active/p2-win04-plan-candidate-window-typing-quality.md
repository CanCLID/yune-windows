# P2-WIN04 Candidate Window And Typing Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** make the installed Yune Windows IME actually pleasant to type with. Fix
the candidate window so it appears at the caret and never orphans, clean up the
candidate comments, and add candidate paging and punctuation/full-width input.

**Architecture:** iterate through the P2-WIN03 dev loop. Comment hygiene is
server-side and rides the proven fast loop (`dev-reload-server`, no reboot, no
holder problem). The candidate-window and input-key changes are TSF-DLL-side and
must be iterated in a holder-free desktop session via `dev-reload-tsf` (close the
apps holding `YuneWindowsTSF.dll`, or reboot, before swapping). Yune remains the
only engine; no default ABI widening.

**Tech Stack:** Win32 TSF COM DLL (C++20), native GDI candidate window, the
shared server + named-pipe line protocol, packaged Yune schema/dictionary, and
the `tools\dev` inner-loop kit.

---

## Current Facts (root causes, grounded)

- **Candidate position is wrong and "random".**
  `ShowCandidates` in `src\tsf\yune_windows_tsf.cpp` (around lines 986-1015)
  computes the anchor cookielessly: it defaults to `RECT anchor = {80,80,96,104}`
  (absolute screen top-left) and, when `GetActiveView`+`GetScreenExt` succeed,
  sets `anchor = screen_ext` (the whole text-**view** rect + 24px). Neither is the
  caret. The window therefore lands at the view/screen top-left, and varies with
  whether `GetScreenExt` succeeds for that app/context. The correct source is
  `ITfContextView::GetTextExt(cookie, range, &rect, &clipped)` on the
  composition/selection range, which requires a read edit-session cookie.
- **Candidate panel can get stuck/orphaned.**
  The candidate window is created as a parentless `WS_POPUP` with
  `WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`
  (`src\candidate_window\yune_windows_candidate_window.cpp` ~line 158), and
  `Hide()` is only `ShowWindow(hwnd, SW_HIDE)` (~line 190). `OnSetFocus(FALSE)`
  (an `ITfKeyEventSink` method) hides it and logs `focus_lost`, but with no owner
  window, any missed hide on an app-switch leaves a topmost panel floating with
  no way to dismiss it.
- **Candidate comments are raw dictionary CSV.**
  The `jyut6ping3` dictionary packs a CSV comment
  (`1,<text>,<jyutping>,...,<glosses>`) that yune-web parses; the server passes
  `context.menu.candidates[i].comment` through unchanged, and the candidate window
  draws it raw (`DrawTextW`, comment column). This is dictionary data meant for
  the web UI, not for display.
- **No paging and no punctuation.** `OnKeyDown` handles a-z, 1-9, space/enter/
  backspace/escape only; `CandidateWindowState` has `page_size`/
  `highlighted_index` but no page index; punctuation keys are not forwarded to the
  server even though the schema has a `punct_translator`.
- **Loop reality (from P2-WIN03):** once the profile is active, the TSF DLL loads
  into every TSF host (chrome, explorer, the agent processes, etc.), so a DLL swap
  needs a holder-free session. Server/schema changes do not.

## Non-Goals

- Do not change Yune engine internals or widen the default `rime_get_api()` ABI.
- Do not modify the shared `apps\yune-web` schema/dictionary in a way that
  regresses the web app; prefer a Windows-side transform or a Windows-only
  `.custom.yaml` patch.
- Do not add learning/userdb or a settings UI in this milestone (separate work).
- Do not weaken any P2-WIN03 dev-tooling safety contract or any elevated
  approval gate.

## Slice Map (sequence)

1. **Slice A - Candidate-comment hygiene (server-side, fast loop).**
2. **Slice B - Candidate window correctness (DLL-side, holder-free session).**
   - B1 caret positioning, B2 no-orphan hide/lifecycle.
3. **Slice C - Candidate paging (DLL-side).**
4. **Slice D - Punctuation / full-width input (DLL-side + schema punct).**

Do Slice A first (cheap, visible, exercises the proven server loop). Batch B/C/D
in a holder-free session because they all reswap the DLL.

## Design Details

### Slice A - Comment hygiene (server)

- In `src\server\yune_windows_server.cpp`, add a comment simplifier applied when
  building each candidate's JSON `comment`: if the comment looks like the
  dictionary CSV, extract the jyutping field (e.g. `ngo5hai6go3`) and drop the
  rest; otherwise pass a short/blank comment. Keep it defensive (a candidate with
  a non-CSV comment stays as-is).
- Rationale for server-side: it does not touch the shared web schema/dict and it
  rides `dev-reload-server` (proven, no holder problem).
- Verify with `tools\dev\dev-repl.ps1 -InputText ngohaig -Once`: candidate
  comments should be clean jyutping (or empty), not CSV.

### Slice B - Candidate window correctness (DLL)

- **B1 caret positioning.** This IME commits directly and keeps no TSF
  composition (only an internal `buffer_`), so there is no composition range to
  anchor on. Add a **new read-only edit session** (do **not** reuse
  `InsertTextEditSession`, which writes committed text) that, with its read
  cookie, calls `context->GetSelection(ec, TF_DEFAULT_SELECTION, ...)` to get the
  caret range, then `ITfContextView::GetTextExt(ec, range, &rect, &clipped)`.
  Fallback chain: selection-range `GetTextExt` -> `GetScreenExt` -> a caret-near
  default. `ComputeCandidateWindowRect` already clamps to the monitor work area,
  so once the anchor is the caret rect the window places below/above correctly.
- **B2 no-orphan hide.** Give the candidate window an **owner** window (the host
  text window from `ITfContextView::GetWnd`) so it is tied to the app's lifetime
  and z-order instead of a parentless topmost. Ensure `Hide()` runs on every
  composition-end/focus-loss path (audit `OnSetFocus(FALSE)`, `Deactivate`,
  commit, escape, empty-backspace, `focus_lost`). Add a foreground guard: if the
  foreground window is not the owning host, hide. Confirm the destructor destroys
  the window. First **diagnose with a live repro** (type, click away
  mid-composition) and check `tsf-events.log` for whether `focus_lost` fires when
  a panel sticks, then harden the path that does not.

### Slice C - Paging (DLL)

- Add a page index to `CandidateWindowState`; handle paging keys in `OnKeyDown`.
  Use `PageUp`/`PageDown` (optionally space-to-next-page) - **do not** use `,`/`.`,
  which Slice D reserves for punctuation. If comma/period paging is ever wanted,
  gate it strictly on the composing state (candidates shown) with a documented
  rule. Ensure enough candidates are available: prefer having the server return a
  larger candidate list and paging client-side first (no protocol/session change).

### Slice D - Punctuation / full-width (DLL + schema)

- Punctuation auto-commits through the schema's `punct_translator`, which surfaces
  via `RimeApi.get_commit` - **not** the menu. The server today never calls
  `get_commit` (it synthesizes `commit_text` from `candidates[0]`; see
  `src\server\yune_windows_server.cpp` ~lines 273/318), so it would miss
  punctuation entirely. Slice D therefore has two parts:
  1. **Server (fast loop):** after `process_key`, call `get_commit`
     (`api_->get_commit`/`free_commit` - part of the existing default `RimeApi`,
     no ABI widening); if committed text exists (e.g. full-width punctuation),
     return it as `commit_text`. Testable via `dev-repl` with a punctuation input,
     before any TSF change.
  2. **TSF (DLL):** forward punctuation keys in `OnKeyDown` so they reach the
     server and the committed punctuation is inserted.
  Tone-digit vs 1-9-selection is moot for toneless input (the smoke used
  `ngohaig`).

## Tasks

### Task 1: Slice A - server comment hygiene
- [ ] Add the comment simplifier in `src\server\yune_windows_server.cpp`.
- [ ] Add a contract asserting the server does not emit raw CSV comments
  (static or a server-response check).
- [ ] Verify via `dev-repl` that `ngohaig` candidates have clean comments.
- [ ] Non-elevated build + host/IPC/candidate smokes pass.
- [ ] Commit directly to `main` (scoped, reviewed) per the repo's direct-main
  workflow.

### Task 2: Slice B - candidate window positioning + no-orphan
- [ ] B1: implement caret positioning via a read edit-session `GetTextExt` with
  the fallback chain; keep `ComputeCandidateWindowRect` clamping.
- [ ] B2: add owner window, audit/complete every hide path, add the foreground
  guard; diagnose the stuck-panel repro first and record findings under
  `docs\evidence\p2-win04\`.
- [ ] Add contracts where static checks are meaningful (e.g. `GetTextExt` used;
  candidate window created with an owner). Note behavioral fixes need live proof.
- [ ] Build; iterate via `dev-reload-tsf` in a holder-free session; live-verify
  the panel appears at the caret and never orphans on app-switch.
- [ ] Commit directly to `main`.

### Task 3: Slice C - paging
- [ ] Add page index + paging keys + page indicator; ensure candidate supply.
- [ ] Live-verify paging reaches later candidates.
- [ ] Commit directly to `main`.

### Task 4: Slice D - punctuation / full-width
- [ ] Server: add a `get_commit` step so auto-committed punctuation is returned;
  verify via `dev-repl` on the fast loop.
- [ ] TSF: forward punctuation keys in `OnKeyDown`.
- [ ] Live-verify typing a full sentence with full-width punctuation.
- [ ] Commit directly to `main` (scoped, reviewed).

### Task 5: Docs
- [ ] Update `README.md`, `docs\roadmap.md`, `docs\requirements.md`,
  `docs\decisions.md` to reflect what shipped and what remains.

## Reviewer Questions (for GPT)

- Is server-side comment simplification the right call vs. a Windows-only
  `.custom.yaml` schema patch (which would also ride `dev-reload-server`)?
- For B1, is a read-only edit session per show acceptable on the key path
  latency-wise, or should the caret rect be cached from the last composition edit?
- For B2, is an owner window the cleanest no-orphan fix, or should the window be
  destroyed (not just hidden) on focus loss?
- Should paging be client-side over a larger candidate list, or a protocol change
  (which couples to future stateful-session/learning work)?

## Completion Gates

- Candidate comments show clean jyutping (or nothing), never raw CSV.
- Candidate window appears at the caret in Notepad and a Chromium field, on the
  correct monitor, and no longer lands in the screen/view top-left.
- No orphaned candidate panel remains after switching apps mid-composition;
  every composition-end path hides the window.
- Paging reaches candidates beyond the first page.
- Full-width punctuation can be typed in a normal sentence.
- Live verification captured under `docs\evidence\p2-win04\`; DLL-side slices
  were reswapped in a holder-free session, no reboot forced by the tooling.
- No default Yune ABI widening; no dev-tooling safety contract weakened.
