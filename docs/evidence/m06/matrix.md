# M06 Host Compatibility Matrix

Status: live attempt failed outside Notepad; raw-fallback fix pending
holder-free installed TSF reload.

This matrix is the operator-facing checklist for M06. Fill each cell with
`Pass`, `Fail`, `N-A`, or `Pending`, followed by a short note and any linked
log/screenshot evidence. Tier 1 must be complete before M06 is marked complete.

## Checklist

1. Composition and caret anchoring.
2. No orphan or stale candidate/language windows.
3. Paging with PageUp/PageDown and unshifted `-`/`=`.
4. Punctuation and full-width shifted punctuation.
5. Commit order.
6. Lone-Shift Chinese/English toggle; Shift+letter passes through.
7. Preserved-key toggles: `Ctrl+Shift+2`, `Ctrl+Shift+3`.
8. English pass-through in ascii mode.
9. Focus-scoped language bar.
10. Settings live-apply.
11. Cross-app reconciliation.
12. Native Windows input-mode indicator observation.

## Tier 1

| Host | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Notepad | Pass user smoke | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | Pending detailed | User reported Notepad worked and normal typing succeeded after approved TSF reload; detailed 12-item checklist still pending |
| Chromium browser | Fail no output | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | Pending retest | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | User reported Chrome produced no output; see `logs/m06-m07-user-host-failures-tsf-events.md` and `logs/2026-07-02-user-host-results.md` |
| VS Code or daily editor | Fail no output | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | Pending retest | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | Zed produced no output; VS Code not installed; see `logs/m06-m07-user-host-failures-tsf-events.md` |
| Telegram Desktop | Fail no output | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | Pending retest | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | User reported Telegram produced no output; see `logs/m06-m07-user-host-failures-tsf-events.md`; lone-Shift cannot be closed until typing output works |

## Tier 2

| Host | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Rich edit host | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | WordPad or Word if available |
| Windows Terminal or console | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Reduced fidelity expected |
| File Explorer rename/search | Fail no output | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | Pending retest | Pending retest | Pending retest | Pending retest | Fail no output | Pending retest | User reported Windows File Explorer produced no output |
| WeChat | N-A | N-A | N-A | N-A | N-A | N-A | N-A | N-A | N-A | N-A | N-A | N-A | Not installed or not tested |

## Tier 3

| Host | Result | Evidence |
| --- | --- | --- |
| UWP/AppContainer or sandboxed host | Pending expected-limitation classification | Broker/autostart milestone owns full support |

## Operator Script

For each host:

1. Start from a holder-free installed TSF DLL session with the M06 build loaded.
2. Run `tools\collect-m06-compatibility-environment.ps1`.
3. Focus the host input field.
4. Type `ngohaig`, page candidates, commit one candidate, then clear the field.
5. Verify shifted punctuation in Chinese mode: `Shift+/`, `Shift+1`,
   `Shift+;`, `Shift+'`, `Shift+=`, and `Shift+-`.
6. Verify unshifted `-` and `=` still page while composing.
7. Press Enter during composition and confirm the raw typed letters commit.
8. Press lone Shift to toggle Chinese/English; verify Shift+letter does not
   toggle and passes through as a capital.
9. Toggle `Ctrl+Shift+2` and `Ctrl+Shift+3`.
10. Switch to another host and confirm state/language-bar reconciliation.
11. Capture a structural log window with
    `tools\capture-m06-tsf-events-window.ps1 -Label <host-label>`.
