param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
$DllGetClassObjectMatch = [regex]::Match(
    $Source,
    '(?s)extern "C" HRESULT STDAPICALLTYPE DllGetClassObject\(REFCLSID clsid, REFIID iid,\s+void\*\* object\) \{(?<body>.*?)\r?\n\}\r?\n\r?\nextern "C" HRESULT STDAPICALLTYPE DllCanUnloadNow\(\)')
if (-not $DllGetClassObjectMatch.Success) {
    throw "could not locate DllGetClassObject body"
}

$Body = $DllGetClassObjectMatch.Groups["body"].Value
$FactoryIndex = $Body.IndexOf("ClassFactory* factory = new (std::nothrow) ClassFactory();", [System.StringComparison]::Ordinal)
if ($FactoryIndex -lt 0) {
    throw "DllGetClassObject must construct the class factory for supported CLSIDs."
}

$BeforeFactory = $Body.Substring(0, $FactoryIndex)
if ($BeforeFactory -notmatch 'if \(!object\) \{\s+return E_INVALIDARG;\s+\}') {
    throw "DllGetClassObject must reject a null output pointer before constructing the class factory."
}

if ($BeforeFactory -notmatch '\*object = nullptr;') {
    throw "DllGetClassObject must clear the output pointer before returning any failure."
}

$NullGuardIndex = $Body.IndexOf("if (!object)", [System.StringComparison]::Ordinal)
$ClearIndex = $Body.IndexOf("*object = nullptr;", [System.StringComparison]::Ordinal)
$UnsupportedIndex = $Body.IndexOf("return CLASS_E_CLASSNOTAVAILABLE;", [System.StringComparison]::Ordinal)

foreach ($Pair in @(
        @("null output guard", $NullGuardIndex),
        @("output clear", $ClearIndex),
        @("unsupported CLSID return", $UnsupportedIndex)
    )) {
    if ([int]$Pair[1] -lt 0) {
        throw "DllGetClassObject is missing $($Pair[0])."
    }
}

if ($ClearIndex -gt $UnsupportedIndex) {
    throw "DllGetClassObject must clear the output pointer before unsupported CLSID failures."
}

Write-Host "DllGetClassObject rejects null outputs and clears stale outputs before failures."
