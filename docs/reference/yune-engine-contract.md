# Yune Engine Contract

Yune Windows consumes Yune as a packaged engine. This repo does not own Yune
core behavior.

## Package Shape

The expected Windows package comes from the Yune repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-yune-windows.ps1
```

Expected package root:

```text
target\yune-windows-native\x86_64-pc-windows-msvc\dist
```

Expected package contents include:

- `rime.dll`
- import library for `rime.dll`
- upstream-shaped `rime_api.h`
- `rime_yune_windows_profile_api.h`
- schema assets for the Yune Windows profile
- support files required by the Yune package script

## ABI Surfaces

Use:

- `rime_get_api()` for the upstream-shaped default ABI.
- `rime_get_yune_windows_profile_api()` for Yune Windows profile behavior.

Do not require new fields in the default `RimeApi`. If Windows product work
needs a new engine surface, first write a named Yune API/profile proposal with
tests in the Yune repo.

## Minimum Host Smoke

A minimal Windows host must prove this lifecycle before TSF UI work depends on
it:

```text
load rime.dll
resolve rime_get_api
resolve rime_get_yune_windows_profile_api
setup
initialize
deploy
create session
select schema jyut6ping3
process ngohaig
read status
read context
free context/status
destroy session
cleanup/finalize
```

Expected evidence:

- `status.schema_id=jyut6ping3`
- candidate/context data for `ngohaig`
- no dependency on librime runtime fallback
- no typed-content logs when sensitive-context mode is enabled

## Sensitive Context

When TSF reports password, secure, or sensitive input:

- do not write typed-content logs;
- suppress learning;
- suppress AI staging;
- keep diagnostic logs structural, such as event names and error codes.

## Engine/Product Claim Split

Yune engine performance work lives in the Yune repo. Windows product readiness
must be proven with Windows evidence: installed TSF activation, real text
fields, candidate UI, installer, uninstall, cleanup, and diagnostics.
