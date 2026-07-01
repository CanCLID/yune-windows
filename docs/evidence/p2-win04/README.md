# P2-WIN04 Evidence

P2-WIN04 implementation evidence was captured on 2026-07-01.

## Runtime Evidence

- `slice-a-dev-repl-ngohaig.txt` - dev REPL proof that `ngohaig` candidate
  comments no longer expose raw dictionary CSV blobs.
- `slice-a-dev-reload-server-output.txt` and
  `slice-a-dev-reload-server-result.json` - installed-server reload evidence
  for the initial comment-hygiene slice.
- `final-dev-repl-ngohaig-paging.txt` - dev REPL proof that the server returns
  30 clean candidates for client-side paging.
- `final-dev-repl-punctuation.txt` - dev REPL proof that punctuation input `.`
  returns full-width U+3002 through the existing Rime `get_commit` path.
- `final-dev-reload-server-output.txt` - installed-server reload after the
  final server changes; readiness passed.

## DLL-Side Verification Boundary

- `tsf-holders-before-dll-reload.json` - read-only holder snapshot before any
  TSF DLL reload attempt.
- `tsf-dll-reload-blocker-20260701.md` - live TSF reload and app typing proof
  were not attempted because non-dev processes held `YuneWindowsTSF.dll`.

The DLL-side candidate-window and key-handling implementation is covered by
static contracts, the TSF shell build, and the candidate-window smoke test in
this closeout. Live caret placement, no-orphan behavior, PageUp/PageDown paging,
and full-sentence punctuation typing still require a holder-free desktop session.
