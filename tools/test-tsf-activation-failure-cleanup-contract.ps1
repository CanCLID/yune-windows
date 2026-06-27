param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
$ActivateMatch = [regex]::Match(
    $Source,
    '(?s)STDMETHODIMP ActivateEx\(ITfThreadMgr\* thread_mgr, TfClientId client_id,\s*DWORD\) override \{(?<body>.*?)\r?\n    STDMETHODIMP Deactivate\(\) override \{')
if (-not $ActivateMatch.Success) {
    throw "could not locate TSF ActivateEx body"
}

$ActivateBody = $ActivateMatch.Groups["body"].Value

if ($ActivateBody -notmatch 'if \(thread_mgr_\) \{\s+Deactivate\(\);\s+\}') {
    throw "ActivateEx must deactivate any prior thread-manager/key-sink state before accepting a new activation."
}

if ($ActivateBody -notmatch 'if \(!thread_mgr\) \{\s+return E_INVALIDARG;\s+\}') {
    throw "ActivateEx must reject a null thread manager before storing active TSF state."
}

$AssignIndex = $ActivateBody.IndexOf("thread_mgr_ = thread_mgr;", [System.StringComparison]::Ordinal)
$AddRefIndex = $ActivateBody.IndexOf("thread_mgr_->AddRef();", [System.StringComparison]::Ordinal)
$ClientIdIndex = $ActivateBody.IndexOf("client_id_ = client_id;", [System.StringComparison]::Ordinal)
$AdviseIndex = $ActivateBody.IndexOf("AdviseKeyEventSink", [System.StringComparison]::Ordinal)
$FailureReturnIndex = $ActivateBody.IndexOf("if (FAILED(hr))", [System.StringComparison]::Ordinal)

foreach ($Pair in @(
        @("thread manager assignment", $AssignIndex),
        @("thread manager AddRef", $AddRefIndex),
        @("client id assignment", $ClientIdIndex),
        @("key-sink advice", $AdviseIndex),
        @("advice failure return", $FailureReturnIndex)
    )) {
    if ([int]$Pair[1] -lt 0) {
        throw "ActivateEx is missing $($Pair[0])"
    }
}

if (($AssignIndex -lt $AdviseIndex) -or
    ($AddRefIndex -lt $AdviseIndex) -or
    ($ClientIdIndex -lt $AdviseIndex)) {
    throw "ActivateEx must not publish thread_mgr_, AddRef it, or store client_id_ before AdviseKeyEventSink succeeds."
}

if (($AssignIndex -lt $FailureReturnIndex) -or
    ($AddRefIndex -lt $FailureReturnIndex) -or
    ($ClientIdIndex -lt $FailureReturnIndex)) {
    throw "ActivateEx must return failed AdviseKeyEventSink HRESULTs before storing active TSF state."
}

Write-Host "TSF activation stores active thread-manager state only after key-sink registration succeeds."
