# P2-WIN01 Signing Decision

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Decision: defer-production-signing

Unsigned local dogfood artifacts are allowed only for approved P2-WIN01
evidence collection on this machine.

Production or public distribution remains blocked until a code-signing
certificate and release signing flow are selected, documented, and verified.

Installer result must record exact artifact paths for the TSF DLL, server,
profile tool, packaged Yune runtime, and diagnostics outputs before any
dogfood-ready claim.

This signing decision does not close P2-WIN01.
