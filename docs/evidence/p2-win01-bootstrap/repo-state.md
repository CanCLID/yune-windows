# P2-WIN01 Repo State

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: public post-rename bootstrap evidence prepared from the clean
`CanCLID/yune-windows` baseline.

## Git State

- Yune Windows repo: `C:\Users\laubonghaudoi\Documents\GitHub\yune-windows`
- Yune Windows `HEAD`: `77f0126ad3c6cddab4a24c6eae4d853a0ef34ffb`
- Yune Windows upstream: `origin/main`
- Yune Windows upstream commit: `77f0126ad3c6cddab4a24c6eae4d853a0ef34ffb`
- Yune engine repo: `C:\Users\laubonghaudoi\Documents\GitHub\yune`
- Yune engine `HEAD`: `0dd7202c031ce330e5d04b4816c541d27d6cfcf5`
- Yune engine upstream commit: `0dd7202c031ce330e5d04b4816c541d27d6cfcf5`

The Yune engine checkout had unrelated local report changes at verification
time. They were preserved and were not adopted into this product evidence.

## Non-Elevated Gates

- Yune package command passed and produced the packaged Windows ABI artifacts
  under `target\yune-windows-native\x86_64-pc-windows-msvc\dist`.
- Old product-name gate passed for old product identity terms.
- TSF shell build passed and produced `YuneWindowsTSF.dll`,
  `YuneWindowsServer.exe`, `YuneWindowsProfileTool.exe`, and
  `YuneWindowsCandidateWindowSmoke.exe`.
- Host smoke, shared-server IPC smoke, native candidate-window smoke, install
  directory safety, and machine-state approval gates passed without elevated
  machine changes.

## Live Evidence Status

Fresh install, TSF registration, profile activation, Notepad, Chromium,
diagnostics export, uninstall, and cleanup evidence still require explicit
current-session approval before machine-state work.
