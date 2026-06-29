# P2-WIN01 Reference Audit

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Status: no additional legacy reference code was imported for this evidence
refresh.

## Classification

| Area | Classification | Notes |
| --- | --- | --- |
| TSF registration, key sinks, and edit sessions | reference-only | Current source remains in `src\tsf\yune_windows_tsf.cpp`; any further extraction needs focused audit and smoke proof. |
| Server lifecycle and IPC | reference-only | Current source remains in `src\server\yune_windows_server.cpp` and uses the Yune Windows pipe contract. |
| Wire-format helpers | rewrite | The current smoke uses the Yune Windows shared-server JSON response contract instead of adopting legacy wire helpers. |
| Engine adapter patterns | rewrite | Yune is loaded through the packaged Yune ABI and opt-in Yune Windows profile API. |
| Candidate positioning | reference-only | The native candidate-window implementation stays in `src\candidate_window\yune_windows_candidate_window.cpp`; live display evidence is still pending. |
| Installer and registration behavior | reference-only | Installer, registration, unregistration, and cleanup scripts remain approval-gated before any machine-state work. |
| Historical settings UI | delete | No settings UI ships in P2-WIN01. WebView2 remains deferred for settings only. |

## Boundary

Yune remains the only runtime engine. No runtime fallback was added, and no
default `rime_get_api()` ABI widening is required by this repo evidence.
