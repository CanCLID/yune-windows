# M04 Evidence Summary

M04 improved daily typing quality: clean candidate comments, larger candidate
supply, caret anchoring, no-orphan candidate-window hardening, paging, and
punctuation/full-width behavior.

## Final Status

- Status: implementation complete
- Evidence retained here: compact summary only
- Raw retained artifacts: none
- Live proof: post-reboot holder-free dev Notepad proof for installed input,
  paging, and punctuation was captured during M05 closeout.
- Remaining coverage: broader Chromium/no-orphan compatibility breadth.

## Proven Behaviors

- Server comments are simplified to display-safe jyutping.
- The server can supply 30 candidates for client-side paging.
- Punctuation can be returned through the existing `get_commit` path.
- Static/build/smoke coverage exists for caret anchoring, owner-window
  lifecycle, paging keys, and punctuation forwarding.
- Review follow-up hardening removed the old no-anchor top-left fallback and
  made dev REPL pipes unique by default.
- Post-reboot holder-free dev Notepad verification during M05 closeout
  exercised the installed TSF path for input, PageUp/PageDown paging, and
  punctuation behavior.

Old TSF holder dumps and dev REPL outputs are intentionally pruned. Capture
fresh compatibility evidence only when it is the active gate.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-comment-hygiene-contract.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-paging-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-punctuation-commit-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-caret-anchor-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-owner-lifecycle-contract.ps1
```

Broader compatibility proof still requires a holder-free TSF DLL session for
file swaps; tooling must not force-close non-dev desktop applications.
