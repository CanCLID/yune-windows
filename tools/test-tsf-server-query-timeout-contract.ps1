param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSourcePath = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$PlanPath = Join-Path $RepoRoot "docs\plans\active\p2-win01-plan-windows-product.md"
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
        'kServerQueryTimeoutMs',
        'FILE_FLAG_OVERLAPPED',
        'CreateEventW',
        'ERROR_IO_PENDING',
        'WaitForSingleObject',
        'CancelIo\(pipe\)',
        'GetOverlappedResult',
        'return ServerQueryFailure\(input\);'
    )) {
    if ($QueryServer -notmatch $Required -and $Source -notmatch $Required) {
        throw "TSF QueryServer is missing bounded pipe I/O pattern: $Required"
    }
}

foreach ($Forbidden in @(
        'CreateFileW\(kPipeName, GENERIC_READ \| GENERIC_WRITE, 0, nullptr,\s*OPEN_EXISTING, 0, nullptr\)',
        'WriteFile\(pipe, request\.data\(\), request_size, &written,\s*nullptr\)',
        'ReadFile\(pipe, response, sizeof\(response\) - 1, &read,\s*nullptr\)'
    )) {
    if ($QueryServer -match $Forbidden) {
        throw "TSF QueryServer still has unbounded synchronous pipe I/O: $Forbidden"
    }
}

$WaitIndex = $QueryServer.IndexOf("WaitForSingleObject")
$FailureIndex = $QueryServer.IndexOf("return ServerQueryFailure(input);")
$SuccessIndex = $QueryServer.IndexOf("result.ok = true;")
if ($WaitIndex -lt 0 -or $FailureIndex -lt 0 -or $SuccessIndex -lt 0) {
    throw "TSF QueryServer timeout guard ordering could not be checked"
}
if ($WaitIndex -gt $SuccessIndex -or $FailureIndex -gt $SuccessIndex) {
    throw "TSF QueryServer must finish bounded I/O checks before marking success"
}

$Plan = Get-Content -Raw -LiteralPath $PlanPath
if ($Plan -notmatch [regex]::Escape("tools\test-tsf-server-query-timeout-contract.ps1")) {
    throw "active plan must mention the TSF server query timeout contract."
}

Write-Host "TSF shared-server client bounds pipe I/O so target apps do not hang on stalled IPC."
