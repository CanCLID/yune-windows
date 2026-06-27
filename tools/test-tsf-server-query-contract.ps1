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
        'const DWORD request_size = static_cast<DWORD>\(request\.size\(\)\);',
        'WriteFile\(pipe, request\.data\(\), request_size, nullptr, &overlapped\)',
        'written == request_size',
        'read > 0',
        'return ServerQueryFailure\(input\);',
        'result\.ok = true;'
    )) {
    if ($QueryServer -notmatch $Required -and $Source -notmatch $Required) {
        throw "TSF QueryServer is missing guarded named-pipe query pattern: $Required"
    }
}

$ShortWriteIndex = $QueryServer.IndexOf("written == request_size")
$EmptyReadIndex = $QueryServer.IndexOf("read_pipe(pipe, response, sizeof(response) - 1, read)")
$SuccessIndex = $QueryServer.IndexOf("result.ok = true;")
if ($ShortWriteIndex -lt 0 -or $EmptyReadIndex -lt 0 -or $SuccessIndex -lt 0) {
    throw "TSF QueryServer guard ordering could not be checked"
}
if ($ShortWriteIndex -gt $SuccessIndex) {
    throw "TSF QueryServer checks incomplete request writes after marking success"
}
if ($EmptyReadIndex -gt $SuccessIndex) {
    throw "TSF QueryServer checks empty responses after marking success"
}

Write-Host "TSF shared-server client rejects incomplete writes and empty responses."
