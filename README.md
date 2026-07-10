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
M07 persistent composition is also implemented in the non-elevated path: the
server owns per-client Rime sessions, the TSF DLL renders Rime preedit through
inline `ITfComposition`, number-key selection routes to Rime, Enter uses raw
commit, and Space uses candidate commit.

M06 and M07 are complete (2026-07-02). The no-output failure in sandboxed hosts
(Chrome/Zed/Telegram/Explorer) was root-caused to the shared server creating its
named pipe with the default security descriptor, which denied
sandboxed/lower-integrity host tokens; it was fixed reboot-free by scoping the
pipe to the current user's SID plus all application packages (AppContainer). F1
(shifted full-width punctuation), F2/F5 (the 中/英 Shift toggle: server request
resilience, async warm-up, a startup dictionary warm-up for first-keystroke
latency, and a single-entry lone-Shift guard), F6 (Enter commits the raw letters),
and the M07 inline composition (F3/F4: typing `dungdatkyut` and picking characters
composes 東突厥, with the romanization shown inline at the caret) were confirmed
live across the Tier-1 hosts. Evidence: `docs/evidence/m06/` and
`docs/evidence/m07/`.

The active native-shell work is rebaselined in dependency order. M10 owns the
implemented Cantonese UI, singular clone-free toolbar presentation, and
settings-window usability closeout. M11 owns the implemented activation,
lone-Shift state, and deterministic toolbar-visibility reliability closeout.
M10 may take the next approval-gated hash-pinned presentation deployment;
M11 may reuse the exact candidate after its remaining direct-TSF preflight, or
must rerun affected M10 regressions if its product inputs change. They receive
separate verdicts, and both remain prerequisites for M12. M12 then adds the
strict manifest-only skin platform, and M13 applies it to the native candidate
presentation. See
`docs/reference/m10-m13-rebaseline.md`.

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
