param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-webview2-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

$Collector = Join-Path $RepoRoot "tools\collect-webview2-feasibility.ps1"
if (-not (Test-Path -LiteralPath $Collector)) {
    throw "missing WebView2 feasibility collector: $Collector"
}

$JsonPath = Join-Path $OutputDir "webview2-feasibility.json"
& $Collector -OutputPath $JsonPath
if (-not (Test-Path -LiteralPath $JsonPath)) {
    throw "WebView2 feasibility collector did not create $JsonPath"
}

$Result = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
if ($Result.registry_collected -ne $false) {
    throw "WebView2 feasibility must not collect registry state"
}
if ($Result.inline_candidate_window_uses_webview2 -ne $false) {
    throw "inline candidate window must not use WebView2"
}
if (@("webview2-settings", "native-settings", "defer-settings") -notcontains $Result.decision) {
    throw "unexpected settings decision: $($Result.decision)"
}
foreach ($Field in @("runtime_availability", "installer_size", "high_dpi", "theme_font", "accessibility", "host_bridge_security", "diagnostics_export")) {
    if (-not $Result.PSObject.Properties.Name.Contains($Field)) {
        throw "missing WebView2 feasibility field: $Field"
    }
}

$Doc = Join-Path $RepoRoot "docs\evidence\p2-win01-settings\webview2-spike.md"
if (-not (Test-Path -LiteralPath $Doc)) {
    $Roadmap = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\roadmap.md")
    if ($Roadmap -notmatch "Rich settings UI until typing evidence is refreshed") {
        throw "missing WebView2 spike evidence doc and roadmap does not mark settings evidence as deferred"
    }
    Write-Host "WebView2 spike evidence is omitted from the public baseline; post-rename evidence is pending."
    return
}
$DocText = Get-Content -Raw -LiteralPath $Doc
foreach ($Phrase in @(
    "Decision:",
    "runtime availability",
    "installer size",
    "high-DPI",
    "theme/font",
    "accessibility",
    "host bridge security",
    "diagnostics export"
)) {
    if ($DocText -notmatch [regex]::Escape($Phrase)) {
        throw "WebView2 spike doc is missing '$Phrase'"
    }
}

Write-Host "WebView2 feasibility smoke passed: decision=$($Result.decision), runtime_available=$($Result.runtime_availability.available)"
