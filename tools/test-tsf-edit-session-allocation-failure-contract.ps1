param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
if ($Source -notmatch '#include <new>') {
    throw "TSF edit-session allocation guard must include <new> for std::nothrow."
}

$CommitTextMatch = [regex]::Match(
    $Source,
    '(?s)bool CommitText\(ITfContext\* context, const std::wstring& text\) \{(?<body>.*?)\r?\n    \}\r?\n\r?\n    bool ShowCandidates')
if (-not $CommitTextMatch.Success) {
    throw "could not locate TextService::CommitText body"
}

$Body = $CommitTextMatch.Groups["body"].Value
$AllocationMatch = [regex]::Match(
    $Body,
    'session =\s+new \(std::nothrow\) InsertTextEditSession\(context, text\);',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $AllocationMatch.Success) {
    throw "CommitText must allocate InsertTextEditSession with new (std::nothrow)."
}

$BeforeAllocation = $Body.Substring(0, $AllocationMatch.Index)
if ($BeforeAllocation -notmatch 'if \(!context \|\| client_id_ == TF_CLIENTID_NULL\) \{\s+WriteStructuralEvent\("commit_text_failed",\s+static_cast<int>\(text\.size\(\)\)\);\s+return false;\s+\}') {
    throw "CommitText must reject missing context/client state before allocating an edit session."
}
if ($BeforeAllocation -notmatch 'InsertTextEditSession\* session = nullptr;') {
    throw "CommitText must start with a nullable edit-session pointer before guarded allocation."
}

$AfterAllocation = $Body.Substring($AllocationMatch.Index + $AllocationMatch.Length)
$AllocationGuardMatch = [regex]::Match(
    $AfterAllocation,
    'if \(!session\) \{\s+WriteStructuralEvent\("commit_text_failed",\s+static_cast<int>\(text\.size\(\)\)\);\s+return false;\s+\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $AllocationGuardMatch.Success) {
    throw "CommitText must log commit_text_failed and return false when edit-session allocation fails."
}

$RequestIndex = $AfterAllocation.IndexOf("context->RequestEditSession", [System.StringComparison]::Ordinal)
if ($RequestIndex -lt 0) {
    throw "CommitText must still request an edit session after successful allocation."
}
if ($AllocationGuardMatch.Index -gt $RequestIndex) {
    throw "CommitText must handle edit-session allocation failure before RequestEditSession."
}

$ReleaseIndex = $AfterAllocation.IndexOf("session->Release();", [System.StringComparison]::Ordinal)
if ($ReleaseIndex -lt 0 -or $ReleaseIndex -lt $RequestIndex) {
    throw "CommitText must release the edit-session object after RequestEditSession."
}

Write-Host "TSF edit-session allocation failures are logged structurally before RequestEditSession."
