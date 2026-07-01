# Requirements

## Yune Windows Product Requirements

**Status:** public rename baseline plus P2-WIN02 product-owned server lifecycle
and structured cleanup hardening are complete. Fresh post-rename live evidence
proves install/register, product-owned Notepad and Chromium typing,
diagnostics, uninstall, and post-reboot no-residue cleanup on the installed
IME.

- [x] **WIN-01 - Product identity:** Product name, repo slug, install root,
  TSF DLL, server, profile tool, candidate smoke, named pipe, and TSF
  description use Yune Windows names.
- [x] **WIN-02 - Fresh TSF identity:** The text service CLSID is
  `{1788DBA7-CC9A-49E2-9C4C-E9DBF0BE2567}` and the profile GUID is
  `{3AE69B8D-19B4-4267-8F21-E239666D6632}`.
- [x] **WIN-03 - Yune-only runtime:** The product loads packaged Yune and does
  not add a librime runtime fallback.
- [x] **WIN-04 - Opt-in profile ABI:** Windows profile behavior is consumed
  through `rime_yune_windows_profile_api.h`,
  `RimeYuneWindowsProfileApi`, and
  `rime_get_yune_windows_profile_api()`.
- [x] **WIN-05 - Default ABI boundary:** The product does not require new
  fields in Yune's default `rime_get_api()` ABI.
- [x] **WIN-06 - Shared server IPC:** The default process model is a shared
  server over `\\.\pipe\yune-windows-ime`.
- [x] **WIN-07 - Native candidate window:** The first inline candidate window
  is native, not WebView2.
- [x] **WIN-08 - Installer safety:** Install, unregister, registry, cleanup,
  AppVerifier, PageHeap, and live TSF registration operations require explicit
  current-session approval before machine-state changes.
- [x] **WIN-09 - Diagnostics privacy:** Diagnostics export must stay
  structural and avoid typed-content logs.
- [x] **WIN-10 - Post-rename live evidence:** Fresh evidence must prove clean
  install target, TSF registration, profile activation, Notepad input,
  candidate display, candidate commit, Chromium text-field input, diagnostics
  export, uninstall, and cleanup under the Yune Windows names. Current evidence
  covers the full path, and P2-WIN02 adds product-owned startup and structured
  cleanup result support. The latest approved P2-WIN02 live attempt reached
  install/register, profile activation, Notepad, Chromium, diagnostics export,
  and structured uninstall. The installed Notepad and Chromium smokes both
  passed, committed `我係個`, and recorded product-owned server start/readiness
  plus profile-active-before-typing evidence. Cleanup initially recorded
  `requires_reboot=true` with delayed-delete paths under the install root
  because GUI processes kept `YuneWindowsTSF.dll` loaded; post-reboot
  validation then passed with no install directory, TSF DLL, server process,
  TSF profile, or machine residue. The closeout audit is complete.
- [ ] **WIN-11 - Dogfood package:** Dogfood installer/package work is the next
  open product gate now that WIN-10 has passed. It must decide and verify the
  uninstall/reinstall user-data policy because the current uninstaller removes
  the install tree, including `user-data`, unless `-KeepFiles` is used.
- [x] **WIN-12 - Product-owned server lifecycle:** The installed IME must start
  or connect to `YuneWindowsServer.exe` without requiring the operator to run
  `tools\start-yune-windows-server.ps1` before typing. Failures must remain
  bounded and structurally logged. Implementation contracts are green, and
  approved live Notepad and Chromium evidence proves product-owned startup on
  the installed path. Post-reboot cleanup validation proves the scheduled
  install-root delayed deletes are gone. Known limitation: cold start currently
  uses a bounded synchronous TSF key-path wait
  (`kServerLaunchReadyWaitMs = 15000`), so the first cold keystroke can block
  the foreground app while the server starts. Non-blocking/asynchronous
  cold-start or broker launch remains a dogfood fast-follow, not a solved gate.

## Non-Elevated Verification Gates

- Naming gate: scan the tree, excluding `.git`, for old product-name strings.
  Expected: no matches.

- Build gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

- Smoke and contract gates:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-host-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-ipc-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-install-dir-safety-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-machine-state-approval-gates.ps1
```

Add broader non-elevated contract tests as needed for touched behavior.
