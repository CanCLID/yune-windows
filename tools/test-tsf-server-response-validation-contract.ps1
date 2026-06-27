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
        'JsonBoolTrueValue\(json, "ready"\)',
        'JsonStringValue\(json, "schema_id"\)\.empty\(\)',
        'JsonHasArrayValue\(json, "candidates"\)',
        'return ServerQueryFailure\(input\);'
    )) {
    if ($QueryServer -notmatch $Required -and $Source -notmatch $Required) {
        throw "TSF QueryServer must validate shared-server response JSON before accepting success: $Required"
    }
}

$JsonCreatedIndex = $QueryServer.IndexOf("const std::string json(response, read);")
$ReadyCheckIndex = $QueryServer.IndexOf('JsonBoolTrueValue(json, "ready")')
$SchemaCheckIndex = $QueryServer.IndexOf('JsonStringValue(json, "schema_id").empty()')
$CandidateArrayCheckIndex = $QueryServer.IndexOf('JsonHasArrayValue(json, "candidates")')
$SuccessIndex = $QueryServer.IndexOf("result.ok = true;")
if ($JsonCreatedIndex -lt 0 -or $ReadyCheckIndex -lt 0 -or
    $SchemaCheckIndex -lt 0 -or $CandidateArrayCheckIndex -lt 0 -or
    $SuccessIndex -lt 0) {
    throw "TSF QueryServer response-validation ordering could not be checked"
}

foreach ($Index in @($ReadyCheckIndex, $SchemaCheckIndex, $CandidateArrayCheckIndex)) {
    if ($Index -lt $JsonCreatedIndex) {
        throw "TSF QueryServer must validate the actual shared-server JSON response."
    }
    if ($Index -gt $SuccessIndex) {
        throw "TSF QueryServer validates malformed shared-server JSON after marking success."
    }
}

Write-Host "TSF shared-server client rejects malformed response JSON before success."
