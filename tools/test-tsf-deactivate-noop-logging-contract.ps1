param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
if (-not (Test-Path -LiteralPath $TsfSource)) {
    throw "missing TSF source: $TsfSource"
}

$Source = Get-Content -Raw -LiteralPath $TsfSource
$DeactivateMatch = [regex]::Match(
    $Source,
    '(?s)STDMETHODIMP Deactivate\(\) override \{(?<body>.*?)\r?\n    STDMETHODIMP OnSetFocus\(BOOL focused\) override \{')
if (-not $DeactivateMatch.Success) {
    throw "could not locate TSF Deactivate body"
}

$DeactivateBody = $DeactivateMatch.Groups["body"].Value

$WasActiveMatch = [regex]::Match(
    $DeactivateBody,
    'const bool was_active =(?<expr>.*?);',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $WasActiveMatch.Success) {
    throw "Deactivate must compute whether any active TSF state exists before logging profile_deactivate."
}

$WasActiveExpr = $WasActiveMatch.Groups["expr"].Value
foreach ($RequiredState in @(
        'thread_mgr_',
        'client_id_ != TF_CLIENTID_NULL',
        '!buffer_.empty()',
        '!candidate_.empty()',
        '!last_candidates_.empty()'
    )) {
    if ($WasActiveExpr -notmatch [regex]::Escape($RequiredState)) {
        throw "Deactivate was_active guard must include $RequiredState."
    }
}

$ProfileLogIndex = $DeactivateBody.IndexOf('WriteStructuralEvent("profile_deactivate"', [System.StringComparison]::Ordinal)
if ($ProfileLogIndex -lt 0) {
    throw "Deactivate must still log profile_deactivate when real active state existed."
}

if ($WasActiveMatch.Index -gt $ProfileLogIndex) {
    throw "Deactivate must compute was_active before writing profile_deactivate."
}

if ($DeactivateBody -notmatch '(?s)if \(was_active\) \{\s+WriteStructuralEvent\("profile_deactivate",\s+static_cast<int>\(buffer_\.size\(\)\),\s+static_cast<int>\(last_candidates_\.size\(\)\)\);\s+\}') {
    throw "Deactivate must guard profile_deactivate logging behind was_active so never-activated probes do not create lifecycle evidence."
}

Write-Host "TSF Deactivate suppresses profile_deactivate logs for never-active services."
