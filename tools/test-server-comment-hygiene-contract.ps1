param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DevRepl = Join-Path $RepoRoot "tools\dev\dev-repl.ps1"
if (-not (Test-Path -LiteralPath $DevRepl -PathType Leaf)) {
    throw "missing dev REPL: $DevRepl"
}

$Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $DevRepl `
    -YuneRoot $YuneRoot `
    -InputText ngohaig `
    -Once 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "dev-repl failed while checking comment hygiene: $($Output -join "`n")"
}

$Text = $Output -join "`n"
if ($Text -match '(?m)\t\s*(\\f|\\r|[\x00-\x1f])*1,[^,\r\n]+,[a-z]+[1-6][a-z0-9'']*') {
    throw "server candidate comments leaked raw jyut6ping3 CSV data: $Text"
}
if ($Text -notmatch '(?m)^\[1\]\s+.+\tngo5hai6go3\s*$') {
    throw "server candidate comments should expose clean jyutping for ngohaig first candidate. Output: $Text"
}

Write-Host "Server candidate comments expose clean jyutping without raw CSV leakage."
