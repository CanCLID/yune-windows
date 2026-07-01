param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSourcePath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSourcePath)) {
    throw "missing TSF source: $TsfSourcePath"
}

$Source = Get-Content -Raw -LiteralPath $TsfSourcePath
$Start = $Source.IndexOf("ServerResponse QueryServer(")
if ($Start -lt 0) {
    throw "TSF source is missing QueryServer"
}
$End = $Source.IndexOf("class InsertTextEditSession", $Start)
if ($End -le $Start) {
    throw "TSF source QueryServer boundary could not be found"
}
$QueryServer = $Source.Substring($Start, $End - $Start)

foreach ($Required in @(
        'DWORD mode = PIPE_READMODE_MESSAGE;',
        'SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)',
        'CloseHandle(pipe);',
        'return ServerQueryFailure(input);'
    )) {
    if ($QueryServer -notmatch [regex]::Escape($Required)) {
        throw "TSF QueryServer is missing named-pipe message-mode guard pattern: $Required"
    }
}

$ModeIndex = $QueryServer.IndexOf("DWORD mode = PIPE_READMODE_MESSAGE;", [System.StringComparison]::Ordinal)
$SetModeIndex = $QueryServer.IndexOf("SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)", [System.StringComparison]::Ordinal)
$WriteIndex = $QueryServer.IndexOf("write_pipe(pipe, request, written)", [System.StringComparison]::Ordinal)
$SuccessIndex = $QueryServer.IndexOf("result.ok = true;", [System.StringComparison]::Ordinal)
foreach ($Pair in @(
        @("message-mode declaration", $ModeIndex),
        @("SetNamedPipeHandleState call", $SetModeIndex),
        @("request write", $WriteIndex),
        @("success marker", $SuccessIndex)
    )) {
    if ([int]$Pair[1] -lt 0) {
        throw "TSF QueryServer could not locate $($Pair[0]) for ordering check."
    }
}

if ($ModeIndex -gt $SetModeIndex -or $SetModeIndex -gt $WriteIndex) {
    throw "TSF QueryServer must configure pipe read mode before writing a request."
}

$FailureGuardPattern = @'
if \(!SetNamedPipeHandleState\(pipe, &mode, nullptr, nullptr\)\) \{
\s+CloseHandle\(pipe\);
\s+WriteStructuralEvent\("server_query_connect_failed"\);
\s+return ServerQueryFailure\(input\);
\s+\}
'@

if ($QueryServer -notmatch $FailureGuardPattern) {
    throw "TSF QueryServer must close the pipe and return structural failure if message-mode setup fails."
}

$FailureGuardIndex = [regex]::Match($QueryServer, $FailureGuardPattern).Index
if ($FailureGuardIndex -gt $WriteIndex -or $FailureGuardIndex -gt $SuccessIndex) {
    throw "TSF QueryServer checks pipe message-mode setup too late."
}

Write-Host "TSF shared-server client rejects pipe message-mode setup failures."
