param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
if ($Source -notmatch '#include <new>') {
    throw "TSF COM entry points must include <new> for std::nothrow allocation guards."
}

$CreateInstanceMatch = [regex]::Match(
    $Source,
    '(?s)STDMETHODIMP CreateInstance\(IUnknown\* outer, REFIID iid, void\*\* object\) override \{(?<body>.*?)\r?\n    \}')
if (-not $CreateInstanceMatch.Success) {
    throw "could not locate TSF class factory CreateInstance body"
}

$CreateBody = $CreateInstanceMatch.Groups["body"].Value
$ServiceAllocation = "TextService* service = new (std::nothrow) TextService();"
$ServiceAllocationIndex = $CreateBody.IndexOf($ServiceAllocation, [System.StringComparison]::Ordinal)
if ($ServiceAllocationIndex -lt 0) {
    throw "CreateInstance must allocate TextService with new (std::nothrow)."
}

$BeforeServiceAllocation = $CreateBody.Substring(0, $ServiceAllocationIndex)
if ($BeforeServiceAllocation -notmatch 'if \(!object\) \{\s+return E_INVALIDARG;\s+\}') {
    throw "CreateInstance must reject a null output pointer before allocating TextService."
}

if ($BeforeServiceAllocation -notmatch 'if \(outer\) \{\s+return CLASS_E_NOAGGREGATION;\s+\}') {
    throw "CreateInstance must reject aggregation before allocating TextService."
}

$AfterServiceAllocation = $CreateBody.Substring($ServiceAllocationIndex + $ServiceAllocation.Length)
if ($AfterServiceAllocation -notmatch 'if \(!service\) \{\s+return E_OUTOFMEMORY;\s+\}') {
    throw "CreateInstance must return E_OUTOFMEMORY when TextService allocation fails."
}

$QueryIndex = $AfterServiceAllocation.IndexOf("service->QueryInterface", [System.StringComparison]::Ordinal)
$OutOfMemoryIndex = $AfterServiceAllocation.IndexOf("return E_OUTOFMEMORY;", [System.StringComparison]::Ordinal)
if ($QueryIndex -lt 0 -or $OutOfMemoryIndex -lt 0 -or $OutOfMemoryIndex -gt $QueryIndex) {
    throw "CreateInstance must handle TextService allocation failure before QueryInterface."
}

$DllGetClassObjectMatch = [regex]::Match(
    $Source,
    '(?s)extern "C" HRESULT STDAPICALLTYPE DllGetClassObject\(REFCLSID clsid, REFIID iid,\s+void\*\* object\) \{(?<body>.*?)\r?\n\}\r?\n\r?\nextern "C" HRESULT STDAPICALLTYPE DllCanUnloadNow\(\)')
if (-not $DllGetClassObjectMatch.Success) {
    throw "could not locate DllGetClassObject body"
}

$DllBody = $DllGetClassObjectMatch.Groups["body"].Value
$FactoryAllocation = "ClassFactory* factory = new (std::nothrow) ClassFactory();"
$FactoryAllocationIndex = $DllBody.IndexOf($FactoryAllocation, [System.StringComparison]::Ordinal)
if ($FactoryAllocationIndex -lt 0) {
    throw "DllGetClassObject must allocate ClassFactory with new (std::nothrow)."
}

$BeforeFactoryAllocation = $DllBody.Substring(0, $FactoryAllocationIndex)
if ($BeforeFactoryAllocation -notmatch 'if \(!object\) \{\s+return E_INVALIDARG;\s+\}') {
    throw "DllGetClassObject must reject a null output pointer before allocating ClassFactory."
}

if ($BeforeFactoryAllocation -notmatch '\*object = nullptr;') {
    throw "DllGetClassObject must clear the output pointer before allocation or unsupported CLSID failures."
}

$UnsupportedIndex = $BeforeFactoryAllocation.IndexOf("return CLASS_E_CLASSNOTAVAILABLE;", [System.StringComparison]::Ordinal)
if ($UnsupportedIndex -lt 0) {
    throw "DllGetClassObject must reject unsupported CLSIDs before allocating ClassFactory."
}

$AfterFactoryAllocation = $DllBody.Substring($FactoryAllocationIndex + $FactoryAllocation.Length)
if ($AfterFactoryAllocation -notmatch 'if \(!factory\) \{\s+return E_OUTOFMEMORY;\s+\}') {
    throw "DllGetClassObject must return E_OUTOFMEMORY when ClassFactory allocation fails."
}

$FactoryQueryIndex = $AfterFactoryAllocation.IndexOf("factory->QueryInterface", [System.StringComparison]::Ordinal)
$FactoryOutOfMemoryIndex = $AfterFactoryAllocation.IndexOf("return E_OUTOFMEMORY;", [System.StringComparison]::Ordinal)
if ($FactoryQueryIndex -lt 0 -or $FactoryOutOfMemoryIndex -lt 0 -or $FactoryOutOfMemoryIndex -gt $FactoryQueryIndex) {
    throw "DllGetClassObject must handle ClassFactory allocation failure before QueryInterface."
}

Write-Host "TSF COM activation allocations return E_OUTOFMEMORY instead of throwing across COM entry points."
