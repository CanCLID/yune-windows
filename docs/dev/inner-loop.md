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
auto-launch race, and restarts through the existing readiness helper.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1
```

Refresh installed schema/user data during the reload:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\dev-reload-server.ps1 -RefreshSchema
```

If copy or readiness validation fails, the script restores the timestamped
backup and reports the failure.

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

`dev-reload-tsf.ps1` rebuilds to scratch, enumerates holders of the installed
`YuneWindowsTSF.dll`, closes only the recorded dev-owned test window, waits for
the DLL to unlock, keeps a timestamped backup, overwrites the DLL, validates the
hash, rolls back on failure, and relaunches the disposable Notepad. If another
holder remains, it aborts with the holder list. `-RestartExplorer` is the only
opt-in path that may bounce `explorer`; the script never touches Chrome or other
user apps.

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
```

The dev loop is non-elevated. It must not install, register, unregister, edit
registry state, schedule delayed deletes, enable verifier tooling, or run the
canonical live IME install/uninstall path. Installed-path reload evidence is
development evidence only; it does not close dogfood readiness.
