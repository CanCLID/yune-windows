# P2-WIN01 First Smoke Target

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: Notepad remains the first live app target; Chromium follows after the
Notepad path proves activation, candidate display, and candidate commit.

## Target

- Input: `ngohaig`
- Schema: `jyut6ping3`
- Expected behavior: Yune candidate display appears in the native candidate
  window and the committed text is not a raw echo.
- First app: Notepad through the registered Yune Windows TSF profile.
- Second app: one Chromium-based text field with exact structural event
  evidence.

## Current Evidence

The packaged host and shared-server IPC smokes prove the Yune runtime can
produce candidates for `ngohaig` without elevated registration. They do not
prove foreground TSF input delivery. The live Notepad and Chromium smokes
remain pending explicit approval.
