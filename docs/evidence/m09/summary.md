# M09 Settings Panel + Skin Picker Evidence

Status: non-elevated implementation complete and verified with build, contract,
toolbar smoke, and settings-window self-test evidence. live-machine steps were not run
because elevated registration, registry mutation, and full TSF host loops require
explicit current-session approval.

What landed:

- Added a persistent settings segment to the Direct2D language bar and routed it
  to `YuneWindowsSettings.exe`, focusing an existing settings window when present.
- Kept the toolbar native, layered, and no-activate; the settings segment follows
  the M08 click-vs-drag threshold so a drag from that area moves the toolbar
  instead of opening settings.
- Scoped candidate-window and language-bar window class registration to the
  current module so temp-build smokes and dev swaps do not dispatch into an
  already installed TSF DLL in the same process.
- Extended the native Win32 settings panel with `Input / session`, `Appearance`,
  `Engine`, `Dictionary`, and `Schemas` sections.
- Wired supported session toggles, schema selection, and skin selection through
  server `op=` requests. The settings executable does not read or write
  `state\ime-state.json` directly.
- Reused `D2DSurface` for an in-window toolbar preview and enumerated installed
  skins from deployed `skins/<name>/theme.json` manifests with the compiled-in
  default fallback preserved.
- Added present-but-disabled controls for deploy-time engine preferences,
  candidate display preferences, dictionary import/export, and schema import so
  future milestones can fill in behavior without redesigning the panel.
- Kept the candidate window visually unchanged; M10 owns candidate-window
  skinning and skin breadth.

Verification run:

- `git diff --check`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m08-modern-toolbar-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-window-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-language-bar-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-ime-state-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-m09-settings-panel-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-settings-window-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-server-ime-state-protocol-contract.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-ime-state-hotkey-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-response-validation-contract.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-repl-ime-state-contract.ps1`

Live-machine boundary:

- Elevated install/register/unregister/cleanup, registry mutation,
  AppVerifier/PageHeap, and full Notepad/Chromium live IME loops were not run.
- Live TSF-host visual confirmation of the single toolbar, drag persistence,
  and no-focus-steal behavior remains approval-gated and separate from this
  non-elevated M09 implementation proof.
