param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$AuditPath = Join-Path $RepoRoot "tools\audit-m01-closeout.ps1"
if (-not (Test-Path -LiteralPath $AuditPath)) {
    throw "missing closeout audit script: $AuditPath"
}

$TempRoot = Join-Path $env:TEMP "yune-windows\m01-audit-require-complete-test"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $TempRoot | Out-Null

$JsonPath = Join-Path $TempRoot "audit.json"
$MarkdownPath = Join-Path $TempRoot "audit.md"
$EvidenceRoot = Join-Path $TempRoot "evidence"

$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $Output = & powershell -ExecutionPolicy Bypass -File $AuditPath `
        -EvidenceRoot $EvidenceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath `
        -RequireComplete 2>&1
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
}

if ($ExitCode -eq 0) {
    throw "closeout audit -RequireComplete must exit nonzero when gates are incomplete"
}
if (-not (Test-Path -LiteralPath $JsonPath)) {
    throw "closeout audit -RequireComplete must still write audit.json before failing"
}
if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    throw "closeout audit -RequireComplete must still write audit.md before failing"
}

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
if ($Audit.status -ne "incomplete") {
    throw "expected incomplete synthetic audit status, got $($Audit.status)"
}
if (($Output | Out-String) -notmatch "M01 closeout audit incomplete") {
    throw "closeout audit -RequireComplete should name incomplete status in its error"
}

Write-Host "Closeout audit -RequireComplete fails only after writing incomplete audit evidence."
