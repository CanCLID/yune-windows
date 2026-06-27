param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-audit-yune-root-transcript-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$FixtureDir = Join-Path $OutputDir "complete-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $FixtureDir | Out-Null

$EvidenceRoot = Join-Path $FixtureDir "evidence"
$CommandsPath = Join-Path $EvidenceRoot "p2-win01-installer\commands.txt"
@"
tools\run-p2-win01-live-smoke.ps1 -PreflightOnly -PreflightPath '$EvidenceRoot\p2-win01-installer\live-preflight.json' -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -BrowserPath 'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
PASS tools\run-p2-win01-live-smoke.ps1 -PreflightOnly -PreflightPath '$EvidenceRoot\p2-win01-installer\live-preflight.json' -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -BrowserPath 'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
tools\install-yune-windows-ime.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\install-yune-windows-ime.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
tools\run-notepad-smoke.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\run-notepad-smoke.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
tools\run-chromium-smoke.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -BrowserPath 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\run-chromium-smoke.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -BrowserPath 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
tools\export-yune-windows-diagnostics.ps1 -OutputDir '$EvidenceRoot\p2-win01-settings\registered-session-diagnostics' -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme'
PASS tools\export-yune-windows-diagnostics.ps1 -OutputDir '$EvidenceRoot\p2-win01-settings\registered-session-diagnostics' -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme'
tools\uninstall-yune-windows-ime.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
PASS tools\uninstall-yune-windows-ime.ps1 -InstallDir 'C:\Users\example\AppData\Local\Yune\WindowsIme' -ApprovedMachineStateChange -ApprovalNote 'User approved elevated live smoke in this session.'
"@ | Out-File -LiteralPath $CommandsPath -Encoding utf8

$JsonPath = Join-Path $OutputDir "audit-missing-yune-root.json"
$MarkdownPath = Join-Path $OutputDir "audit-missing-yune-root.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $EvidenceRoot `
    -JsonPath $JsonPath `
    -MarkdownPath $MarkdownPath | Out-Null

$Audit = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
$InvalidGateIds = @(
    "live-preflight",
    "fresh-install-registration-activation",
    "tsf-notepad-smoke",
    "chromium-text-field-smoke"
)
foreach ($GateId in $InvalidGateIds) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId evidence when live commands omit the approved -YuneRoot, got $($Gate.status)"
    }
}
if ($Audit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts omit the approved -YuneRoot"
}

$MismatchedFixtureDir = Join-Path $OutputDir "mismatched-yune-root-fixture"
& (Join-Path $RepoRoot "tools\test-closeout-audit-complete-synthetic.ps1") `
    -OutputDir $MismatchedFixtureDir | Out-Null

$MismatchedEvidenceRoot = Join-Path $MismatchedFixtureDir "evidence"
$MismatchedCommandsPath = Join-Path $MismatchedEvidenceRoot "p2-win01-installer\commands.txt"
if (-not (Test-Path -LiteralPath $MismatchedCommandsPath)) {
    throw "mismatched Yune-root fixture did not write commands.txt"
}
(Get-Content -LiteralPath $MismatchedCommandsPath) |
    ForEach-Object {
        $_ -replace "-YuneRoot\s+'[^']+'", "-YuneRoot 'C:\Users\example\Documents\GitHub\other-yune'"
    } |
    Out-File -LiteralPath $MismatchedCommandsPath -Encoding utf8

$MismatchedJsonPath = Join-Path $OutputDir "audit-mismatched-yune-root.json"
$MismatchedMarkdownPath = Join-Path $OutputDir "audit-mismatched-yune-root.md"
& (Join-Path $RepoRoot "tools\audit-p2-win01-closeout.ps1") `
    -EvidenceRoot $MismatchedEvidenceRoot `
    -JsonPath $MismatchedJsonPath `
    -MarkdownPath $MismatchedMarkdownPath | Out-Null

$MismatchedAudit = Get-Content -Raw -LiteralPath $MismatchedJsonPath | ConvertFrom-Json
foreach ($GateId in $InvalidGateIds) {
    $Gate = $MismatchedAudit.gates | Where-Object { $_.id -eq $GateId } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit $GateId gate for mismatched Yune root"
    }
    if ($Gate.status -ne "invalid") {
        throw "audit should reject $GateId evidence when live commands use a Yune root different from approval.md, got $($Gate.status)"
    }
}
if ($MismatchedAudit.status -eq "complete") {
    throw "audit should not report complete when live command transcripts use a Yune root different from approval.md"
}

Write-Host "Closeout audit rejects live command transcripts that omit or mismatch approved Yune roots."
