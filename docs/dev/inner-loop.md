# Development Inner Loop

P2-WIN03 adds a non-elevated development kit for the Windows product. The one
time install/register setup remains approval-gated; the inner-loop tools below
use scratch builds, exact installed-path swaps, and dev-owned processes only.
They do not perform TSF registration, registry edits, delayed-delete cleanup,
AppVerifier/PageHeap setup, or full live install/uninstall loops.

## Standalone REPL

Use the REPL for engine, candidate, and schema debugging without touching the
installed IME. It builds to a temp directory, prepares scratch Yune product
data, starts a throwaway `YuneWindowsServer.exe` on
`\\.\pipe\yune-windows-ime-dev`, reconnects per request, and stops only that
scratch server on exit.

Run one query non-interactively:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -InputText ngohaig -Once
```

Commit-mode checks the first candidate commit text:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1 -InputText ngohaig -Commit -Once
```

Interactive mode accepts jyutping input, `:commit <input>`, and `:quit`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-repl.ps1
```

The script rebuilds to a temp directory, prepares scratch Yune product data, and
starts only the scratch `YuneWindowsServer.exe` process that it owns. On exit it
stops only that process.

## Server Reload

Use server reload after changing `src\server` or refreshing schema data for the
installed profile. The script rebuilds to scratch, stops only installed
`YuneWindowsServer.exe` processes whose executable path exactly matches
`%LOCALAPPDATA%\Yune\WindowsIme\YuneWindowsServer.exe`, keeps a timestamped
backup, copies in the scratch server with bounded retry for the product-owned
auto-launch race, and restarts through the existing readiness helper. If the
product-owned installed server is already running and passes readiness after the
copy, the script records that as success instead of launching another server.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1
```

Refresh installed schema/user data during the reload:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -RefreshSchema
```

With `-RefreshSchema`, the script also backs up `schema` and `user-data` before
refreshing product data. If copy or readiness validation fails, the script
restores timestamped server/schema/user-data backups and reports the failure.
Successful runs retain the newest three dev backups per backup type by default.

## TSF DLL Reload

Use the disposable test window to keep the TSF DLL lock inside a process the dev
tooling owns:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-test-window.ps1
```

Select Yune Windows in that Notepad window, then reload the installed TSF DLL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-tsf.ps1
```

`dev-test-window.ps1` records the real Notepad process name, executable path,
process start time, launch time, and temp test file. `dev-reload-tsf.ps1`
rebuilds to scratch, verifies that state before treating any process as
dev-owned, enumerates holders of the installed `YuneWindowsTSF.dll`, closes only
the recorded dev-owned test window, waits for the DLL to unlock, keeps a
timestamped backup, overwrites the DLL, validates the hash, rolls back on
failure, and relaunches the disposable Notepad. If another holder remains, it
aborts with the holder list. `-RestartExplorer` is the only opt-in path that may
bounce `explorer`; the script never touches Chrome, Codex, or other user apps.

A full installed TSF DLL file swap requires a holder-free desktop session. In a
normal dogfood session, TSF can be loaded into many already-running GUI apps,
including the editor running this repo. In that state, the correct dev-tool
behavior is a safe abort with the exact holder list, not forced app closure or
delayed-delete scheduling.

## Watch Wrapper

`dev-watch.ps1` routes source changes to the right reload command. It watches
`src\server`, `src\tsf`, `src\candidate_window`, and the Yune schema source.
The default mode is dry-run and only prints the command it would run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-watch.ps1
```

Actual reloads require explicit `-AutoRun`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-watch.ps1 -AutoRun
```

Pass a custom Yune checkout with `-YuneRoot`; dry-run output and `-AutoRun`
routes forward that exact path to server, TSF, and schema reload commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-watch.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

Dry-run route probes are useful for checking automation without stopping
processes or copying files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-watch.ps1 -SimulatePath src\server\yune_windows_server.cpp
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-watch.ps1 -SimulatePath src\tsf\yune_windows_tsf.cpp
```

## Safety

Run the static safety contract after editing dev tooling:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-tooling-safety-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-reload-no-reregister-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-watch-yuneroot-forwarding-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-test-window-state-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-reload-server-safety-contract.ps1
```

The dev loop is non-elevated. It must not install, register, unregister, edit
registry state, schedule delayed deletes, enable verifier tooling, or run the
canonical live IME install/uninstall path. Installed-path reload evidence is
development evidence only; it does not close dogfood readiness. P2-WIN03
runtime evidence is recorded under
`docs/evidence/p2-win03-dev-inner-loop/`.
