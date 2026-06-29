# P2-WIN01 Chromium Smoke Plan

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: pending approved live run.

The Chromium smoke uses one Chromium-based text field after the Notepad smoke
has proven install, TSF registration, profile activation, candidate display,
and candidate commit.

Required live evidence:

- `docs\evidence\p2-win01-tsf-smoke\chromium-smoke-result.md`
- `docs\evidence\p2-win01-tsf-smoke\chromium-interactive-status.json`
- `docs\evidence\p2-win01-tsf-smoke\candidate-display-chromium.png`
- `docs\evidence\p2-win01-tsf-smoke\chromium-commit.png`
- `docs\evidence\p2-win01-tsf-smoke\chromium-post-state.json`

The new TSF structural log lines for the smoke include exact
`event=candidate_update` and `event=commit_text` tokens. The result evidence
records `Structural event matcher: exact event tokens`.

The smoke must not log typed content. Diagnostics can record structural event
counts and candidate counts, but not the raw input or committed text.
