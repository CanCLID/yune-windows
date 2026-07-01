# P2-WIN04 TSF DLL Reload Blocker

Checked at: 2026-07-01T09:24:47.8623833-07:00

The installed TSF DLL was not reloaded because non-dev processes were holding:

- `chrome` PID 10756
- `claude` PID 17600
- `Codex` PID 15980
- `explorer` PID 3796
- `GitHubDesktop` PID 24444
- `NVIDIA Overlay` PID 15068
- `Telegram` PID 23516

Per the P2-WIN04 goal safety boundary, these apps were not closed or restarted.
DLL-side Slice B/C/D behavior is therefore covered by static contracts, build
verification, candidate-window smoke coverage, and dev REPL server-side evidence
only. Live caret-position, no-orphan, paging, and TSF punctuation verification
requires a holder-free desktop session.
