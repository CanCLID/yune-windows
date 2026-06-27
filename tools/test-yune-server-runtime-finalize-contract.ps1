param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ServerSourcePath = Join-Path $RepoRoot "src\server\yune_windows_server.cpp"
if (-not (Test-Path -LiteralPath $ServerSourcePath)) {
    throw "missing shared server source: $ServerSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $ServerSourcePath
$DestructorMatch = [regex]::Match($Source, '(?s)~YuneRuntime\(\)\s*\{(?<body>.*?)\n\s*if \(library_\)')
if (-not $DestructorMatch.Success) {
    throw "shared server source is missing YuneRuntime destructor"
}

$Destructor = $DestructorMatch.Groups["body"].Value
foreach ($Required in @(
        'cleanup_all_sessions',
        'api_->finalize\(\);'
    )) {
    if ($Destructor -notmatch $Required) {
        throw "shared server runtime finalizer is missing lifecycle cleanup pattern: $Required"
    }
}

if ($Destructor.IndexOf('cleanup_all_sessions') -gt $Destructor.IndexOf('api_->finalize();')) {
    throw "shared server must call cleanup_all_sessions before finalize"
}

Write-Host "Shared server finalizer cleans up Yune sessions before finalize when the API is available."
