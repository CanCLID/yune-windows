param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
$CommitTextMatch = [regex]::Match(
    $Source,
    '(?s)bool CommitText\(ITfContext\* context, const std::wstring& text\) \{(?<body>.*?)\r?\n    \}\r?\n\r?\n    bool ShowCandidates')
if (-not $CommitTextMatch.Success) {
    throw "could not locate TextService::CommitText body"
}

$Body = $CommitTextMatch.Groups["body"].Value
$SessionDeclarationIndex = $Body.IndexOf("InsertTextEditSession* session = nullptr;", [System.StringComparison]::Ordinal)
if ($SessionDeclarationIndex -lt 0) {
    throw "CommitText must declare a nullable edit-session pointer before guarded construction."
}

$ConstructionGuardMatch = [regex]::Match(
    $Body,
    'try \{\s+session =\s+new \(std::nothrow\) InsertTextEditSession\(context, text\);\s+\} catch \(\.\.\.\) \{\s+WriteStructuralEvent\("commit_text_failed",\s+static_cast<int>\(text\.size\(\)\)\);\s+return false;\s+\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $ConstructionGuardMatch.Success) {
    throw "CommitText must catch edit-session construction exceptions, log commit_text_failed, and return false."
}

$RequestIndex = $Body.IndexOf("context->RequestEditSession", [System.StringComparison]::Ordinal)
if ($RequestIndex -lt 0) {
    throw "CommitText must still request an edit session after successful construction."
}

if ($ConstructionGuardMatch.Index -gt $RequestIndex) {
    throw "CommitText must handle edit-session construction exceptions before RequestEditSession."
}

$NullGuardMatch = [regex]::Match(
    $Body,
    'if \(!session\) \{\s+WriteStructuralEvent\("commit_text_failed",\s+static_cast<int>\(text\.size\(\)\)\);\s+return false;\s+\}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $NullGuardMatch.Success) {
    throw "CommitText must still log commit_text_failed when non-throwing allocation returns null."
}

if ($NullGuardMatch.Index -gt $RequestIndex) {
    throw "CommitText must handle null edit-session allocation before RequestEditSession."
}

Write-Host "TSF edit-session construction exceptions are converted to structural commit failure evidence."
