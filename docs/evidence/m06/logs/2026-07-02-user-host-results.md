# 2026-07-02 User Host Results After Approved TSF Reload

Status: live host compatibility attempt failed outside Notepad; raw fallback fix
implemented in source and awaiting a holder-free installed TSF reload.

## User Report

After the approved non-elevated `tools\dev\dev-reload-tsf.ps1 -RestartExplorer`
swap:

- Notepad worked and normal typing succeeded.
- Chrome failed: typing produced no output.
- Zed failed: typing produced no output. VS Code is not installed.
- Telegram Desktop failed: typing produced no output.
- Windows File Explorer failed: typing produced no output.
- WeChat is not installed or was not tested.

## Captured Evidence

- M06 TSF log window:
  `docs\evidence\m06\logs\m06-m07-user-host-failures-tsf-events.md`.
- M07 TSF log window:
  `docs\evidence\m07\logs\m07-user-host-failures-tsf-events.md`.
- The M06 and M07 log windows each show 45 `server_query_failed` events, 48
  `server_warmup_started` events, 48 `server_launch_ready` events, no
  `server_query_pipe_busy`, no `server_query_invalid_response`, and no
  `commit_text` event in the failed-host window.
- A direct installed-pipe `input=ngohaig` request returned `ready=true`,
  `schema_id=luna_pinyin`, and 30 candidates in 140 ms.
- Ten direct installed-pipe `compose-begin` plus `compose-key n` probes all
  succeeded with `compose-begin` taking 60-116 ms and `compose-key` taking
  2-5 ms.

## Diagnosis

The installed server and M07 persistent composition protocol are healthy from a
normal medium-integrity client. The failed-host logs point to the TSF client
operation path: `OnTestKeyDown`/`OnKeyDown` marked letter keys as eaten, then
`compose-begin` or `compose-key` failed and the old installed DLL cleared local
composition state without inserting any fallback text. That explains the user
visible "typing gives no output at all" symptom.

The source fix added after this report keeps eaten consistency, but replaces the
silent drop with a TSF raw-text fallback:

- First-letter `compose-begin` failure inserts the raw key.
- Mid-composition `compose-key` failure clears inline preedit and inserts
  `buffer_ + key`.
- Generic `CallNamedPipeW` failures now log `server_query_call_failed` with a
  structural `error_code=` field so the next live capture can identify the host
  failure reason.

This fix has passed focused contracts and a scratch TSF build, but is not yet
installed into the live TSF DLL at the time of this note.

## Holder State

Current non-elevated holder inspection found `Codex`, `conhost`, `explorer`, and
`Telegram` holding `YuneWindowsTSF.dll`. The dev reload tool must not force-close
non-dev holders; the fallback build needs another holder-free swap before live
retest.
