# M06 Host Compatibility Matrix

Status: passed. After the reboot-free pipe-security fix + the toggle fixes, the
user confirmed the core typing behaviors work across the Tier-1 hosts on
2026-07-02 (the earlier no-output failure is resolved). This is a behavior-level
confirmation of the folded-in fixes and typing controls; items 9-12 are
implemented and contract-covered and were spot-checked, not exhaustively audited
per host.

This matrix is the operator-facing checklist for M06. Cells record `Pass`,
`Fail`, `N-A`, or `Pending` with a short note.

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

Legend: `Pass` = user-confirmed live on 2026-07-02; `Impl` = implemented and
contract-covered, spot-checked but not exhaustively host-audited this pass.

## Tier 1

| Host | Composition/caret (1), paging (3), punctuation (4/F1), commit (5), lone-Shift (6/F5), pass-through (8) | Preserved-key (7), language bar (9), settings (10), reconcile (11), indicator (12) | Evidence |
| --- | --- | --- | --- |
| Notepad | Pass | Impl (spot-checked) | Baseline; typing, F1 punctuation, F6 raw Enter, F3/F4 compose, lone-Shift all confirmed |
| Chromium browser | Pass | Impl (spot-checked) | Was no-output pre-fix; after pipe-security fix the user confirmed typing, F1, F6, F3/F4, and the lone-Shift toggle |
| Telegram Desktop | Pass | Impl (spot-checked) | Was no-output pre-fix; lone-Shift now toggles first-press after the warm-up + single-entry guard fixes |
| Zed | Pass | Impl (spot-checked) | Was no-output pre-fix; confirmed after fix. VS Code not installed |

## Tier 2

| Host | Result | Evidence |
| --- | --- | --- |
| File Explorer search | Pass | Was no-output pre-fix; types Chinese after the pipe-security fix |
| Rich edit host (WordPad/Word) | Pending | Opportunistic breadth |
| Windows Terminal / console | Pending | Reduced fidelity expected |
| WeChat | N-A | Not installed |

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
