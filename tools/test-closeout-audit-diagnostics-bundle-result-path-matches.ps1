param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-diagnostics-bundle-result-path-matches-test"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"
$DiagnosticsDir = Join-Path $EvidenceRoot "m01\settings\registered-session-diagnostics"
$WrongBundlePath = Join-Path $DiagnosticsDir "wrong-bundle.zip"
"not a diagnostics bundle" | Out-File -LiteralPath $WrongBundlePath -Encoding utf8

$InstallResultPath = Join-Path $EvidenceRoot "m01\installer\result.md"
$InstallResult = Get-Content -Raw -LiteralPath $InstallResultPath
$WrongBundleBlock = "Diagnostics bundle:`r`n`r`n````text`r`n$WrongBundlePath`r`n````"
$MutatedInstallResult = [regex]::Replace(
    $InstallResult,
    'Diagnostics bundle:\s*`{2,4}text\s*.*?\s*`{2,4}',
    $WrongBundleBlock,
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($MutatedInstallResult -eq $InstallResult) {
    throw "test fixture did not contain diagnostics bundle result evidence"
}
$MutatedInstallResult | Out-File -LiteralPath $InstallResultPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-wrong-diagnostics-bundle.json"
$MarkdownPath = Join-Path $OutputDir "audit-wrong-diagnostics-bundle.md"
& (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$DiagnosticsGate = $Audit.gates | Where-Object { $_.id -eq "diagnostics-export" }
$InstallGate = $Audit.gates | Where-Object { $_.id -eq "fresh-install-registration-activation" }
if (($DiagnosticsGate.status -eq "complete") -or ($InstallGate.status -eq "complete")) {
    throw "audit should reject live evidence when result.md names a different diagnostics bundle than the validated support bundle"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when installer result names the wrong diagnostics bundle artifact"
}

Write-Host "Closeout audit requires result.md to name the exact diagnostics bundle that is validated."
