param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-m01-live-smoke.ps1"
if (-not (Test-Path -LiteralPath $OrchestratorPath)) {
    throw "missing live smoke orchestrator: $OrchestratorPath"
}

$Source = Get-Content -Raw -LiteralPath $OrchestratorPath
$Lines = @(Get-Content -LiteralPath $OrchestratorPath)

function Get-SourceSlice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartText,
        [Parameter(Mandatory = $true)]
        [string]$EndText
    )

    $Start = $Source.IndexOf($StartText)
    if ($Start -lt 0) {
        throw "live smoke orchestrator is missing block start: $StartText"
    }
    $End = $Source.IndexOf($EndText, $Start)
    if ($End -lt $Start) {
        throw "live smoke orchestrator is missing block end: $EndText"
    }
    return $Source.Substring($Start, ($End + $EndText.Length) - $Start)
}

$RecordStart = -1
for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index] -match '^function\s+Record-Command\s*\{') {
        $RecordStart = $Index
        break
    }
}
if ($RecordStart -lt 0) {
    throw "live smoke orchestrator is missing Record-Command"
}

$RecordEnd = -1
for ($Index = $RecordStart + 1; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index] -match '^\}') {
        $RecordEnd = $Index
        break
    }
}
if ($RecordEnd -lt 0) {
    throw "Record-Command function body is not closed"
}

$RecordBody = ($Lines[($RecordStart + 1)..($RecordEnd - 1)] -join "`n")
if ($RecordBody -notmatch 'Write-TranscriptFile') {
    throw "Record-Command must flush commands.txt immediately so failed live runs keep a command transcript"
}

foreach ($Required in @(
        'function Record-CommandSuccess',
        'function Record-CommandFailure',
        'PASS',
        'FAIL'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "live smoke orchestrator must record command completion status in commands.txt: missing $Required"
    }
}

if ($Source -notmatch '\$CurrentStage\s*=\s*"cleanup-validation"') {
    throw "live smoke orchestrator must name cleanup-validation as a failure stage"
}

if ($Source -notmatch '\$CurrentStage\s*=\s*"post-cleanup-state"') {
    throw "live smoke orchestrator must name post-cleanup-state as a failure stage"
}

$PostCleanupFailureBlock = Get-SourceSlice `
    -StartText '$CurrentStage = "post-cleanup-state"' `
    -EndText 'if (-not $CleanupValidation.pass)'
if ($PostCleanupFailureBlock -notmatch 'Write-YuneWindowsStateSnapshot' -or
    $PostCleanupFailureBlock -notmatch 'Get-Content\s+-Raw\s+-LiteralPath\s+\$PostCleanupStatePath' -or
    $PostCleanupFailureBlock -notmatch '\$CurrentStage\s*=\s*"cleanup-validation"' -or
    $PostCleanupFailureBlock -notmatch 'catch\s*\{(?s:.*?)Write-LiveSmokeResult(?s:.*?)-Status\s+"failed"(?s:.*?)-FailureStage\s+\$CurrentStage(?s:.*?)-DiagnosticsBundle\s+\$DiagnosticsBundleText(?s:.*?)throw') {
    throw "post-cleanup snapshot or validation failures must rewrite result.md as failed and preserve diagnostics bundle evidence"
}

if ($Source -notmatch 'if\s*\(\s*-not\s+\$CleanupValidation\.pass\s*\)\s*\{(?s:.*?)Write-LiveSmokeResult(?s:.*?)-Status\s+"failed"(?s:.*?)-FailureStage\s+\$CurrentStage') {
    throw "cleanup validation failure must rewrite result.md as Status: failed with the cleanup failure stage"
}

$CleanupValidationFailureBlock = Get-SourceSlice `
    -StartText 'if (-not $CleanupValidation.pass)' `
    -EndText 'throw $CleanupMessage'
if ($CleanupValidationFailureBlock -notmatch 'Write-LiveSmokeResult(?s:.*?)-Status\s+"failed"' -or
    $CleanupValidationFailureBlock -notmatch '-FailureMessage\s+\$CleanupMessage' -or
    $CleanupValidationFailureBlock -notmatch '-DiagnosticsBundle\s+\$DiagnosticsBundleText') {
    throw "cleanup validation failure must preserve diagnostics bundle evidence in result.md"
}

if ($Source -notmatch 'catch\s*\{(?s:.*?)\$CleanupFailureMessage\s*=\s*\$_\.Exception\.Message') {
    throw "uninstall failures must be captured before cleanup validation continues"
}

if ($Source -notmatch 'if\s*\(\s*\$CleanupFailureMessage\s+-ne\s+""\s*\)\s*\{(?s:.*?)Write-LiveSmokeResult(?s:.*?)-Status\s+"failed"(?s:.*?)-FailureStage\s+"cleanup"') {
    throw "uninstall failure must rewrite result.md as Status: failed with cleanup failure stage"
}

$CleanupFailureBlock = Get-SourceSlice `
    -StartText 'if ($CleanupFailureMessage -ne "")' `
    -EndText 'throw $CleanupFailureMessage'
if ($CleanupFailureBlock -notmatch 'Write-LiveSmokeResult(?s:.*?)-Status\s+"failed"' -or
    $CleanupFailureBlock -notmatch '-FailureMessage\s+\$CleanupFailureMessage' -or
    $CleanupFailureBlock -notmatch '-DiagnosticsBundle\s+\$DiagnosticsBundleText') {
    throw "uninstall failure after diagnostics export must preserve diagnostics bundle evidence in result.md"
}

if ($Source -notmatch '\$CurrentStage\s*=\s*"closeout-audit"') {
    throw "live smoke orchestrator must name closeout-audit as a failure stage"
}

if ($Source -notmatch '\$LiveSmokeSucceeded\s*=\s*\$false') {
    throw "live smoke orchestrator must track whether install, app smokes, and diagnostics passed before final audit"
}

if ($Source -notmatch '\$DiagnosticsBundleText\s*=\s*""') {
    throw "live smoke orchestrator must initialize diagnostics bundle text before the live sequence"
}

if ($Source -notmatch '\$DiagnosticsBundleText\s*=\s*\(\$DiagnosticsBundle\s*\|\s*Select-Object\s+-Last\s+1\)(?s:.*?)\$LiveSmokeSucceeded\s*=\s*\$true') {
    throw "live smoke orchestrator must retain diagnostics output and mark the live sequence otherwise passed only after diagnostics export succeeds"
}

if ($Source -notmatch 'try\s*\{(?s:.*?)\$DiagnosticsBundleText\s*=\s*\(\$DiagnosticsBundle\s*\|\s*Select-Object\s+-Last\s+1\)(?s:.*?)Assert-DiagnosticsBundleEvidence\s+-Path\s+\$DiagnosticsBundleText\s+-OutputDir\s+\$DiagnosticsDir(?s:.*?)Record-CommandSuccess\s+\$DiagnosticsCommand(?s:.*?)\}\s*catch\s*\{(?s:.*?)Record-CommandFailure\s+\$DiagnosticsCommand\s+\$_\.Exception\.Message(?s:.*?)throw') {
    throw "diagnostics bundle validation failures must record diagnostics FAIL in commands.txt before the live sequence reports failure"
}

if ($Source -notmatch 'if\s*\(\s*\$LiveSmokeSucceeded\s*\)\s*\{(?s:.*?)Write-LiveSmokeResult(?s:.*?)-Status\s+"passed"(?s:.*?)\$CurrentStage\s*=\s*"closeout-audit"(?s:.*?)try\s*\{(?s:.*?)audit-m01-closeout\.ps1(?s:.*?)-RequireComplete(?s:.*?)\}\s*catch\s*\{(?s:.*?)Write-LiveSmokeResult(?s:.*?)-Status\s+"failed"(?s:.*?)-FailureStage\s+\$CurrentStage') {
    throw "closeout audit failure must rewrite result.md only after cleanup succeeded and the live sequence has otherwise passed"
}

Write-Host "Live smoke harness preserves failure evidence for command transcript, uninstall failures, post-cleanup state failures, cleanup validation failures, deferred pass evidence, and closeout audit failures."
