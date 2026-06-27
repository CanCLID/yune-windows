param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-diagnostics-bundle-result-path-test"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $OutputDir | Out-Null

$EvidenceRoot = Join-Path $OutputDir "evidence"
$InstallResultPath = Join-Path $EvidenceRoot "p2-win01-installer\result.md"
$InstallResult = Get-Content -Raw -LiteralPath $InstallResultPath
$WeakDiagnosticsBlock = "Diagnostics bundle:`r`n`r`n````text`r`nsynthetic.zip`r`n````"
if ($InstallResult -match 'Diagnostics bundle:\s*`{2,4}text\s*.*?\s*`{2,4}') {
    $WeakenedInstallResult = [regex]::Replace(
        $InstallResult,
        'Diagnostics bundle:\s*`{2,4}text\s*.*?\s*`{2,4}',
        $WeakDiagnosticsBlock,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
}
else {
    $WeakenedInstallResult = [regex]::Replace(
        $InstallResult,
        '(?m)^Diagnostics bundle:.*$',
        $WeakDiagnosticsBlock)
}
if ($WeakenedInstallResult -eq $InstallResult) {
    throw "test fixture did not contain diagnostics bundle result evidence"
}
$WeakenedInstallResult | Out-File -LiteralPath $InstallResultPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-vague-diagnostics-bundle.json"
$MarkdownPath = Join-Path $OutputDir "audit-vague-diagnostics-bundle.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InstallGate = $Audit.gates | Where-Object { $_.id -eq "fresh-install-registration-activation" }
if ($InstallGate.status -eq "complete") {
    throw "audit should reject installer result evidence without the exact diagnostics bundle artifact path"
}
if ($Audit.status -eq "complete") {
    throw "audit must not report complete when result.md omits the exact diagnostics bundle artifact path"
}

Write-Host "Closeout audit requires exact diagnostics bundle path in installer result evidence."
