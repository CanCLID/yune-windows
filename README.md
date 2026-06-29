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

Current development dogfood works after install, registration, profile
activation, and an explicit start of the shared server. The installer does not
yet own the server lifecycle, so manual dogfood must start
`YuneWindowsServer.exe` before typing.

Before dogfood or production installer work, regenerate live evidence under the
Yune Windows names:

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
5. [docs/plans/active/p2-win01-plan-windows-product.md](./docs/plans/active/p2-win01-plan-windows-product.md)

## Build

From the Yune repo, first create the Windows engine package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-yune-windows.ps1
```

Then build the Windows IME shell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

## Manual Dogfood

After packaging Yune and installing Yune Windows with explicit approval, start
the shared server before opening the text field you want to test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\start-yune-windows-server.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune -InstallDir "$env:LOCALAPPDATA\Yune\WindowsIme" -WaitForReady
```

Then activate the profile:

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
