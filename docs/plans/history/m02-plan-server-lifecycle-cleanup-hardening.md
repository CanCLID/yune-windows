# M02 Server Lifecycle And Cleanup Hardening Implementation Plan

> Historical status: complete. This plan is retained for audit context. Current
> work should start from `docs/roadmap.md` and `docs/plans/active/README.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** make the installed Yune Windows IME dogfoodable without a separate
operator command to start `YuneWindowsServer.exe`, and make uninstall/cleanup
evidence actionable enough to reach a no-residue state after normal app
shutdown.

**Implementation status:** Complete on
`codex/m02-server-lifecycle-cleanup`.
Tasks 1-6 are implemented with non-elevated contracts green.
The first resumed Task 7/live closeout reached install/register and profile
activation, then failed Notepad because cold product-owned server readiness
outlasted the TSF readiness probe. The branch includes a cold-start readiness
contract and a 15-second TSF readiness probe. The next approved retry after
reboot proved the TSF DLL starts the installed product-owned server, but the
smoke harness captured the launch-triggering input before the cold server was
ready. The following approved retry proved the patched smoke waits for
product-owned readiness, but the launch probe remained in the active IME
composition buffer and caused Notepad to commit `我` instead of `我係個`. The
branch now adds a product-owned server readiness wait, composition cancel, and
target reset/retype path in the Notepad and Chromium smokes. The latest
approved live retry proved both installed text-field smokes: Notepad and
Chromium committed `我係個`, recorded `product_owned_server_start_observed:
True`, `product_owned_server_ready_observed: True`, and verified the profile
was active before typing. Cleanup initially scheduled approved delayed deletes
because GUI processes kept `YuneWindowsTSF.dll` loaded, then passed
post-reboot validation with no install directory, no pending delete residue, no
server process, and no registered TSF profile. The closeout audit is complete.

**Architecture:** keep the existing per-user shared server/IPC model, but move
server startup ownership into the product. The TSF DLL should request an
on-demand launch when the pipe is genuinely absent, avoid launching when the
pipe is merely busy, fail the triggering key path quickly, and let later
keystrokes connect after the server is ready. Cleanup hardening should keep
approval boundaries intact while recording exact `YuneWindowsTSF.dll` holders,
scheduled-delete fallback state, and cleanup transitions.

**Tech Stack:** Win32 TSF COM DLL in C++20, hidden per-user Win32 server process,
named-pipe IPC, PowerShell installer/smoke/contract tooling, Markdown/JSON/PNG
evidence under `docs/evidence`.

---

## Current Facts

- M01 proved the core development dogfood path under the Yune Windows
  names: install/register, profile activation, Notepad smoke, candidate display,
  candidate commit, Chromium smoke, diagnostics export, uninstall, and recovered
  cleanup evidence exist.
- Manual dogfood failed until `YuneWindowsServer.exe` was started explicitly.
  The TSF DLL received keystrokes and logged repeated `server_query_failed`
  entries, which means profile selection and key handling worked, but IPC had
  no server endpoint.
- Manual dogfood also exposed profile activation loss:
  `YuneWindowsProfileTool.exe --state` moved from `active=true` to
  `active=false` between setup and the target text field. M02 must not
  hide that with per-smoke `--activate` calls immediately before typing.
- The current smoke scripts call `tools\start-yune-windows-server.ps1` before
  typing. That is acceptable for pre-M02 harnesses but not for the product
  dogfood contract.
- Cleanup can still be blocked by GUI processes that keep
  `YuneWindowsTSF.dll` loaded after unregister. Existing uninstall code can find
  module holders and stop safe host processes, but the operator evidence path
  needs clearer structured results.
- Elevated install, unregister, registry cleanup, AppVerifier, PageHeap, and
  machine cleanup remain approval-gated. This plan must not weaken that rule.
- Yune remains the only runtime engine. Do not add a librime fallback and do not
  widen the default `rime_get_api()` ABI.

## Non-Goals

- Do not add a Windows service, scheduled task, Run-key autostart, or other
  persistent server launcher in the first M02 implementation slice.
  On-demand launch from the TSF DLL is the smallest path that removes the
  manual server-start requirement on classic desktop hosts. A per-user broker
  remains the documented fast-follow if UWP/AppContainer hosts, EDR policy, or
  daily-use browser coverage need it.
- Do not change Yune engine internals in this repo.
- Do not make WebView2 the inline candidate renderer.
- Do not make the uninstaller kill arbitrary user applications that loaded the
  TSF DLL. Report holders and stop only safe IME host processes unless the user
  explicitly approves a wider cleanup outside this plan.
- Do not mark dogfood release ready from non-elevated preflights alone.

## File Map

- Modify `src\tsf\yune_windows_tsf.cpp`
  - Add product-owned server launch and readiness helpers.
  - Add reason-specific structural events for IPC and server-launch failures.
  - Split busy-pipe reconnect from absent-pipe launch.
  - Add restricted-host launch gating and a launch cooldown.
- Modify `src\server\yune_windows_server.cpp`
  - Add a per-user single-instance mutex so stray duplicate launches exit
    cleanly.
- Modify `tools\run-notepad-smoke.ps1`
  - Remove the manual `tools\start-yune-windows-server.ps1` call from the
    default product smoke path.
  - Verify server autostart was observed after typing.
  - Stop programmatic profile activation immediately before typing; the live
    sequence must select the profile once and smokes must verify it stayed
    active.
- Modify `tools\run-chromium-smoke.ps1`
  - Mirror the Notepad smoke server-autostart behavior and evidence fields.
- Modify `tools\run-m01-live-smoke.ps1`
  - Treat product-owned server startup as a live closeout gate.
  - Keep the full install/register/Notepad/Chromium/diagnostics/uninstall/
    cleanup sequence approval-gated.
- Modify `tools\uninstall-yune-windows-ime.ps1`
  - Add structured cleanup result output while preserving the existing approval
    and elevation gates.
  - Add approved delayed-delete fallback with `MoveFileExW` for locked TSF DLL
    cleanup that requires sign-out or reboot.
- Modify `tools\live-smoke-support.ps1`
  - Add shared helpers for server-process snapshots and cleanup result
    validation if the existing helpers are not sufficient.
- Modify `tools\test-start-server-readiness-contract.ps1`
  - Keep readiness coverage for the diagnostic start tool, but remove the old
    requirement that Notepad and Chromium smokes manually call it.
- Modify `tools\test-tsf-server-query-timeout-contract.ps1`
  - Preserve the bounded I/O ordering invariant if implementation changes make
    the current literal matcher too narrow.
- Create `tools\test-tsf-server-autostart-contract.ps1`
  - Static contract test for TSF on-demand server startup.
- Create `tools\test-tsf-server-failure-reason-contract.ps1`
  - Static contract test for reason-specific structural failure events.
- Create `tools\test-yune-server-single-instance-contract.ps1`
  - Static contract test for server-side duplicate-launch protection.
- Create `tools\test-product-owned-server-smoke-contract.ps1`
  - Contract test that Notepad and Chromium smoke scripts no longer start the
    server manually.
- Create `tools\test-cold-profile-selection-contract.ps1`
  - Contract test that the live smokes do not hide activation loss by calling
    `--activate` immediately before typing.
- Create `tools\test-uninstall-structured-cleanup-result-contract.ps1`
  - Contract test for structured uninstall result evidence.
- Create `docs\evidence\m02\server-lifecycle\`
  - New evidence directory for M02 preflight, smoke, live, and cleanup
    artifacts.
- Modify `README.md`
  - Replace the manual server-start dogfood workaround after M02 passes.
- Modify `docs\roadmap.md`, `docs\requirements.md`, and `docs\decisions.md`
  - Update milestone status only when implementation evidence exists.

## Design Details

### On-Demand Server Startup

Use the TSF DLL install directory as the source of truth. In
`src\tsf\yune_windows_tsf.cpp`, `ModuleDirectory()` already resolves the
directory containing `YuneWindowsTSF.dll`; the launcher should derive:

```text
<module-dir>\YuneWindowsServer.exe
<module-dir>\rime.dll
<module-dir>\schema
<module-dir>\user-data
\\.\pipe\yune-windows-ime
```

The first `CreateFileW(kPipeName, ...)` failure should branch on
`GetLastError()`:

- `ERROR_PIPE_BUSY`: do not launch. Use `WaitNamedPipeW` with a short bounded
  wait, then reconnect.
- `ERROR_FILE_NOT_FOUND`: first use `WaitNamedPipeW` with a short bounded wait
  to cover the server's pipe-recreate gap; only request launch if the pipe is
  still absent.
- Other errors: log `server_query_connect_failed` and return failure.

Launch should use a local mutex such as
`Local\YuneWindowsServerLaunch_1788DBA7_CC9A_49E2_9C4C_E9DBF0BE2567` so
multiple TSF host processes do not start multiple servers for the same user
session. Re-check the pipe while holding the mutex before spawning. The server
itself must also own a per-user single-instance mutex because the diagnostic
`tools\start-yune-windows-server.ps1` can start it out of band. The server-side
mutex must be scoped to the requested pipe name, not to a fixed product GUID,
so hermetic tests using per-process pipes can run next to a real dogfood
server.

The TSF key path must not wait for first-run deploy. Launch should be
fire-and-forget with a process-wide cooldown. Keep the process handle only long
enough for a short readiness probe so the TSF DLL can distinguish
`server_launch_started`, `server_launch_ready`, `server_launch_pending`, and
`server_launch_exited`. The triggering keystroke can be eaten and produce no
candidate; later keystrokes should reconnect once the server is ready. Do not
block the foreground app for the diagnostic tool's 180-second readiness window.

Use `CreateProcessW` directly. Do not use PowerShell, `ShellExecute`, a service,
or elevated launch. The server should inherit the current user context and run
hidden:

```cpp
STARTUPINFOW startup = {};
startup.cb = sizeof(startup);
startup.dwFlags = STARTF_USESHOWWINDOW;
startup.wShowWindow = SW_HIDE;
PROCESS_INFORMATION process = {};
const DWORD flags = CREATE_NO_WINDOW;
```

Pass `bInheritHandles = FALSE`.

Before calling `CreateProcessW`, gate restricted hosts. If the TSF DLL is
loaded in an AppContainer or a low-integrity process where child process launch
is blocked or unsafe, skip launch and emit
`server_launch_skipped_restricted_host`. Classic desktop hosts such as Notepad
and Chromium browser processes should still be allowed when policy permits.
Launching an unsigned server from a medium-integrity browser process can still
be blocked by Defender ASR, SmartScreen, or endpoint policy; M02 should
record that as residual risk for the broker fast-follow rather than hiding it.

The command line must quote each argument:

```text
"<module-dir>\YuneWindowsServer.exe" --rime-dll "<module-dir>\rime.dll" --shared-dir "<module-dir>\schema" --user-dir "<module-dir>\user-data" --pipe "\\.\pipe\yune-windows-ime"
```

Do not log typed input. Structural events are allowed:

```text
event=server_launch_attempt
event=server_launch_started
event=server_launch_ready
event=server_launch_pending
event=server_launch_timeout
event=server_launch_exited
event=server_launch_failed
event=server_launch_skipped_restricted_host
event=server_query_connect_failed
event=server_query_pipe_busy
event=server_query_write_failed
event=server_query_read_timeout
event=server_query_invalid_response
```

Keep the existing universal `server_query_failed` event as the final failure
marker so existing bounded-I/O contracts keep their no-hang ordering invariant.
Emit reason-specific events before the final `return ServerQueryFailure(input);`
rather than replacing every return with a new helper signature.

### Cleanup Result Shape

Add a `-ResultPath` parameter to `tools\uninstall-yune-windows-ime.ps1`. When
provided, the script should write JSON even on failure. The object should be
small and stable:

```json
{
  "generated_at": "2026-06-29T00:00:00-07:00",
  "install_dir": "C:\\Users\\...\\AppData\\Local\\Yune\\WindowsIme",
  "approval_note_present": true,
  "profile_deactivated": true,
  "machine_registration_absent": true,
  "server_processes_stopped": true,
  "safe_module_hosts_stopped": [
    { "process_id": 123, "process_name": "ctfmon", "process_path": "C:\\Windows\\System32\\ctfmon.exe" }
  ],
  "module_holders_before_remove": [],
  "module_holders_after_remove": [],
  "install_dir_removed": true,
  "pending_delete_scheduled": false,
  "pending_delete_paths": [],
  "requires_reboot": false,
  "pass": true,
  "error": ""
}
```

If the install directory cannot be removed because user apps still hold
`YuneWindowsTSF.dll`, `pass` must be `false`, `install_dir_removed` must be
`false`, and `module_holders_after_remove` must list concrete process IDs and
names.

If normal removal fails after unregister and safe-host cleanup, the approved
uninstall path may call `MoveFileExW(path, NULL, MOVEFILE_DELAY_UNTIL_REBOOT)`
for locked Yune Windows files under the approved install directory. In that
case `pending_delete_scheduled=true`, `requires_reboot=true`, and
`pending_delete_paths` must list every scheduled path. The milestone can close
only after sign-out/reboot plus post-cleanup validation proves the scheduled
paths are gone.

## Task 1: Baseline M02 Plan And Contracts

**Files:**
- Create: `docs\evidence\m02\server-lifecycle\baseline.md`
- Create: `tools\test-tsf-server-autostart-contract.ps1`
- Create: `tools\test-tsf-server-failure-reason-contract.ps1`
- Create: `tools\test-yune-server-single-instance-contract.ps1`
- Create: `tools\test-product-owned-server-smoke-contract.ps1`
- Create: `tools\test-cold-profile-selection-contract.ps1`
- Create: `tools\test-uninstall-structured-cleanup-result-contract.ps1`

- [ ] **Step 1: Write baseline evidence**

Create `docs\evidence\m02\server-lifecycle\baseline.md`:

```markdown
# M02 Baseline

Status: planned

Known blocker from M01: manual dogfood requires a separate
`tools\start-yune-windows-server.ps1` command before typing. Without the shared
server, the TSF DLL receives keystrokes but logs `server_query_failed` and does
not show candidates.

M02 closes when:

- the installed TSF DLL starts or connects to `YuneWindowsServer.exe` without a
  separate operator server-start command;
- Notepad and Chromium smokes pass from a fresh install without manual server
  startup;
- uninstall writes structured cleanup evidence and reaches no-residue state
  after normal app shutdown or after an explicitly recorded sign-out/reboot
  when delayed delete is required for locked install-root files;
- closeout evidence remains under Yune Windows names only.
```

- [ ] **Step 2: Write TSF autostart contract test**

Create `tools\test-tsf-server-autostart-contract.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $TsfSource

$Required = @(
    'RequestSharedServerLaunch',
    'CreateProcessW',
    'YuneWindowsServer.exe',
    'rime.dll',
    'schema',
    'user-data',
    'WaitNamedPipeW',
    'ERROR_PIPE_BUSY',
    'ERROR_FILE_NOT_FOUND',
    'server_query_pipe_busy',
    'server_launch_attempt',
    'server_launch_started',
    'server_launch_ready',
    'server_launch_pending',
    'server_launch_timeout',
    'server_launch_exited',
    'server_launch_failed',
    'server_launch_skipped_restricted_host'
)

foreach ($Pattern in $Required) {
    if ($Source -notmatch [regex]::Escape($Pattern)) {
        throw "TSF server autostart source is missing required pattern: $Pattern"
    }
}

$Forbidden = @(
    'ShellExecute',
    'powershell',
    'schtasks',
    'SERVICE_WIN32',
    'HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
)

foreach ($Pattern in $Forbidden) {
    if ($Source -match [regex]::Escape($Pattern)) {
        throw "TSF server autostart must not use persistent or shell-based launch path: $Pattern"
    }
}

Write-Host "TSF owns bounded on-demand YuneWindowsServer startup."
```

- [ ] **Step 3: Write failure-reason logging contract test**

Create `tools\test-tsf-server-failure-reason-contract.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $TsfSource

$RequiredEvents = @(
    'server_query_connect_failed',
    'server_query_pipe_busy',
    'server_query_write_failed',
    'server_query_read_timeout',
    'server_query_invalid_response'
)

foreach ($EventName in $RequiredEvents) {
    if ($Source -notmatch "WriteStructuralEvent\(`"$([regex]::Escape($EventName))`"") {
        throw "TSF query path must log structural event $EventName"
    }
}

foreach ($Forbidden in @(
        'WriteStructuralEvent\([^;]*Narrow\(input\)',
        'WriteStructuralEvent\([^;]*\brequest\b',
        'log << input',
        'log << Narrow\(input\)'
    )) {
    if ($Source -match $Forbidden) {
        throw "TSF structural logging must not write typed input content: $Forbidden"
    }
}

if ($Source -notmatch 'return ServerQueryFailure\(input\);') {
    throw "TSF query path must keep the universal server_query_failed return for existing timeout-ordering contracts."
}

Write-Host "TSF server query failures are reason-specific and structural."
```

- [ ] **Step 4: Write server single-instance contract test**

Create `tools\test-yune-server-single-instance-contract.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")

foreach ($Pattern in @(
        'CreateMutexW',
        'YuneWindowsServerSingleInstance',
        'ServerInstanceMutexName',
        'args.pipe_name',
        'ERROR_ALREADY_EXISTS',
        'YuneWindowsServer failed'
    )) {
    if ($ServerSource -notmatch [regex]::Escape($Pattern)) {
        throw "Shared server is missing single-instance guard pattern: $Pattern"
    }
}

Write-Host "Shared server exits cleanly when a per-user instance already exists."
```

- [ ] **Step 5: Write product-owned smoke contract test**

Create `tools\test-product-owned-server-smoke-contract.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$NotepadSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-notepad-smoke.ps1")
$ChromiumSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-chromium-smoke.ps1")

foreach ($Entry in @(
        @{ Name = "Notepad"; Source = $NotepadSmoke },
        @{ Name = "Chromium"; Source = $ChromiumSmoke }
    )) {
    if ($Entry.Source -match 'start-yune-windows-server\.ps1') {
        throw "$($Entry.Name) smoke must not manually start YuneWindowsServer.exe after M02."
    }
    foreach ($Pattern in @(
            'Assert-NoYuneWindowsServerProcess',
            'product_owned_server_start_observed',
            'ProductOwnedServerStartObserved',
            'YuneWindowsServer'
        )) {
        if ($Entry.Source -notmatch [regex]::Escape($Pattern)) {
            throw "$($Entry.Name) smoke is missing product-owned server evidence pattern: $Pattern"
        }
    }
}

Write-Host "Text-field smokes rely on product-owned shared-server startup."
```

- [ ] **Step 6: Write cold profile-selection contract test**

Create `tools\test-cold-profile-selection-contract.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$NotepadSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-notepad-smoke.ps1")
$ChromiumSmoke = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\run-chromium-smoke.ps1")

foreach ($Entry in @(
        @{ Name = "Notepad"; Source = $NotepadSmoke },
        @{ Name = "Chromium"; Source = $ChromiumSmoke }
    )) {
    if ($Entry.Source -match '--activate') {
        throw "$($Entry.Name) smoke must not reactivate the profile immediately before typing."
    }
    foreach ($Pattern in @(
            'Assert-YuneWindowsProfileActive',
            'profile_active_verified_before_typing'
        )) {
        if ($Entry.Source -notmatch [regex]::Escape($Pattern)) {
            throw "$($Entry.Name) smoke is missing cold profile verification pattern: $Pattern"
        }
    }
}

Write-Host "Text-field smokes verify profile selection without hiding activation loss."
```

- [ ] **Step 7: Write uninstall structured-result contract test**

Create `tools\test-uninstall-structured-cleanup-result-contract.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$UninstallScript = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$Source = Get-Content -Raw -LiteralPath $UninstallScript

$Required = @(
    '[string]$ResultPath',
    'module_holders_before_remove',
    'module_holders_after_remove',
    'safe_module_hosts_stopped',
    'install_dir_removed',
    'machine_registration_absent',
    'pending_delete_scheduled',
    'pending_delete_paths',
    'requires_reboot',
    'MoveFileEx',
    'MOVEFILE_DELAY_UNTIL_REBOOT',
    'ConvertTo-Json'
)

foreach ($Pattern in $Required) {
    if ($Source -notmatch [regex]::Escape($Pattern)) {
        throw "Uninstaller structured cleanup result is missing required pattern: $Pattern"
    }
}

if ($Source -notmatch 'pass\s*=') {
    throw "Uninstaller result must include a boolean pass field."
}

Write-Host "Uninstaller writes structured cleanup result evidence."
```

- [ ] **Step 8: Run contracts and verify RED**

Run each new contract before implementation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-autostart-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-failure-reason-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-single-instance-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-product-owned-server-smoke-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-cold-profile-selection-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-uninstall-structured-cleanup-result-contract.ps1
```

Expected: all six fail before implementation.

- [ ] **Step 9: Commit contracts**

```powershell
git add docs\evidence\m02\server-lifecycle\baseline.md tools\test-tsf-server-autostart-contract.ps1 tools\test-tsf-server-failure-reason-contract.ps1 tools\test-yune-server-single-instance-contract.ps1 tools\test-product-owned-server-smoke-contract.ps1 tools\test-cold-profile-selection-contract.ps1 tools\test-uninstall-structured-cleanup-result-contract.ps1
git commit -m "test: define p2 win02 lifecycle contracts"
```

## Task 2: Implement TSF On-Demand Server Startup

**Files:**
- Modify: `src\tsf\yune_windows_tsf.cpp`
- Modify: `src\server\yune_windows_server.cpp`
- Test: `tools\test-tsf-server-autostart-contract.ps1`
- Test: `tools\test-tsf-server-failure-reason-contract.ps1`
- Test: `tools\test-yune-server-single-instance-contract.ps1`
- Test: `tools\test-tsf-server-query-timeout-contract.ps1`
- Test: `tools\test-tsf-server-query-contract.ps1`

- [ ] **Step 1: Add launch helper declarations near `ModuleDirectory()`**

Add helper functions with these responsibilities:

```cpp
std::wstring QuoteCommandLineArgument(const std::filesystem::path& value);
bool PathExists(const std::filesystem::path& value);
bool WaitForSharedServerPipe(DWORD timeout_ms);
bool CanLaunchSharedServerFromCurrentHost();
bool RequestSharedServerLaunch();
```

`RequestSharedServerLaunch()` must be idempotent and bounded. It should use a
local mutex, re-check the pipe while holding the mutex, respect a process-wide
cooldown, and return without throwing if launch or readiness probing fails.

- [ ] **Step 2: Implement command-line quoting**

Use a conservative Windows command-line quoting helper. It must wrap every path
in quotes and preserve backslashes before quotes:

```cpp
std::wstring QuoteCommandLineArgument(const std::filesystem::path& value) {
    std::wstring input = value.wstring();
    std::wstring output = L"\"";
    size_t backslashes = 0;
    for (wchar_t ch : input) {
        if (ch == L'\\') {
            ++backslashes;
            continue;
        }
        if (ch == L'"') {
            output.append(backslashes * 2 + 1, L'\\');
            output.push_back(ch);
            backslashes = 0;
            continue;
        }
        output.append(backslashes, L'\\');
        backslashes = 0;
        output.push_back(ch);
    }
    output.append(backslashes * 2, L'\\');
    output.push_back(L'"');
    return output;
}
```

- [ ] **Step 3: Add server-side single-instance guard**

In `src\server\yune_windows_server.cpp`, add a pipe-scoped mutex-name helper:

```cpp
std::wstring ServerInstanceMutexName(const std::wstring& pipe_name) {
    std::wstring suffix;
    suffix.reserve(pipe_name.size());
    for (wchar_t ch : pipe_name) {
        if ((ch >= L'0' && ch <= L'9') ||
            (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'a' && ch <= L'z') ||
            ch == L'_' || ch == L'-') {
            suffix.push_back(ch);
        } else {
            suffix.push_back(L'_');
        }
    }
    return L"Local\\YuneWindowsServerSingleInstance_" + suffix;
}
```

Then create the mutex early in `wmain` after argument parsing and before
`YuneRuntime runtime(args);`:

```cpp
const std::wstring mutex_name = ServerInstanceMutexName(args.pipe_name);
HANDLE single_instance = CreateMutexW(
    nullptr, TRUE, mutex_name.c_str());
if (!single_instance) {
    throw std::runtime_error("failed to create server single-instance mutex");
}
if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(single_instance);
    return 0;
}
```

Close `single_instance` before normal return and in the catch path. A duplicate
server for the same pipe should exit cleanly instead of throwing after
`CreateNamedPipeW` fails. A diagnostic server using
`\\.\pipe\yune-windows-ime-<pid>` must not block or be blocked by the real
dogfood server on `\\.\pipe\yune-windows-ime`.

- [ ] **Step 4: Implement `RequestSharedServerLaunch()`**

Use `ModuleDirectory()` and require all product-owned runtime paths to exist
before launch. Log structural events for every outcome:

```text
server_launch_attempt
server_launch_started
server_launch_pending
server_launch_exited
server_launch_failed
server_launch_skipped_restricted_host
```

Launch command:

```text
"YuneWindowsServer.exe" --rime-dll "rime.dll" --shared-dir "schema" --user-dir "user-data" --pipe "\\.\pipe\yune-windows-ime"
```

Call `CreateProcessW` with `bInheritHandles = FALSE`. Keep `hProcess` only
during a short readiness probe so `GetExitCodeProcess` can distinguish
"launched and still deploying" from "exited during deploy"; then close both
process and thread handles.

If `CanLaunchSharedServerFromCurrentHost()` detects AppContainer or low
integrity, skip `CreateProcessW` and emit
`server_launch_skipped_restricted_host`.

- [ ] **Step 5: Implement bounded pipe wait**

`WaitForSharedServerPipe()` should use `WaitNamedPipeW(kPipeName, remaining_ms)`
in a loop until the deadline expires. It is used in two paths:

- `ERROR_PIPE_BUSY`: wait and reconnect; never launch.
- `ERROR_FILE_NOT_FOUND`: wait and reconnect first to cover the server's
  `CloseHandle` to next `CreateNamedPipeW` gap; launch only if the pipe remains
  absent.

It should log:

```text
server_launch_ready
server_launch_timeout
server_query_pipe_busy
```

Do not sleep unboundedly. Do not use the diagnostic tool's 180-second readiness
window on the foreground key path. Keep the launch probe small enough that a
first-run deploy cannot freeze the host UI; the triggering keystroke may be
eaten with no candidate, and later keystrokes should connect once ready.

- [ ] **Step 6: Retry only after the correct connection state**

In `QueryServer()`:

- On `ERROR_PIPE_BUSY`, emit `server_query_pipe_busy`, call
  `WaitForSharedServerPipe(...)`, and retry `CreateFileW` once. If retry fails,
  log `server_query_connect_failed` and return `ServerQueryFailure(input)`.
- On `ERROR_FILE_NOT_FOUND`, first call `WaitForSharedServerPipe(...)` and
  retry once. If the pipe is still absent, call `RequestSharedServerLaunch()`.
  If launch is pending or skipped, return `ServerQueryFailure(input)` quickly.
  If launch reports a ready pipe during the short probe, retry once.
- On other `CreateFileW` errors, log `server_query_connect_failed` and return
  `ServerQueryFailure(input)`.

- [ ] **Step 7: Split reason-specific query failures without breaking timeout contracts**

Keep the existing bare return shape:

```cpp
WriteStructuralEvent("server_query_write_failed");
return ServerQueryFailure(input);
```

Use that pattern for connect, write, read timeout, and invalid response
failures. This preserves the `tools\test-tsf-server-query-timeout-contract.ps1`
ordering invariant around `return ServerQueryFailure(input);` while adding
reason-specific diagnostics. Do not route these through a string-parameter
helper unless the contract is updated to grep that helper call instead of the
literal `WriteStructuralEvent("server_query_*")` tokens. The log call must
never log the input text.

- [ ] **Step 8: Run TSF/server contracts**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-autostart-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-failure-reason-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-single-instance-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-query-timeout-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-query-contract.ps1
```

Expected: all pass.

- [ ] **Step 9: Build shell**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

Expected: `YuneWindowsTSF.dll`, `YuneWindowsServer.exe`,
`YuneWindowsProfileTool.exe`, and `YuneWindowsCandidateWindowSmoke.exe` are
built.

- [ ] **Step 10: Commit TSF startup implementation**

```powershell
git add src\tsf\yune_windows_tsf.cpp src\server\yune_windows_server.cpp
git commit -m "feat: autostart yune windows shared server from tsf"
```

## Task 3: Move Text-Field Smokes To Product-Owned Server Startup

**Files:**
- Modify: `tools\run-notepad-smoke.ps1`
- Modify: `tools\run-chromium-smoke.ps1`
- Modify: `tools\live-smoke-support.ps1`
- Modify: `tools\test-start-server-readiness-contract.ps1`
- Test: `tools\test-product-owned-server-smoke-contract.ps1`
- Test: `tools\test-cold-profile-selection-contract.ps1`

- [ ] **Step 1: Remove manual server start from Notepad smoke**

In `tools\run-notepad-smoke.ps1`, remove the call to
`tools\start-yune-windows-server.ps1`. Keep the precondition that no
`YuneWindowsServer.exe` process is running before typing.

- [ ] **Step 2: Remove immediate profile reactivation from Notepad smoke**

Remove the `Invoke-YuneWindowsProfileTool --activate` call from the Notepad
smoke's focused-text-field path. The full live sequence may select the Yune
Windows profile once before launching the text-field smokes, but the smoke
itself must only verify:

```powershell
Assert-YuneWindowsProfileActive `
    -ProfileToolPath $ProfileTool `
    -Context "Notepad smoke before typing"
$ProfileActiveVerifiedBeforeTyping = $true
```

If the profile has fallen inactive, fail the smoke with clear evidence instead
of re-activating and hiding the product issue.

Write the exact evidence key:

```text
profile_active_verified_before_typing: True
```

The source should contain both `$ProfileActiveVerifiedBeforeTyping` and
`profile_active_verified_before_typing` so
`tools\test-cold-profile-selection-contract.ps1` flips from RED to GREEN.

- [ ] **Step 3: Capture product-owned server evidence in Notepad smoke**

After typed input and before commit, capture server processes:

```powershell
$ServerProcessesAfterTyping = @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
    Where-Object {
        try {
            $_.Path -eq (Join-Path $InstallRoot "YuneWindowsServer.exe")
        }
        catch {
            $false
        }
    })
$ProductOwnedServerStartObserved = $ServerProcessesAfterTyping.Count -gt 0
```

Write result field:

```text
product_owned_server_start_observed: True
```

The source should contain both the PowerShell variable
`$ProductOwnedServerStartObserved` and the exact evidence key
`product_owned_server_start_observed` so
`tools\test-product-owned-server-smoke-contract.ps1` flips from RED to GREEN.
Make `ProductOwnedServerStartObserved` part of the pass condition.

- [ ] **Step 4: Stop the product-owned server during smoke cleanup**

In the `finally` block, stop only `YuneWindowsServer.exe` processes whose
`Path` equals the installed server path. Use existing
`Wait-YuneWindowsProcessExit` for bounded cleanup.

- [ ] **Step 5: Mirror the same behavior in Chromium smoke**

Apply the same server-start removal, immediate-activation removal, evidence
capture, pass condition, and cleanup in `tools\run-chromium-smoke.ps1`.

- [ ] **Step 6: Update the diagnostic start-tool contract**

Modify `tools\test-start-server-readiness-contract.ps1` so it still verifies
`tools\start-yune-windows-server.ps1 -WaitForReady`, but no longer requires the
Notepad and Chromium smoke scripts to call it. The test should instead assert
the start script remains available as a diagnostic helper.

- [ ] **Step 7: Add shared helper only if duplication becomes brittle**

The profile and server precondition helpers already exist in
`tools\live-smoke-support.ps1`:

```powershell
Assert-NoYuneWindowsServerProcess
Assert-YuneWindowsProfileActive
```

Use those existing helpers; do not duplicate them in the smoke scripts.

If both smoke scripts need more than 20 duplicated lines, add this helper to
`tools\live-smoke-support.ps1`:

```powershell
function Get-YuneWindowsInstalledServerProcesses {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    $ServerPath = Join-Path $InstallDir "YuneWindowsServer.exe"
    return @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -eq $ServerPath
            }
            catch {
                $false
            }
        } |
        Select-Object Id, ProcessName, Path, StartTime)
}
```

- [ ] **Step 8: Run smoke contracts**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-start-server-readiness-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-product-owned-server-smoke-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-cold-profile-selection-contract.ps1
```

Expected: pass.

- [ ] **Step 9: Run non-elevated build/smoke checks**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-host-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-ipc-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1
```

Expected: all pass.

- [ ] **Step 10: Commit smoke harness update**

```powershell
git add tools\run-notepad-smoke.ps1 tools\run-chromium-smoke.ps1 tools\live-smoke-support.ps1 tools\test-start-server-readiness-contract.ps1
git commit -m "test: require product-owned server startup in smokes"
```

## Task 4: Add Structured Cleanup Result Evidence

**Files:**
- Modify: `tools\uninstall-yune-windows-ime.ps1`
- Modify: `tools\run-m01-live-smoke.ps1`
- Modify: `tools\live-smoke-support.ps1`
- Test: `tools\test-uninstall-structured-cleanup-result-contract.ps1`
- Test: `tools\test-uninstall-install-dir-retry-contract.ps1`
- Test: `tools\test-uninstall-profile-state-contract.ps1`

- [ ] **Step 1: Add `-ResultPath` to uninstaller**

Extend the param block:

```powershell
[string]$ResultPath = ""
```

Do not make it mandatory. Existing callers without `-ResultPath` must keep
working.

- [ ] **Step 2: Track cleanup state**

Initialize an ordered cleanup result object after `$InstallRoot` is resolved:

```powershell
$CleanupResult = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    install_dir = $InstallRoot
    approval_note_present = -not [string]::IsNullOrWhiteSpace($ApprovalNote)
    profile_deactivated = $false
    machine_registration_absent = $false
    server_processes_stopped = $false
    safe_module_hosts_stopped = @()
    module_holders_before_remove = @()
    module_holders_after_remove = @()
    install_dir_removed = $false
    pending_delete_scheduled = $false
    pending_delete_paths = @()
    requires_reboot = $false
    pass = $false
    error = ""
}
```

- [ ] **Step 3: Record module holders before removal**

Before calling `Remove-YuneWindowsInstallDirectoryWithRetry`, record:

```powershell
$CleanupResult.module_holders_before_remove =
    @(Get-YuneWindowsProcessesUsingModule -ModulePath $TsfDll)
```

When safe host processes are stopped, record those process objects in
`safe_module_hosts_stopped`.

- [ ] **Step 4: Write result in success and failure paths**

Add a helper:

```powershell
function Write-YuneWindowsCleanupResult {
    param(
        [Parameter(Mandatory = $true)][object]$Result,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent)) {
        New-Item -ItemType Directory -Force $Parent | Out-Null
    }
    $Result | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Path -Encoding utf8
}
```

Wrap the main uninstall body so both success and failure write the result. On
failure, set `error` to `$_.Exception.Message`, refresh
`module_holders_after_remove`, and keep `pass=false`.

- [ ] **Step 5: Add approved delayed-delete fallback**

Add a PowerShell P/Invoke wrapper for `MoveFileExW` with
`MOVEFILE_DELAY_UNTIL_REBOOT`. Use it only after:

- `Require-Approval`, `Require-LiveSmokeApprovalNote`, and
  `Require-Administrator` have all completed in the elevated uninstall path;
- profile deactivation and unregister have completed or machine registration is
  already absent;
- safe host cleanup has run;
- normal `Remove-Item -Recurse -Force` with retry still failed;
- the target path is inside the resolved approved install directory.

When fallback is used, set:

```powershell
$CleanupResult.pending_delete_scheduled = $true
$CleanupResult.pending_delete_paths = @($ScheduledPaths)
$CleanupResult.requires_reboot = $true
$CleanupResult.pass = $false
```

Do not schedule deletion for arbitrary user-app paths or machine-level paths
outside the approved install root.

- [ ] **Step 6: Wire live smoke to structured cleanup result**

In `tools\run-m01-live-smoke.ps1`, pass:

```powershell
-ResultPath (Join-Path $InstallerEvidence "uninstall-result.json")
```

When cleanup fails, include the result path in the failure summary. If
`requires_reboot=true`, write that the live closeout is pending sign-out/reboot
and post-cleanup validation, not failed implementation evidence.

- [ ] **Step 7: Run cleanup contracts**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-uninstall-structured-cleanup-result-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-uninstall-install-dir-retry-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-uninstall-profile-state-contract.ps1
```

Expected: all pass.

- [ ] **Step 8: Commit cleanup evidence support**

```powershell
git add tools\uninstall-yune-windows-ime.ps1 tools\run-m01-live-smoke.ps1 tools\live-smoke-support.ps1
git commit -m "test: record structured yune windows cleanup result"
```

## Task 5: Refresh Docs For The New Dogfood Contract

**Files:**
- Modify: `README.md`
- Modify: `docs\roadmap.md`
- Modify: `docs\requirements.md`
- Modify: `docs\decisions.md`
- Modify: `docs\plans\active\m02-plan-server-lifecycle-cleanup-hardening.md`

- [ ] **Step 1: Update README after implementation**

Replace the manual dogfood instruction that tells users to run
`tools\start-yune-windows-server.ps1` with this contract:

```markdown
The installed TSF DLL starts the per-user `YuneWindowsServer.exe` on demand
when the Yune Windows profile receives composition input. Manual
`tools\start-yune-windows-server.ps1` remains a diagnostic helper, not a
dogfood prerequisite.
```

Keep the approval-gated install and cleanup warnings.

- [ ] **Step 2: Update requirements**

Mark `WIN-12` complete only after the product-owned server smoke evidence
passes. Keep `WIN-10` open until the full approved live closeout succeeds.

- [ ] **Step 3: Update roadmap**

Move M02 from recommended to active/in-progress while implementation is
underway. After live closeout, set the next gate to dogfood package hardening.

- [ ] **Step 4: Maintain Claude review disposition**

If additional review arrives, update the `## Claude Review Disposition` section
with accepted changes and rejected changes. Each rejected change needs one
sentence explaining the product or safety reason.

- [ ] **Step 5: Run docs check**

```powershell
git diff --check
```

Expected: no output.

- [ ] **Step 6: Commit docs update**

```powershell
git add README.md docs\roadmap.md docs\requirements.md docs\decisions.md docs\plans\active\m02-plan-server-lifecycle-cleanup-hardening.md
git commit -m "docs: update p2 win02 dogfood contract"
```

## Task 6: Run Non-Elevated Verification

**Files:**
- Read: `docs\evidence\m02\server-lifecycle\`
- Modify: evidence files only when commands produce new M02 evidence

- [ ] **Step 1: Package Yune**

From `C:\Users\laubonghaudoi\Documents\GitHub\yune`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-yune-windows.ps1
```

Expected: packaged `rime.dll`, headers, and dynamic-loader smoke pass.

- [ ] **Step 2: Run naming gate**

From `C:\Users\laubonghaudoi\Documents\GitHub\yune-windows`, scan for old
product-name hits:

```powershell
$OldProductNamePattern = ("Type" + "Duck|Typed" + "uck|typed" + "uck|TYPE_" + "DUCK|Type " + "Duck")
rg -n $OldProductNamePattern --hidden -g "!/.git/**" .
```

Expected: exit code `1` with no output, meaning no old product-name hits.

- [ ] **Step 3: Build Windows shell**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-tsf-shell.ps1 -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

Expected: build succeeds and emits all four Yune Windows binaries.

- [ ] **Step 4: Run contract and smoke suite**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-shell-build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-host-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-ipc-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-candidate-window-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-autostart-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-tsf-server-failure-reason-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-yune-server-single-instance-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-start-server-readiness-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-product-owned-server-smoke-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-cold-profile-selection-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-uninstall-structured-cleanup-result-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-install-dir-safety-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-machine-state-approval-gates.ps1
```

Expected: all pass without elevated machine-state changes.

- [ ] **Step 5: Commit verification evidence if generated**

```powershell
git add docs\evidence\m02\server-lifecycle
git commit -m "docs: add p2 win02 non elevated evidence"
```

Only commit if new evidence files were generated.

## Task 7: Run Approved Live Closeout

**Files:**
- Modify: `docs\evidence\m02\server-lifecycle\`
- Modify: `docs\evidence\m01\installer\` only if the existing live-smoke
  scripts still write there
- Read: `docs\evidence\m01\closeout\audit.json`

- [ ] **Step 1: Stop at approval boundary**

Before elevated install/register/unregister/cleanup or app automation, ask for
fresh explicit approval in the current session. Do not reuse approval from
M01.

- [ ] **Step 2: Run full live path**

After approval, run the full live path with the existing launcher:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\run-m01-live-smoke.ps1 -ApprovedMachineStateChange -ApprovalNote "User approved M02 live install/register/smoke/uninstall/cleanup in this session." -YuneRoot C:\Users\laubonghaudoi\Documents\GitHub\yune
```

Expected live behavior:

- install/register succeeds;
- Yune Windows profile selection happens once before text-field smokes;
- Notepad and Chromium smokes verify the profile is still active before typing
  but do not run `YuneWindowsProfileTool.exe --activate` immediately before
  typing;
- Notepad smoke passes without manual `start-yune-windows-server.ps1`;
- structural log contains `server_launch_started` plus either
  `server_launch_ready` or `server_launch_pending` followed by successful
  later `candidate_update`;
- candidate display and commit evidence exists;
- Chromium smoke passes without manual server startup;
- diagnostics export exists and has structural logs only;
- if Defender ASR, SmartScreen, or other endpoint policy blocks the unsigned
  server launch, the transcript and structural logs record that as a M02
  blocker and the per-user broker fast-follow becomes the next path;
- uninstall result JSON records `pass=true`, or records
  `requires_reboot=true` with approved delayed-delete paths under the install
  root;
- cleanup validation records no install directory, no TSF DLL, no server
  process, no TSF profile, and no machine residue. If delayed delete was used,
  this validation must happen after sign-out/reboot.

- [ ] **Step 3: Audit closeout**

Run the closeout audit command used by M01. If a new M02 audit script
is created during implementation, run that instead and keep M01 evidence
unchanged.

Expected: product-owned server startup and cleanup gates pass. Dogfood release
readiness remains a separate decision unless the audit explicitly says the full
live path is clean.

- [ ] **Step 4: Commit live evidence**

```powershell
git add docs\evidence
git commit -m "docs: add p2 win02 live dogfood evidence"
```

- [ ] **Step 5: Push branch for review**

```powershell
git push origin HEAD
```

Use a branch name under `codex/`, for example:

```text
codex/m02-server-lifecycle-cleanup
```

## Claude Review Disposition

Accepted changes from the first Claude review:

- Preserve the existing `return ServerQueryFailure(input);` timeout-contract
  shape and emit reason-specific events before that universal failure return.
- Update `tools\test-start-server-readiness-contract.ps1` in lockstep when
  smokes stop manually starting the server.
- Fix the privacy contract so it forbids logging typed content, not the local
  identifier `input` used for `input.size()`.
- Treat `ERROR_PIPE_BUSY` as an existing busy server: wait and reconnect, never
  launch.
- Add client-side `WaitNamedPipeW` before concluding `ERROR_FILE_NOT_FOUND`
  means absent, covering the server's pipe-recreate gap.
- Add a server-side single-instance mutex because the diagnostic start tool can
  start a server out of band.
- Avoid long UI-thread blocking during first-run deploy; launch should be
  fire-and-forget with cooldown and a short readiness probe.
- Keep `hProcess` during the short readiness probe so an immediate launch exit
  can be logged distinctly.
- Gate in-host launch for restricted/AppContainer/low-integrity processes and
  document the per-user broker as a fast-follow if coverage or policy requires
  it.
- Stop hiding activation loss in smokes by re-running `--activate` immediately
  before typing.
- Add approved `MoveFileExW(..., MOVEFILE_DELAY_UNTIL_REBOOT)` fallback for
  locked install-root files and require post-reboot validation before closeout.

Accepted changes from the second Claude review:

- Scope the server-side single-instance mutex to `args.pipe_name` so hermetic
  test pipes and the real dogfood pipe do not block each other.
- Anchor the privacy regex to `\brequest\b` so existing `commit_request`
  structural events remain valid.
- Inline literal `WriteStructuralEvent("server_query_*")` calls before
  `return ServerQueryFailure(input);` so the static contract can turn GREEN.
- Align the smoke evidence contract with an exact
  `product_owned_server_start_observed` evidence key.
- Clarify that `Assert-NoYuneWindowsServerProcess` and
  `Assert-YuneWindowsProfileActive` already exist in
  `tools\live-smoke-support.ps1` and should be reused, not recreated.
- Record AV/EDR blocking of unsigned in-host server launch as live-run residual
  risk and broker-fast-follow evidence.
- State explicitly that the delayed-delete fallback runs only after the
  elevated uninstall approval and administrator gates.

Rejected or deferred changes:

- A per-user broker is deferred from the first implementation slice. On-demand
  TSF launch is still the smallest classic-desktop fix, but the plan now treats
  the broker as a known fast-follow rather than an indefinite maybe.
- Killing arbitrary GUI applications that hold `YuneWindowsTSF.dll` remains out
  of scope. The product should report holders, stop only safe IME hosts, and use
  approved delayed delete or sign-out/reboot recovery.

## Completion Gates

M02 is complete only when all of these are true:

- Manual dogfood no longer requires `tools\start-yune-windows-server.ps1`.
- Notepad smoke passes from a fresh install and records product-owned server
  startup without per-smoke `--activate` immediately before typing.
- Chromium smoke passes from a fresh install and records product-owned server
  startup without per-smoke `--activate` immediately before typing.
- TSF structural logs distinguish busy-pipe, launch, restricted-host,
  connect/write/read/invalid-response failures without typed-content logs.
- Duplicate shared-server starts exit cleanly through a server-side
  single-instance guard.
- Uninstall writes structured cleanup result evidence on success and failure.
- Full approved live path reaches no install directory, no TSF DLL, no server
  process, no TSF profile, and no machine residue. If locked-file cleanup
  schedules delayed delete, this gate closes only after sign-out/reboot and a
  clean post-reboot validation.
- README, roadmap, requirements, decisions, and evidence paths match the proven
  behavior.
