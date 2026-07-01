param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1"
$Source = Get-Content -Raw -LiteralPath $OrchestratorPath
$ChromiumSmokePath = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$ChromiumSmokeSource = Get-Content -Raw -LiteralPath $ChromiumSmokePath

function Require-OrderedText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Needle,
        [Parameter(Mandatory = $true)]
        [string]$Reason,
        [Parameter(Mandatory = $true)]
        [ref]$PreviousIndex
    )

    $Index = $Source.IndexOf($Needle, $PreviousIndex.Value + 1)
    if ($Index -lt 0) {
        throw "tools\run-m01-live-smoke.ps1 is missing $Reason."
    }
    if ($Index -le $PreviousIndex.Value) {
        throw "tools\run-m01-live-smoke.ps1 records $Reason out of order."
    }
    $PreviousIndex.Value = $Index
}

$PreviousIndex = [ref](-1)
Require-OrderedText '$ResolvedBrowserPath = Find-ChromiumBrowserPath -RequestedPath $BrowserPath' "resolved Chromium browser path before approval evidence" $PreviousIndex
Require-OrderedText 'Assert-ConcreteChromiumBrowserPath' "concrete Chromium browser path gate before approval evidence" $PreviousIndex
Require-OrderedText 'Write-LiveSmokeApprovalEvidence' "approval evidence write" $PreviousIndex
Require-OrderedText '-BrowserPath $ResolvedBrowserPath' "resolved browser path in approval evidence" $PreviousIndex
Require-OrderedText '$LivePreflightCommand = "tools\run-m01-live-smoke.ps1' "live preflight command construction" $PreviousIndex
Require-OrderedText '$LivePreflightCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"' "resolved browser path in live preflight transcript" $PreviousIndex
Require-OrderedText '-BrowserPath $ResolvedBrowserPath' "resolved browser path in live preflight report" $PreviousIndex
Require-OrderedText '$ChromiumCommand += " -BrowserPath $(Format-CommandValue $ResolvedBrowserPath)"' "resolved browser path in Chromium transcript" $PreviousIndex
Require-OrderedText '"-BrowserPath", $ResolvedBrowserPath' "resolved browser path passed to Chromium smoke" $PreviousIndex

if ($Source -match 'if \(\$ResolvedBrowserPath\)\s*\{') {
    throw "tools\run-m01-live-smoke.ps1 still makes resolved browser path evidence optional."
}
if ($Source -match 'if \(\$BrowserPath\)\s*\{\s*\$ChromiumArgs\.BrowserPath = \$BrowserPath') {
    throw "tools\run-m01-live-smoke.ps1 still ties Chromium smoke browser evidence to the raw BrowserPath parameter."
}
if ($ChromiumSmokeSource -match 'if \(\$RequestedPath -and \(Test-Path -LiteralPath \$RequestedPath\)\)') {
    throw "tools\run-chromium-smoke.ps1 still falls back from a missing explicitly requested Chromium browser path."
}
foreach ($ForbiddenChromiumSmokeText in @(
        '$Candidates = @(',
        'No Chromium browser found. Provide -BrowserPath'
    )) {
    if ($ChromiumSmokeSource.Contains($ForbiddenChromiumSmokeText)) {
        throw "tools\run-chromium-smoke.ps1 still contains standalone Chromium browser auto-discovery fallback: $ForbiddenChromiumSmokeText"
    }
}
foreach ($RequiredChromiumSmokeText in @(
        'Assert-ConcreteChromiumBrowserPath',
        'Requested -BrowserPath must provide a concrete Chromium browser path',
        'existing absolute .exe path'
    )) {
    if ($ChromiumSmokeSource -notmatch [regex]::Escape($RequiredChromiumSmokeText)) {
        throw "tools\run-chromium-smoke.ps1 is missing browser-path validation text: $RequiredChromiumSmokeText"
    }
}

$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
. $SupportPath

$TempDir = Join-Path $env:TEMP "yune-windows\m01-approval-browser-path-test"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Force $TempDir | Out-Null

$MissingRequestedBrowserPath = Join-Path $TempDir "missing-requested-browser.exe"
$MissingRequestedFailure = ""
try {
    Find-ChromiumBrowserPath -RequestedPath $MissingRequestedBrowserPath | Out-Null
}
catch {
    $MissingRequestedFailure = $_.Exception.Message
}
if ($MissingRequestedFailure -eq "") {
    throw "Find-ChromiumBrowserPath should reject a missing explicitly requested Chromium browser path instead of falling back to auto-discovery."
}
if ($MissingRequestedFailure -notmatch "concrete Chromium browser path") {
    throw "Find-ChromiumBrowserPath rejected a missing requested browser path without naming the concrete browser-path problem: $MissingRequestedFailure"
}

function Find-ChromiumBrowserPath {
    param([string]$RequestedPath = "")
    return $null
}

$FailureMessage = ""
try {
    Write-LiveSmokeApprovalEvidence `
        -Path (Join-Path $TempDir "approval.md") `
        -ApprovalNote "2026-06-26 current-session yune_windows browser path test approval" `
        -InstallDir (Join-Path $TempDir "install") `
        -YuneRoot $RepoRoot `
        -BrowserPath ""
}
catch {
    $FailureMessage = $_.Exception.Message
}
if ($FailureMessage -eq "") {
    throw "Write-LiveSmokeApprovalEvidence should reject missing Chromium browser evidence before live smoke approval."
}
if ($FailureMessage -notmatch "concrete Chromium browser path") {
    throw "Write-LiveSmokeApprovalEvidence rejected missing browser evidence without naming the concrete browser-path problem: $FailureMessage"
}

Write-Host "Live smoke resolves Chromium browser path once, rejects missing explicit browser paths, and uses the resolved path for approval, preflight, and Chromium smoke evidence."
