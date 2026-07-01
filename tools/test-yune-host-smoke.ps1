param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01\yune-host\evidence"
}

$Runner = Join-Path $RepoRoot "tools\run-yune-host-smoke.ps1"
if (-not (Test-Path -LiteralPath $Runner)) {
    throw "missing smoke runner: $Runner"
}

& $Runner -YuneRoot $YuneRoot -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "Yune host smoke runner failed with exit code $LASTEXITCODE"
}

$ResultPath = Join-Path $OutputDir "result.json"
if (-not (Test-Path -LiteralPath $ResultPath)) {
    throw "missing host smoke result: $ResultPath"
}

$Result = Get-Content -Raw -LiteralPath $ResultPath | ConvertFrom-Json
if (-not $Result.exports.rime_get_api) {
    throw "rime_get_api was not resolved"
}
if (-not $Result.exports.rime_get_yune_windows_profile_api) {
    throw "rime_get_yune_windows_profile_api was not resolved"
}
if ($Result.status.schema_id -ne "jyut6ping3") {
    throw "expected status.schema_id=jyut6ping3, got '$($Result.status.schema_id)'"
}
if ([int]$Result.context.candidate_count -le 0) {
    throw "expected candidate_count > 0"
}
foreach ($Candidate in $Result.context.candidates) {
    if ($Candidate.text -eq "ngohaig") {
        throw "raw echo candidate leaked into Yune host result"
    }
}
if ($Result.sensitive_context.typed_content_logs -ne $false) {
    throw "sensitive context must suppress typed-content logs"
}
if ($Result.sensitive_context.ai_staging -ne $false) {
    throw "sensitive context must suppress AI staging"
}
if ($Result.sensitive_context.learning -ne $false) {
    throw "sensitive context must suppress learning"
}
if ($Result.sensitive_context.yune_disable_learning_option -ne $true) {
    throw "sensitive context must enable the Yune disable_learning option"
}
if ($Result.lifecycle.destroy_session -ne $true) {
    throw "host did not destroy the test session"
}
if ($Result.lifecycle.finalize -ne $true) {
    throw "host did not finalize Yune"
}

Write-Host "Yune host smoke passed: status.schema_id=$($Result.status.schema_id), candidates=$($Result.context.candidate_count)"
