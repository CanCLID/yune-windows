param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$CreateInstancePattern = @'
STDMETHODIMP CreateInstance\(IUnknown\* outer, REFIID iid, void\*\* object\) override \{(?<prefix>[\s\S]*?)TextService\* service = new \(std::nothrow\) TextService\(\);
'@

$Match = [regex]::Match($Source, $CreateInstancePattern)
if (-not $Match.Success) {
    throw "missing TSF class factory CreateInstance allocation shape"
}

$Prefix = $Match.Groups["prefix"].Value
$NullGuardPattern = "if \(!object\) \{\s+return E_INVALIDARG;\s+\}"
$GuardMatch = [regex]::Match($Prefix, $NullGuardPattern)
if (-not $GuardMatch.Success) {
    throw "TSF class factory must reject a null output pointer before constructing TextService."
}

$BeforeGuard = $Prefix.Substring(0, $GuardMatch.Index)
if ($BeforeGuard -match "TextService|WriteStructuralEvent|DllAddRef|Deactivate") {
    throw "TSF class factory must reject null output pointers before service lifetime side effects."
}

Write-Host "TSF class factory rejects null output pointers before constructing TextService."
