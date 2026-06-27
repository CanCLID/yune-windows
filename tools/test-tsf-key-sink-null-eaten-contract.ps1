param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource

$Methods = @(
    @{
        Name = "OnTestKeyDown"
        Pattern = "STDMETHODIMP OnTestKeyDown\(ITfContext\*, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?<prefix>[\s\S]*?)\*eaten"
    },
    @{
        Name = "OnKeyDown"
        Pattern = "STDMETHODIMP OnKeyDown\(ITfContext\* context, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?<prefix>[\s\S]*?)\*eaten"
    },
    @{
        Name = "OnTestKeyUp"
        Pattern = "STDMETHODIMP OnTestKeyUp\(ITfContext\*, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?<prefix>[\s\S]*?)\*eaten"
    },
    @{
        Name = "OnKeyUp"
        Pattern = "STDMETHODIMP OnKeyUp\(ITfContext\*, WPARAM key, LPARAM, BOOL\* eaten\) override \{(?<prefix>[\s\S]*?)\*eaten"
    },
    @{
        Name = "OnPreservedKey"
        Pattern = "STDMETHODIMP OnPreservedKey\(ITfContext\*, REFGUID, BOOL\* eaten\) override \{(?<prefix>[\s\S]*?)\*eaten"
    }
)

$NullGuardPattern = "if \(!eaten\) \{\s+return E_INVALIDARG;\s+\}"
$StateMutationPattern = "WriteStructuralEvent|QueryServer|CommitText|ShowCandidates|buffer_|candidate_|last_candidates_|candidate_window_"

foreach ($Method in $Methods) {
    $Match = [regex]::Match($Source, $Method.Pattern)
    if (-not $Match.Success) {
        throw "missing TSF key sink method shape for $($Method.Name)"
    }

    $Prefix = $Match.Groups["prefix"].Value
    $GuardMatch = [regex]::Match($Prefix, $NullGuardPattern)
    if (-not $GuardMatch.Success) {
        throw "$($Method.Name) must reject a null BOOL* eaten result pointer with E_INVALIDARG before reporting key handling."
    }

    $BeforeGuard = $Prefix.Substring(0, $GuardMatch.Index)
    if ($BeforeGuard -match $StateMutationPattern) {
        throw "$($Method.Name) must reject a null BOOL* eaten result pointer before mutating TSF state or writing structural logs."
    }
}

Write-Host "TSF key sink methods reject null BOOL* eaten before state mutation."
