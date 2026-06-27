param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BriefScript = Join-Path $RepoRoot "tools\write-p2-win01-approval-brief.ps1"
if (-not (Test-Path -LiteralPath $BriefScript)) {
    throw "missing approval brief writer: tools\write-p2-win01-approval-brief.ps1"
}

$TempDir = Join-Path $env:TEMP "yune-windows\p2-win01-approval-brief-browser-architecture-test"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Force $TempDir | Out-Null

$X86BrowserPath = Join-Path $TempDir "chromium-x86.exe"
$Bytes = [byte[]]::new(160)
$Bytes[0] = [byte][char]'M'
$Bytes[1] = [byte][char]'Z'
$PeOffset = 0x80
[BitConverter]::GetBytes([int]$PeOffset).CopyTo($Bytes, 0x3c)
$Bytes[$PeOffset] = [byte][char]'P'
$Bytes[$PeOffset + 1] = [byte][char]'E'
$Bytes[$PeOffset + 2] = 0
$Bytes[$PeOffset + 3] = 0
[BitConverter]::GetBytes([UInt16]0x014c).CopyTo($Bytes, $PeOffset + 4)
[System.IO.File]::WriteAllBytes($X86BrowserPath, $Bytes)

$PriorErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $BriefScript `
        -CleanupPlanPath (Join-Path $TempDir "missing-cleanup-plan.json") `
        -AuditPath (Join-Path $TempDir "missing-audit.json") `
        -OutputPath (Join-Path $TempDir "approval-brief.md") `
        -BrowserPath $X86BrowserPath 2>&1
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PriorErrorActionPreference
}
$Text = [string]($Output | Out-String)

if ($ExitCode -eq 0) {
    throw "approval brief writer accepted an x86 Chromium browser path."
}
if ($Text -notmatch "x64") {
    throw "approval brief writer rejected x86 browser path without naming the x64 TSF-shell requirement. Output: $Text"
}
if ($Text -match "missing-cleanup-plan") {
    throw "approval brief writer should reject incompatible browser architecture before reading cleanup-plan inputs. Output: $Text"
}

Write-Host "Approval brief rejects x86 Chromium browser paths for the current x64 TSF shell."
