# 2026-07-02 Post-Reboot Reload Retry

Scope: non-elevated retry of the M06/M07 holder-free reload sequence after a
reboot. No elevated install/register/unregister/cleanup/AppVerifier/PageHeap or
registry steps were run.

## Server Reload

- `tools\collect-m06-compatibility-environment.ps1` refreshed
  `docs\evidence\m06\environment.json`.
- Initial `tools\dev\dev-reload-server.ps1 -RefreshSchema` built the scratch
  artifacts, copied `YuneWindowsServer.exe`, then timed out waiting for
  `\\.\pipe\yune-windows-ime`; the script restored the installed server backup.
- Root cause: installed `state\ime-state.json` persisted
  `schema_id=luna_pinyin`, while the readiness probe accepted only the
  `jyut6ping3` first candidate for `ngohaig`.
- Minimal probe without the hardcoded readiness gate started the installed
  server as PID 4260, returned `ready=true`, `state_schema=luna_pinyin`,
  `input_schema=luna_pinyin`, and `candidate_count=30`, then stopped PID 4260.
- After the readiness probe was changed to accept the persisted active schema,
  `tools\dev\dev-reload-server.ps1 -RefreshSchema` passed and reloaded the
  installed server as PID 19632.

## TSF DLL Reload

- `tools\dev\dev-reload-tsf.ps1 -RestartExplorer` built scratch artifacts but
  stopped before copying the installed DLL.
- Remaining holder: `Codex[19200]`
  `C:\Program Files\WindowsApps\OpenAI.Codex_26.623.11225.0_x64__2p2nqsd0c76g0\app\Codex.exe`.
- Codex was not force-closed, and `YuneWindowsProfileTool.exe --deactivate` was
  not run.
- M06/M07 live host verification remains pending until the installed TSF DLL can
  be swapped from a holder-free session.
