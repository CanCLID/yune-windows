param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ($OutputPath -eq "") {
    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $OutputPath = Join-Path $RepoRoot "docs\evidence\p2-win01-settings\webview2-feasibility.json"
}

function Candidate-Path([string]$Path) {
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return $null
}

function Measure-DirectoryBytes([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $Bytes = 0
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { $Bytes += $_.Length }
    return $Bytes
}

$RuntimeRoots = @(
    (Candidate-Path (Join-Path ${env:ProgramFiles(x86)} "Microsoft\EdgeWebView\Application")),
    (Candidate-Path (Join-Path $env:ProgramFiles "Microsoft\EdgeWebView\Application"))
) | Where-Object { $_ } | Select-Object -Unique

$BrowserPaths = @(
    (Candidate-Path (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")),
    (Candidate-Path (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")),
    (Candidate-Path (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe")),
    (Candidate-Path (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"))
) | Where-Object { $_ } | Select-Object -Unique

$RuntimeVersions = @()
foreach ($Root in $RuntimeRoots) {
    $RuntimeVersions += Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^\d+\." } |
        Select-Object -ExpandProperty Name
}

$RuntimeBytes = $null
if ($RuntimeRoots.Count -gt 0) {
    $RuntimeBytes = 0
    foreach ($Root in $RuntimeRoots) {
        $Size = Measure-DirectoryBytes $Root
        if ($null -ne $Size) {
            $RuntimeBytes += $Size
        }
    }
}

$Decision = "defer-settings"
$Reason = "P2-WIN01 only needs typing, diagnostics export, and cleanup evidence; a settings UI would add installer and host-bridge scope before the IME is proven end to end."

$Result = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    registry_collected = $false
    decision = $Decision
    decision_reason = $Reason
    inline_candidate_window_uses_webview2 = $false
    runtime_availability = [ordered]@{
        available = $RuntimeRoots.Count -gt 0
        runtime_roots = @($RuntimeRoots)
        runtime_versions = @($RuntimeVersions | Select-Object -Unique)
        chromium_browsers = @($BrowserPaths)
    }
    installer_size = [ordered]@{
        runtime_bytes = $RuntimeBytes
        runtime_megabytes = if ($null -ne $RuntimeBytes) { [Math]::Round($RuntimeBytes / 1MB, 1) } else { $null }
        packaging_position = "Do not bundle WebView2 for P2-WIN01; defer settings UI until typing, install, diagnostics, and cleanup are proven."
    }
    high_dpi = [ordered]@{
        position = "Native candidate window handles first inline high-DPI work; WebView2 high-DPI behavior is deferred with settings UI."
    }
    theme_font = [ordered]@{
        position = "Native candidate renderer uses system font and colors for inline UI; settings UI theme/font integration is deferred."
    }
    accessibility = [ordered]@{
        position = "No settings controls ship in P2-WIN01, so no placeholder accessibility surface is exposed."
    }
    host_bridge_security = [ordered]@{
        position = "No WebView2 host bridge is introduced in P2-WIN01; this avoids a new trust boundary before the IME is proven."
    }
    diagnostics_export = [ordered]@{
        implemented = Test-Path -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "tools\export-yune-windows-diagnostics.ps1")
        script = "tools\\export-yune-windows-diagnostics.ps1"
    }
}

$OutputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$Result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
