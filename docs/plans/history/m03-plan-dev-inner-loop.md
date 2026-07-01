# M03 Development Inner Loop (Dev Kit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** give the maintainer a fast `type -> find bug -> fix -> takes effect`
inner loop for the Windows product, with no reboot and no re-registration in the
loop. Replace the slow `rebuild -> reboot -> retry` cycle that came from running
the production cleanup ceremony during development.

**Architecture:** the system already splits into two components with very
different reload costs. `YuneWindowsServer.exe` (plus the Yune engine and schema)
is a separate background process that can be killed and restarted freely; the TSF
DLL reconnects on the next keystroke. `YuneWindowsTSF.dll` is loaded in-process in
**every** host app that receives TSF input, so replacing it requires all current
holders to release it. The dev discipline is to keep the Yune profile active only
in a disposable test app, so the sole holder is a process the tooling can close;
then the swap is reboot-free and needs no re-registration (the install path is
fixed; only the file bytes change). If an un-closeable app (explorer, chrome, or
the agent's own process) has grabbed the DLL, the swap aborts cleanly with holder
guidance rather than forcing a reboot. This plan adds dev-only tooling that
exploits that split; it does not change product behavior.

**Tech Stack:** PowerShell dev tooling on top of the existing
`tools\build-tsf-shell.ps1`, `tools\start-yune-windows-server.ps1`,
`tools\prepare-yune-product-data.ps1`, and the shared server's named-pipe line
protocol. No new C++.

---

## Current Facts

- The server accepts `--rime-dll --shared-dir --user-dir --pipe` and a `--once`
  flag, and speaks a line protocol over the pipe: request `input=<jyutping>\n`
  `commit=0|1\n.\n`, response JSON `{ready, schema_id, candidate_count,`
  `commit_text, candidates:[{text,comment}]}`.
- The server single-instance mutex is **pipe-scoped**
  (`ServerInstanceMutexName(args.pipe_name)`), so a dev server on a non-canonical
  pipe (e.g. `\\.\pipe\yune-windows-ime-dev`) coexists with a real installed
  server on `\\.\pipe\yune-windows-ime` without conflict.
- `tools\build-tsf-shell.ps1 -OutputDir <dir> -YuneRoot <root>` builds all four
  binaries (`YuneWindowsTSF.dll`, `YuneWindowsServer.exe`,
  `YuneWindowsProfileTool.exe`, `YuneWindowsCandidateWindowSmoke.exe`). A C++
  shell rebuild is seconds; a Yune engine (`rime.dll`) rebuild is a Rust build in
  the Yune repo and is out of scope here (engine work lives in Yune per D-06).
- `tools\build-tsf-shell.ps1` throws `missing packaged Yune headers` if the Yune
  Windows package is absent, so any dev script that builds must first preflight
  that the package (headers + `rime.dll`) exists.
- `tools\start-yune-windows-server.ps1` throws `missing installed shared server`
  when `<InstallDir>\YuneWindowsServer.exe` is absent, so it cannot start a
  scratch/no-install dev server as-is; `dev-repl` needs its own scratch-start
  helper (in `tools\dev\dev-support.ps1`).
- The installed layout is `%LOCALAPPDATA%\Yune\WindowsIme` with the three exes,
  `rime.dll`, `schema\`, and `user-data\` flattened into the root; the TSF DLL,
  the server, and `rime.dll` all sit next to each other.
- The server does **not** hold `YuneWindowsTSF.dll` (it loads `rime.dll`, not the
  TSF DLL). Only host apps that receive TSF input hold the TSF DLL.
- DLL-holder enumeration currently exists **only** inside
  `tools\uninstall-yune-windows-ime.ps1` (`Get-YuneWindowsProcessesUsingModule`,
  a machine-mutating script). Dev tooling must **not** dot-source the uninstaller;
  it needs its own read-only holder helper in `tools\dev\dev-support.ps1`.
- The product-owned TSF path auto-launches the server from the install dir on a
  missing pipe (M02), so a stopped dev server is re-launched on the next
  keystroke from whatever `YuneWindowsServer.exe` currently sits in the install
  dir.
- The one-time install/register (`tools\install-yune-windows-ime.ps1`) is
  elevated and approval-gated. Overwriting files under `%LOCALAPPDATA%` and
  restarting a user process are **not** elevated and **not** approval-gated.

## Non-Goals

- Do not create a second install/registration path. The one-time setup reuses the
  existing approval-gated `tools\install-yune-windows-ime.ps1`.
- Do not weaken or bypass any existing machine-state approval gate. The dev inner
  loop must stay user-level: no `regsvr32`, no registry writes, no unregister, no
  `MoveFileEx` delayed delete, no AppVerifier/PageHeap.
- Do not auto-kill arbitrary user apps. The dev DLL swap may close only the
  disposable dev test app; any other holder (explorer, chrome) is reported with
  guidance, and `explorer` is only restarted on an explicit opt-in switch.
- Do not change product code (`src\**`) or product behavior in this milestone.
- Do not add release/dogfood packaging (that is the separate WIN-11 candidate).

## File Map

- Create `tools\dev\dev-support.ps1`
  - Shared read-only dev helpers: DLL-holder enumeration (reimplemented, not
    dot-sourced from the uninstaller), a scratch-server start on the dev pipe, and
    a packaged-Yune preflight.
- Create `tools\dev\dev-repl.ps1`
  - Standalone engine/candidate REPL over a dev pipe; no install, no TSF.
- Create `tools\dev\dev-reload-server.ps1`
  - Rebuild + hot-restart the installed server; fast loop for engine/candidate/
    schema behavior.
- Create `tools\dev\dev-reload-tsf.ps1`
  - Rebuild + in-place swap the installed TSF DLL by releasing the disposable
    test app; no reboot, no re-registration.
- Create `tools\dev\dev-test-window.ps1`
  - Launch a disposable text target (default: a fresh Notepad the script owns)
    to confine the DLL lock to a closeable process.
- Create `tools\dev\dev-watch.ps1`
  - File watcher that routes changes to the correct reload script.
- Create `tools\test-dev-tooling-safety-contract.ps1`
  - Static contract: every `tools\dev\*.ps1` script and any dot-sourced dev
    helper perform no elevated/registry/unregister/delayed-delete operations
    and never mutate machine registration.
- Create `tools\test-dev-reload-no-reregister-contract.ps1`
  - Static contract: `dev-reload-tsf.ps1` overwrites the DLL but never calls
    `regsvr32` or re-registers.
- Create `docs\dev\inner-loop.md`
  - Maintainer guide: one-time approved setup, then the free inner loop.

## Design Details

### Two loops, one boundary

- **Fast loop (server / engine-config / schema):** `dev-reload-server.ps1` and
  `dev-repl.ps1`. Rebuild the server, stop the running server by install-path
  match (as the smokes do), keep a timestamped backup of the installed
  `YuneWindowsServer.exe`, copy the new server into the install dir, restart it
  with `-WaitForReady`, and restore the backup if readiness fails. The TSF path
  then uses the new server on the next keystroke. Seconds; no app restart; no
  reboot.
- **DLL loop (TSF / candidate window):** `dev-reload-tsf.ps1`. Rebuild the DLL to
  a scratch dir, enumerate holders, close the disposable dev test app, keep a
  timestamped backup of the installed `YuneWindowsTSF.dll`, overwrite the DLL,
  validate the swap, restore the backup if validation fails, and relaunch the
  test app. Seconds; no reboot; no re-registration.

### Preflight and scratch start

- Every dev script that builds first preflights the packaged Yune Windows engine
  (`rime_yune_windows_profile_api.h` + `rime.dll`) and stops with a message
  pointing at `scripts\package-yune-windows.ps1` in the Yune repo if it is
  missing (`build-tsf-shell.ps1` throws on missing headers).
- `dev-repl.ps1` uses a scratch-start helper in `dev-support.ps1` that
  `Start-Process`es the freshly built scratch `YuneWindowsServer.exe` on
  `\\.\pipe\yune-windows-ime-dev`; it does **not** call the install-oriented
  `start-yune-windows-server.ps1`, which throws on a missing installed server.

### Dev isolation vs. real install

- `dev-repl.ps1` runs a **throwaway** server on `\\.\pipe\yune-windows-ime-dev`
  with a scratch `-shared-dir`/`-user-dir` under the scratch/temp tree. It never
  needs the install dir or registration, so it is the fastest and safest loop for
  "these candidates are wrong/missing/ordered badly" bugs.
- `dev-reload-server.ps1` / `dev-reload-tsf.ps1` operate on the **real** install
  dir and canonical pipe, because they exist to iterate the actually-registered
  IME the maintainer types into.

### Holder handling for the DLL swap

- Use the **read-only holder helper in `dev-support.ps1`** (reimplemented; never
  dot-source the machine-mutating uninstaller) before overwrite. If holders are
  only the dev test app (and processes the script itself launched), close them and
  wait for exit. If any other holder remains (explorer, chrome, the agent's own
  process), print the holder summary and **abort cleanly with guidance** rather
  than forcing a reboot; only restart `explorer` when `-RestartExplorer` is
  explicitly passed. Never touch chrome/other user apps, and never reboot.
- After overwrite, relaunch the disposable test app so typing resumes on the new
  DLL.
- Installed binary swaps are transactional at the script level: keep timestamped
  backups beside the installed binary, validate readiness/swap success before
  declaring the reload usable, and roll back to the backup if validation fails.

### One-time setup vs. free inner loop

- One-time (approval-gated, elevated, existing installer): install + register.
- Everything after is user-level: file overwrites under `%LOCALAPPDATA%` and
  user-process restarts. The dev scripts must contain no elevation, no
  `regsvr32`, and no registration so the safety contracts pass.

## Task 1: Standalone engine REPL (`dev-repl.ps1`)

**Files:**
- Create: `tools\dev\dev-support.ps1`
- Create: `tools\dev\dev-repl.ps1`
- Create: `tools\test-dev-tooling-safety-contract.ps1`

- [x] **Step 0: dev-support helpers + preflight**
  Create `dev-support.ps1` with a read-only DLL-holder helper (reimplemented, not
  dot-sourced from the uninstaller), a packaged-Yune preflight, and a
  scratch-server start helper. `dev-repl` calls the preflight and scratch-start.

- [x] **Step 1: Build/start a throwaway server**
  After the package preflight, build the server to a scratch dir, prepare scratch
  schema/user data via `prepare-yune-product-data.ps1`, and start it on
  `\\.\pipe\yune-windows-ime-dev` via the `dev-support.ps1` scratch-start helper
  (not `start-yune-windows-server.ps1`, which requires an installed server).

- [x] **Step 2: Interactive loop**
  Read a line of jyutping, open a `NamedPipeClientStream`, send
  `input=<line>\ncommit=0\n.\n`, parse the JSON, and print numbered candidates
  plus `schema_id`. Support `:commit <input>` (send `commit=1`) and `:quit`.
  Reconnect per input (the server serves one request per connection).

- [x] **Step 3: Teardown**
  On exit, stop only the dev server process the script started.

- [x] **Step 4: Safety contract (static)**
  `test-dev-tooling-safety-contract.ps1` discovers every `tools\dev\*.ps1` file
  plus any dot-sourced dev helper under `tools\dev`, then throws if any scanned
  file contains `regsvr32`, `MOVEFILE_DELAY_UNTIL_REBOOT`, `Register-` (incl.
  `Register-ScheduledTask`), `New-Service`, `New-ItemProperty`,
  `Set-ItemProperty`, `Remove-ItemProperty`, `reg add`/`reg delete`/`reg.exe`,
  `schtasks`, `sc.exe`, `Start-Process -Verb RunAs`,
  `-ApprovedMachineStateChange`, or dot-sourcing / invoking
  `install-yune-windows-ime.ps1` or `uninstall-yune-windows-ime.ps1`. Confirm RED
  then GREEN.

## Task 2: Server hot-reload (`dev-reload-server.ps1`)

**Files:**
- Create: `tools\dev\dev-reload-server.ps1`

- [x] **Step 1: Rebuild the server** to a scratch build dir with
  `build-tsf-shell.ps1 -OutputDir <scratch> -YuneRoot <root>`.
- [x] **Step 2: Stop the installed server** by matching processes whose `Path`
  equals `<InstallDir>\YuneWindowsServer.exe`; wait for exit. During the swap
  window, a keystroke in a Yune-active field can trigger the product-owned
  auto-launch path and recreate the installed server, so hold the reload
  discipline by retrying stop/copy when the exe is briefly locked instead of
  assuming the server stays down.
- [x] **Step 3: Swap in the new server** by creating a timestamped backup of the
  installed `YuneWindowsServer.exe`, copying the scratch build into place, and
  restoring the backup if copy or readiness validation fails. With an optional
  `-RefreshSchema` switch, re-run `prepare-yune-product-data.ps1` into the
  install dir.
- [x] **Step 4: Restart** via `start-yune-windows-server.ps1 -InstallDir <dir>`
  `-WaitForReady` so the next keystroke does not pay the cold-start wait. If
  readiness fails, roll back to the timestamped backup and report the failure.
- [x] **Step 5:** Print the new server PID and readiness. Non-elevated
  throughout.

## Task 3: Disposable test app + TSF DLL swap

**Files:**
- Create: `tools\dev\dev-test-window.ps1`
- Create: `tools\dev\dev-reload-tsf.ps1`
- Create: `tools\test-dev-reload-no-reregister-contract.ps1`

- [x] **Step 1: `dev-test-window.ps1`** launches a fresh Notepad the script owns
  (records its PID) as the disposable test target, and prints how to select Yune
  (Win+Space). A custom titled edit window is a later nice-to-have.
- [x] **Step 2: `dev-reload-tsf.ps1`** rebuilds the DLL to a scratch dir (after
  the packaged-Yune preflight), enumerates holders of
  `<InstallDir>\YuneWindowsTSF.dll` via the read-only `dev-support.ps1` helper,
  closes the dev test app (and only that), waits for the DLL to unlock, creates a
  timestamped backup of the installed DLL, overwrites the installed DLL,
  validates that the swap landed, rolls back to the backup if validation fails,
  and relaunches the test app. If a non-dev holder remains, it aborts cleanly
  with holder guidance rather than forcing a reboot.
- [x] **Step 3:** Holder policy: unsafe holders (not the dev test app) abort with
  a printed summary; `-RestartExplorer` is the only opt-in that may bounce
  explorer. Never re-register.
- [x] **Step 4: No-reregister contract (static)**
  `test-dev-reload-no-reregister-contract.ps1` asserts `dev-reload-tsf.ps1`
  copies/overwrites the DLL and contains no `regsvr32` / `Register` call. RED then
  GREEN.

## Task 4: Watch wrapper (`dev-watch.ps1`)

**Files:**
- Create: `tools\dev\dev-watch.ps1`

- [x] **Step 1:** `FileSystemWatcher` on `src\server`, `src\tsf`,
  `src\candidate_window`, and the schema source; debounce changes.
- [x] **Step 2:** Route: `src\server\**` or schema -> `dev-reload-server.ps1`;
  `src\tsf\**` / `src\candidate_window\**` -> `dev-reload-tsf.ps1`.
  Default behavior is dry-run/print-only: print the reload command and reason
  without running it. Actual reloads require explicit `-AutoRun`; when `-AutoRun`
  is absent, no process stop, file copy, app close, or reload script invocation
  may occur.

## Task 5: Docs and non-elevated verification

**Files:**
- Create: `docs\dev\inner-loop.md`
- Modify: `docs\roadmap.md` (slot M03 as the chosen next milestone)

- [x] **Step 1:** Write `docs\dev\inner-loop.md`: the one-time approved
  install/register, then the free inner loop (`dev-repl` for engine/candidate
  bugs; `dev-reload-server` for server/schema; `dev-reload-tsf` for TSF/candidate
  window; `dev-watch` to automate). State clearly that no step after setup needs
  elevation, approval, re-registration, or a reboot.
- [x] **Step 2:** Run the dev safety and no-reregister contracts plus
  `git diff --check`. Run `dev-repl.ps1` end to end against a scratch server and
  confirm candidates for `ngohaig` include the expected commit. This is
  non-elevated and needs no install.
- [x] **Step 3:** Commit tooling and docs directly on `main` and push
  `origin/main`, preserving unrelated worktree changes and staging only the
  intended files.

## Reviewer Questions (for GPT)

- Is the two-loop split (server hot-restart vs. DLL swap) the right primitive, or
  should more product logic move server-side first to shrink the DLL loop?
- Is `dev-repl` on a dedicated dev pipe + scratch data the right isolation, given
  the pipe-scoped server mutex, or should it reuse the installed server?
- Should the disposable test app be Notepad (proven, simplest) or a purpose-built
  edit window from the start?
- Are the two static safety contracts sufficient to guarantee the inner loop
  never mutates machine state, or is a broader dev-tooling scan needed?
- Does `dev-watch` need any mode beyond the default dry-run/print-only behavior
  and explicit `-AutoRun`, or is that enough to avoid surprising rebuilds while
  the maintainer is mid-edit?

## Completion Gates

- `dev-repl.ps1` returns candidates for `ngohaig` with no install and no
  registration.
- `dev-reload-server.ps1` swaps and restarts the installed server without
  elevation and without touching registration; the next keystroke uses the new
  server. It keeps a timestamped backup of the installed server binary and rolls
  back if readiness validation fails.
- `dev-reload-tsf.ps1` swaps the installed DLL with no reboot and no
  re-registration **when the only holders are dev-owned/closeable apps**;
  otherwise it aborts cleanly with holder guidance (with an optional
  `-RestartExplorer` opt-in), never forcing a reboot. It keeps a timestamped
  backup of the installed TSF DLL and rolls back if swap validation fails.
- `dev-watch.ps1` defaults to dry-run/print-only and invokes reload scripts only
  with explicit `-AutoRun`.
- Dev scripts reimplement a read-only holder helper in `dev-support.ps1` and never
  dot-source the machine-mutating uninstaller.
- The two dev-tooling safety contracts pass and prove no machine-state mutation
  in the inner loop, scanning every `tools\dev\*.ps1` file and any dot-sourced
  dev helper.
- `docs\dev\inner-loop.md` documents one-time approved setup then a free,
  reboot-free inner loop.
- No product code under `src\**` changed.
