# Yune Windows

Yune Windows is the Windows IME product for the Yune engine.

This repo owns the Windows product surface:

- TSF text service registration and input delivery
- shared Windows server and IPC lifecycle
- packaged Yune loading
- native candidate window behavior
- diagnostics export
- installer, uninstall, and cleanup scripts
- dogfood and release evidence

Yune owns the engine. Yune Windows consumes Yune through the Windows package
and ABI surfaces documented in
[docs/reference/yune-engine-contract.md](./docs/reference/yune-engine-contract.md).

## Current Checkpoint

This public baseline is the renamed Yune Windows product tree. It keeps the
usable TSF shell, shared server, native candidate window, installer scripts,
diagnostics export, and non-elevated contract tests, but omits old private
evidence captured before the rename.

Current development dogfood has product-owned shared-server startup in the TSF
DLL and structured cleanup result support in the uninstaller. The approved live
install/register/type/diagnostics/uninstall/cleanup closeout passed after
post-reboot delayed-delete validation. M03 added a non-elevated development
inner loop for candidate debugging, installed-server reload, TSF DLL reload, and
watch-mode routing. M04 implemented server-side candidate comment hygiene,
larger candidate supply for client-side paging, read-session caret anchoring,
owner-window/no-orphan lifecycle hardening, PageUp/PageDown paging, and
punctuation/full-width forwarding through the existing Rime `get_commit` path.
M05 adds server-owned persistent IME state, `op=` IPC verbs, toggle hotkeys,
a focus-scoped native mini language bar, and `YuneWindowsSettings.exe`.
M06 implementation relief is now landed for the known compatibility blockers:
server request failures no longer kill the shared server, TSF activation/focus
warms the server asynchronously, foreground key-path queries are capped, shifted
punctuation and number-row symbols are forwarded to Rime, Enter commits the raw
typed buffer, and a focus-gated low-level Shift hook covers hosts that do not
deliver lone-Shift key-up through the TSF sink.

After a post-reboot holder-free reload, the installed server, TSF DLL, active
profile, and settings executable were refreshed from the M05 build. Manual dev
Notepad verification confirmed `ngohaig` input, Shift Chinese/English toggle,
English pass-through, toggling back to Cantonese, PageUp/PageDown paging,
punctuation behavior, and the settings entrypoint. The M06 non-elevated proof
and operator scripts live under `docs/evidence/m06/`; the next M06 gate is a
holder-free installed TSF DLL host matrix for Notepad, Chromium, a daily editor,
and Telegram. Do not mark M06 complete from local contracts alone.

For dogfood package or production installer work, refresh live evidence under
the Yune Windows names whenever package inputs or installer behavior change:

1. Build against the current packaged Yune Windows engine.
2. Register the text service only after explicit approval.
3. Prove `ngohaig` can type through Yune into Notepad.
4. Prove candidate display, candidate commit, diagnostics export, Chromium
   text-field input, uninstall, and cleanup.
5. Record fresh post-rename evidence before larger release work.

## Reference Material

The legacy Weasel-derived implementation remains reference material for TSF,
server/IPC, installer registration, smoke harnesses, and candidate-window
positioning. Do not treat old Weasel UI architecture or librime fallback
assumptions as product requirements.

## Start Here

Read these in order:

1. [docs/roadmap.md](./docs/roadmap.md)
2. [docs/requirements.md](./docs/requirements.md)
3. [docs/decisions.md](./docs/decisions.md)
4. [docs/reference/yune-engine-contract.md](./docs/reference/yune-engine-contract.md)
5. [docs/plans/active/README.md](./docs/plans/active/README.md)

## Build

From the Yune repo, first create the Windows engine package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-yune-windows.ps1
```

Then build the Windows IME shell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

## Development Inner Loop

M03 tooling keeps ordinary iteration non-elevated:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -InputText ngohaig -Once
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -InputText ':state' -Once
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-test-window.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-watch.ps1
```

See [docs/dev/inner-loop.md](./docs/dev/inner-loop.md). The install/register
setup remains approval-gated; the dev tools do not perform registration,
registry edits, delayed-delete cleanup, verifier setup, or canonical live
install/uninstall loops.

## Manual Dogfood

The installed TSF DLL starts the per-user `YuneWindowsServer.exe` on demand
when the Yune Windows profile receives composition input. Manual
`tools\start-yune-windows-server.ps1` remains a diagnostic helper, not a
dogfood prerequisite.

After packaging Yune and installing Yune Windows with explicit approval,
activate the profile:

```powershell
$tool = "$env:LOCALAPPDATA\Yune\WindowsIme\YuneWindowsProfileTool.exe"
& $tool --activate
& $tool --state
```

Open a fresh normal Notepad or Chromium text field, select **Yune Windows** if
Windows has not already switched to it, type `ngohaig`, and press `Space` to
commit the first candidate.

Development cleanup remains approval-gated. Close apps that loaded
`YuneWindowsTSF.dll`, then use the uninstall/cleanup scripts with explicit
approval and verify no install directory, TSF DLL, server process, TSF profile,
or machine residue remains.

## Safety Rule

Do not run elevated registration, installer, AppVerifier, PageHeap, registry
cleanup, unregister, or machine cleanup commands without explicit user approval
in the current session.
