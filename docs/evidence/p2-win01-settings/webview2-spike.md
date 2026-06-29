# P2-WIN01 WebView2 Feasibility

Date: 2026-06-27T14:15:00.2685419-07:00

Machine state changed: false

Decision: `defer-settings`

Status: settings UI is deferred until typing, diagnostics export, uninstall,
and cleanup evidence are proven.

## runtime availability

WebView2 runtime was available under:

- `C:\Program Files (x86)\Microsoft\EdgeWebView\Application`

Detected runtime versions:

- `149.0.4022.80`
- `149.0.4022.98`

Detected Chromium browsers:

- `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`
- `C:\Program Files\Google\Chrome\Application\chrome.exe`

## installer size

Runtime footprint observed by the collector: `1677.3 MB`.

Do not bundle WebView2 for P2-WIN01. A settings UI would add installer and
host-bridge scope before the IME path is proven end to end.

## high-DPI

The native candidate window owns first inline high-DPI work. WebView2 high-DPI
behavior is deferred with settings UI.

## theme/font

The native candidate renderer uses system font and colors for inline UI.
Settings theme and font integration is deferred.

## accessibility

No settings controls ship in P2-WIN01, so no placeholder accessibility surface
is exposed.

## host bridge security

No WebView2 host bridge is introduced in P2-WIN01. This avoids a new trust
boundary before the IME is proven.

## diagnostics export

Diagnostics export remains a product requirement and is handled by
`tools\export-yune-windows-diagnostics.ps1`, not by a WebView2 settings UI.
