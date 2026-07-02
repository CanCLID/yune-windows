param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TsfSource = Join-Path $RepoRoot "src\tsf\yune_windows_tsf.cpp"
$Source = Get-Content -Raw -LiteralPath $TsfSource

foreach ($Required in @(
        'CommitRawFallback(context, key_text)',
        'CommitRawFallback(context, buffer_ + key_text)',
        'WriteStructuralEvent("server_fallback_raw_commit"',
        'ClearCompositionState(false);',
        'return CommitText(context, text);',
        'WriteStructuralEvent("server_query_call_failed", -1, -1, last_error);'
    )) {
    if ($Source -notlike "*$Required*") {
        throw "TSF server-unavailable fallback is missing source marker: $Required"
    }
}

$LetterPathPattern = @'
std::wstring key_text\(1, LowerAscii\(key\)\);
\s+if \(!EnsureComposeSession\(context\)\) \{
\s+\(void\)CommitRawFallback\(context, key_text\);
\s+return S_OK;
\s+\}
(?s:.*?)
\s+if \(!response\.ok\) \{
\s+\(void\)CommitRawFallback\(context, buffer_ \+ key_text\);
\s+return S_OK;
\s+\}
'@

if ($Source -notmatch $LetterPathPattern) {
    throw "TSF letter-key failures must keep the key eaten but explicitly commit raw fallback text."
}

Write-Host "TSF server-unavailable key path commits raw fallback text instead of silently dropping eaten keys."
