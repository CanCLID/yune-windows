# M05 Evidence Summary

M05 adds everyday IME controls without changing the Yune engine ABI:
server-owned state, `op=` IPC verbs, TSF toggle hotkeys, a focus-scoped native
mini language bar, and `YuneWindowsSettings.exe`.

## Final Status

- Status: complete.
- Evidence retained here: compact summary only.
- Raw retained artifacts: none.
- Closeout basis: non-elevated build/contract/scratch-server coverage plus a
  post-reboot holder-free installed-path reload and manual dev Notepad/settings
  verification on 2026-07-01.
- Remaining coverage is follow-up breadth, not an M05 completion blocker:
  Chromium cross-app checks, native Windows input-mode indicator observation,
  and broader dogfood packaging/compatibility evidence.

## Executed Proof

- `tools\test-server-ime-state-protocol-contract.ps1` runs a scratch
  `YuneWindowsServer.exe` and proves `ascii_mode=true non-empty input` returns
  a normal ready response instead of killing the server.
- The same scratch-server test proves `persisted ascii_mode=true restart` does
  not create a crash loop: state is persisted, the server is restarted, and
  `input=nihao` still returns without process exit.
- The same scratch-server test proves `invalid op returns ready:false/error`
  for unknown op names, unknown option names, bad boolean values, bad output
  standards, invalid schema IDs, and version-skewed unknown request fields.
- The same scratch-server test proves `server remains alive after invalid op`
  by sending `op=get-state` after every invalid request.
- The same scratch-server test proves `settings/schema-cycle fallback cannot
  kill server` by surviving invalid schema selection and then continuing
  through valid schema and state mutations.
- The scratch runtime lists `jyut6ping3`, `cangjie5`, and `luna_pinyin`,
  mutates `ascii_mode`, `full_shape`, output standard, and schema, and
  persists those mutations in `state\ime-state.json`.
- `dev-repl.ps1 -Once` exercises normal input plus the `:state` and toggle
  command paths through the same `op=` IPC protocol.
- `build-tsf-shell.ps1` builds `YuneWindowsTSF.dll`,
  `YuneWindowsServer.exe`, `YuneWindowsProfileTool.exe`,
  `YuneWindowsSettings.exe`, and the candidate-window smoke executable.

## Source Contracts

- `tools\test-tsf-ime-state-hotkey-contract.ps1` verifies the TSF source has
  mid-composition toggle commit-or-clear coverage before `ascii_mode`,
  `full_shape`, output-standard, or schema changes.
- The same TSF source contract verifies lone-Shift chord/autorepeat/mouse/focus
  guards, including `Ctrl+Shift+2` and `Ctrl+Shift+3` not also toggling
  `ascii_mode`, stale Shift state clearing on focus loss/deactivation, and
  autorepeat not re-arming the lone-Shift state.
- The same TSF source contract verifies focus refresh existing-server-only
  behavior: `ActivateEx` and `OnSetFocus(TRUE)` use a short bounded query and
  do not launch-and-wait for the shared server.
- `tools\test-language-bar-window-contract.ps1` verifies the native language
  bar is focus-scoped, no-activate, clickable, and wired to server verbs.
- `tools\test-settings-ime-state-contract.ps1` verifies
  `YuneWindowsSettings.exe` uses shared server verbs rather than direct writes
  to `ime-state.json`.
- `tools\test-m05-evidence-summary-contract.ps1` verifies this summary keeps
  executed proof, source contracts, holder-free live proof, follow-up coverage,
  and deferred work separate.

## Holder-free Live Proof

- After reboot on 2026-07-01, `tools\dev\dev-reload-server.ps1 -RefreshSchema`
  rebuilt and hot-swapped the installed `YuneWindowsServer.exe`; readiness
  passed on installed server PID 2548.
- In the same holder-free session,
  `tools\dev\dev-reload-tsf.ps1 -RestartExplorer` rebuilt and swapped the
  installed `YuneWindowsTSF.dll`; the script validated the DLL swap and opened
  a dev-owned Notepad window.
- `YuneWindowsProfileTool.exe --activate` followed by `--state` reported the
  Yune Windows profile as registered and active.
- The freshly built `YuneWindowsSettings.exe` was copied into the install root
  so the installed settings entrypoint matched the M05 build.
- Manual operator verification in the dev-owned Notepad window confirmed the
  live installed IME path worked after the swap: `ngohaig` input, Shift
  Chinese/English toggle, English pass-through, toggling back to Cantonese,
  PageUp/PageDown candidate paging, punctuation behavior, and the settings
  entrypoint all worked.

## Follow-up Coverage

- Chromium cross-app state reconciliation should be rechecked during the next
  compatibility or dogfood package pass.
- Native Windows input-mode indicator behavior should be observed explicitly in
  a focused compatibility pass.
- Broader language-bar click and settings-to-typing coverage across multiple
  desktop hosts should be captured when compatibility breadth is the active
  gate.

## Deferred

- `WH_KEYBOARD_LL` fallback for lone-Shift delivery is not implemented in M05.
  Current code uses TSF key-sink delivery with non-elevated source contracts and
  holder-free Notepad proof; if future compatibility evidence shows Shift
  key-up is unreliable in specific hosts, the fallback must be scoped as a
  follow-up.
- Non-blocking first cold keystroke remains a separate product-owned server
  lifecycle follow-up. M05 bounds activation/focus refresh to an
  existing-server-only query, but the first key path can still launch the
  shared server synchronously.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-ime-state-protocol-contract.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -Once -InputText 'ngohaig'
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -Once -InputText ':state'
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -Once -InputText ':ascii 1'
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-repl-ime-state-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-window-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-ime-state-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-up-pass-through-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m05-evidence-summary-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -RefreshSchema
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -RestartExplorer
```

Installed-path reloads require a holder-free TSF DLL session. Tooling must not
force-close non-dev applications or mutate live IME machine state without
explicit current-session approval.
