param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$WatchScript = Join-Path $RepoRoot "tools\dev\dev-watch.ps1"

if (-not (Test-Path -LiteralPath $WatchScript -PathType Leaf)) {
    throw "missing dev-watch script: tools\dev\dev-watch.ps1"
}

$Source = Get-Content -Raw -LiteralPath $WatchScript

foreach ($Required in @(
        'args\s*=\s*@\("-YuneRoot",\s*\$YuneRoot,\s*"-RefreshSchema"\)',
        'args\s*=\s*@\("-YuneRoot",\s*\$YuneRoot\)',
        'Format-YuneWindowsDevWatchCommand',
        '&\s+\$Route\.script\s+@\(\$Route\.args\)'
    )) {
    if ($Source -notmatch $Required) {
        throw "dev-watch.ps1 is missing custom YuneRoot forwarding pattern: $Required"
    }
}

$TempRoot = Join-Path $env:TEMP ("yune-windows\dev-watch-yuneroot-contract-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N").Substring(0, 8))
$SchemaRoot = Join-Path $TempRoot "apps\yune-web\public\schema"
New-Item -Path $SchemaRoot -ItemType Directory -Force | Out-Null
$ResolvedTempRoot = (Resolve-Path $TempRoot).Path
$SchemaPath = Join-Path $SchemaRoot "custom.schema.yaml"
Set-Content -LiteralPath $SchemaPath -Encoding UTF8 -Value "schema_id: custom"

$ServerOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $WatchScript -YuneRoot $ResolvedTempRoot -SimulatePath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")
$TsfOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $WatchScript -YuneRoot $ResolvedTempRoot -SimulatePath (Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp")
$SchemaOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $WatchScript -YuneRoot $ResolvedTempRoot -SimulatePath $SchemaPath

foreach ($Entry in @(
        @{ Name = "server"; Output = $ServerOutput; Pattern = [regex]::Escape("-YuneRoot `"$ResolvedTempRoot`"") },
        @{ Name = "tsf"; Output = $TsfOutput; Pattern = [regex]::Escape("-YuneRoot `"$ResolvedTempRoot`"") },
        @{ Name = "schema"; Output = $SchemaOutput; Pattern = [regex]::Escape("-YuneRoot `"$ResolvedTempRoot`"") + '.*-RefreshSchema' }
    )) {
    $Text = $Entry.Output -join "`n"
    if ($Text -notmatch $Entry.Pattern) {
        throw "dev-watch $($Entry.Name) dry-run did not print custom YuneRoot forwarding. Output: $Text"
    }
    if ($Text -notmatch 'dry_run: true') {
        throw "dev-watch $($Entry.Name) dry-run did not stay dry-run. Output: $Text"
    }
}

Write-Host "dev-watch forwards custom YuneRoot in dry-run output and AutoRun route args."
