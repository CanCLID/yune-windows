param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
if (-not (Test-Path -LiteralPath $OrchestratorPath)) {
    throw "missing live smoke orchestrator: $OrchestratorPath"
}

$Source = Get-Content -Raw -LiteralPath $OrchestratorPath

$PassedResultIndex = $Source.IndexOf('-Status "passed"')
$CleanupValidationFailureIndex = $Source.IndexOf('if (-not $CleanupValidation.pass)')
$CleanupFailureIndex = $Source.IndexOf('if ($CleanupFailureMessage -ne "")')
$CloseoutAuditIndex = $Source.IndexOf('$CurrentStage = "closeout-audit"')
$DiagnosticsBundleTextIndex = $Source.IndexOf('$DiagnosticsBundleText')

if ($PassedResultIndex -lt 0) {
    throw "live smoke orchestrator must write a passed result after cleanup validation succeeds"
}
if ($CleanupValidationFailureIndex -lt 0) {
    throw "live smoke orchestrator must validate cleanup before any passed result can stand"
}
if ($CleanupFailureIndex -lt 0) {
    throw "live smoke orchestrator must handle uninstall command failures before any passed result can stand"
}
if ($CloseoutAuditIndex -lt 0) {
    throw "live smoke orchestrator must run the final closeout audit after writing passed live evidence"
}
if ($DiagnosticsBundleTextIndex -lt 0) {
    throw "live smoke orchestrator must carry diagnostics bundle output forward until cleanup validation passes"
}

if ($PassedResultIndex -lt $CleanupValidationFailureIndex) {
    throw "result.md must not be marked passed before cleanup validation has a chance to fail"
}
if ($PassedResultIndex -lt $CleanupFailureIndex) {
    throw "result.md must not be marked passed before uninstall failures have a chance to rewrite it"
}
if ($PassedResultIndex -gt $CloseoutAuditIndex) {
    throw "result.md must be marked passed only after cleanup succeeds and before the final closeout audit runs"
}

if ($Source -notmatch '\$DiagnosticsBundleText\s*=\s*""') {
    throw "live smoke orchestrator must initialize diagnostics bundle text before the main live sequence"
}
if ($Source -notmatch '\$DiagnosticsBundleText\s*=\s*\(\$DiagnosticsBundle\s*\|\s*Select-Object\s+-Last\s+1\)') {
    throw "live smoke orchestrator must store diagnostics bundle output for the post-cleanup passed result"
}
if ($Source -notmatch 'function\s+Assert-DiagnosticsBundleEvidence') {
    throw "live smoke orchestrator must define a diagnostics bundle evidence validator"
}
if ($Source -notmatch 'Assert-DiagnosticsBundleEvidence\s*\{(?s:.*?)\[string\]\$OutputDir') {
    throw "live smoke diagnostics bundle validator must accept the expected registered-session output directory"
}
if ($Source -notmatch 'Assert-DiagnosticsBundleEvidence\s*\{(?s:.*?)ZipFile\]::OpenRead(?s:.*?)GetEntry\("manifest\.json"\)(?s:.*?)ConvertFrom-Json(?s:.*?)generated_at') {
    throw "live smoke diagnostics bundle validator must reject unreadable bundles or bundles without a parseable manifest generated_at"
}
if ($Source -notmatch '\$DiagnosticsBundleText\s*=\s*\(\$DiagnosticsBundle\s*\|\s*Select-Object\s+-Last\s+1\)(?s:.*?)Assert-DiagnosticsBundleEvidence\s+-Path\s+\$DiagnosticsBundleText(?s:.*?)\$LiveSmokeSucceeded\s*=\s*\$true') {
    throw "live smoke orchestrator must validate the diagnostics bundle zip path before marking the live sequence otherwise passed"
}
if ($Source -notmatch '\$DiagnosticsBundleText\s*=\s*\(\$DiagnosticsBundle\s*\|\s*Select-Object\s+-Last\s+1\)(?s:.*?)Assert-DiagnosticsBundleEvidence\s+-Path\s+\$DiagnosticsBundleText\s+-OutputDir\s+\$DiagnosticsDir(?s:.*?)\$LiveSmokeSucceeded\s*=\s*\$true') {
    throw "live smoke orchestrator must validate the diagnostics bundle zip comes from the registered-session diagnostics output directory"
}
if ($Source -notmatch 'Assert-DiagnosticsBundleEvidence\s+-Path\s+\$DiagnosticsBundleText\s+-OutputDir\s+\$DiagnosticsDir(?s:.*?)Record-CommandSuccess\s+\$DiagnosticsCommand(?s:.*?)\$LiveSmokeSucceeded\s*=\s*\$true') {
    throw "live smoke orchestrator must record diagnostics PASS only after the returned bundle passes validation"
}
if ($Source -notmatch '\$CleanupResultStatus\s*=\s*if\s*\(\$CleanupValidation\.pass\)\s*\{\s*"passed"\s*\}\s*else\s*\{\s*"failed"\s*\}') {
    throw "live smoke orchestrator must derive cleanup-result.md Status from cleanup validation"
}
if ($Source -notmatch '"Status:\s*\$CleanupResultStatus"') {
    throw "live smoke orchestrator must write cleanup-result.md Status evidence"
}

Write-Host "Live smoke harness writes passed result evidence only after cleanup validation succeeds."
