# Development Inner Loop

P2-WIN03 starts with a no-install engine REPL for candidate and schema debugging.
It uses a scratch build, a scratch schema/user-data tree, and the dev pipe
`\\.\pipe\yune-windows-ime-dev`; it does not touch TSF registration, the installed
IME, or machine state.

## Standalone REPL

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

## Safety

Run the static safety contract after editing dev tooling:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-dev-tooling-safety-contract.ps1
```

The Task 1 dev loop is non-elevated. It must not install, register, unregister,
edit registry state, schedule delayed deletes, enable verifier tooling, or run
the installed IME live path.
