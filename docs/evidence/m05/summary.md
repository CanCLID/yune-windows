# M05 Evidence Summary

M05 adds everyday IME controls without changing the Yune engine ABI: server-owned
state, `op=` IPC verbs, TSF toggle hotkeys, a focus-scoped native mini language
bar, and `YuneWindowsSettings.exe`.

## Final Status

- Status: implementation complete for non-elevated build, contract, and scratch
  server/dev-loop coverage.
- Evidence retained here: compact summary only.
- Raw retained artifacts: none.
- Remaining gate: holder-free live app proof for DLL-side hotkeys, language-bar
  clicks, settings-driven reconciliation, and native Windows input-mode
  indicator behavior.

## Proven Behaviors

- The shared server owns persistent IME state in `state\ime-state.json` and is
  the only writer.
- `op=get-state`, `op=list-schemas`, `op=set-option`, and `op=select-schema`
  work through the named-pipe protocol.
- Every normal `input=` response includes the current state block.
- The scratch runtime can list `jyut6ping3`, `cangjie5`, and `luna_pinyin`,
  mutate `ascii_mode`, `full_shape`, output standard, and schema, and persist
  those mutations.
- `dev-repl.ps1 -Once -InputText ':state'` exercises the same `op=` path.
- The TSF DLL has contract/build coverage for activation/focus state refresh,
  lone-Shift `ascii_mode` toggle, `Ctrl+Shift+2` schema cycle,
  `Ctrl+Shift+3` full/half toggle, ASCII pass-through in English mode, and
  input-mode compartment updates.
- The native language bar is a focus-scoped, no-activate, clickable popup wired
  to server verbs.
- `YuneWindowsSettings.exe` builds as a native settings entrypoint and uses only
  server verbs, not the private state file.
- The full `tools\test-*.ps1` non-elevated sweep was run after implementation;
  the only failures were the four pre-existing caveat tests named in the goal
  objective.

## Regeneration Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-ime-state-protocol-contract.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -Once -InputText ':state'
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-repl-ime-state-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-window-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-ime-state-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-key-up-pass-through-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

Holder-free live proof requires a TSF DLL session without non-dev desktop
holders. Tooling must not force-close non-dev applications or mutate live IME
machine state without explicit current-session approval.
