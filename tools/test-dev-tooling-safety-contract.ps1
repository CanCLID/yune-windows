param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$DevRoot = Join-Path $RepoRoot "tools\dev"

if (-not (Test-Path -LiteralPath $DevRoot -PathType Container)) {
    throw "missing dev tooling directory: tools\dev"
}

$RequiredDevScripts = @(
    "dev-support.ps1",
    "dev-repl.ps1",
    "dev-reload-server.ps1",
    "dev-test-window.ps1",
    "dev-reload-tsf.ps1",
    "dev-live-closeout-preflight.ps1",
    "dev-watch.ps1"
)
foreach ($ScriptName in $RequiredDevScripts) {
    $ScriptPath = Join-Path $DevRoot $ScriptName
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "missing required dev script: tools\dev\$ScriptName"
    }
}

$Scripts = @(Get-ChildItem -LiteralPath $DevRoot -Recurse -File -Filter "*.ps1")
if ($Scripts.Count -eq 0) {
    throw "no dev scripts found under tools\dev"
}

$ForbiddenPatterns = [ordered]@{
    "regsvr32" = '(?i)\bregsvr32\b'
    "MOVEFILE_DELAY_UNTIL_REBOOT" = 'MOVEFILE_DELAY_UNTIL_REBOOT'
    "Register-" = '(?i)\bRegister-'
    "Register-ScheduledTask" = '(?i)\bRegister-ScheduledTask\b'
    "New-Service" = '(?i)\bNew-Service\b'
    "New-ItemProperty" = '(?i)\bNew-ItemProperty\b'
    "Set-ItemProperty" = '(?i)\bSet-ItemProperty\b'
    "Remove-ItemProperty" = '(?i)\bRemove-ItemProperty\b'
    "reg add" = '(?i)\breg(?:\.exe)?\s+add\b'
    "reg delete" = '(?i)\breg(?:\.exe)?\s+delete\b'
    "reg.exe" = '(?i)\breg\.exe\b'
    "schtasks" = '(?i)\bschtasks(?:\.exe)?\b'
    "sc.exe" = '(?i)\bsc\.exe\b'
    "Start-Process -Verb RunAs" = '(?is)\bStart-Process\b[^\r\n]*\b-Verb\s+RunAs\b'
    "-ApprovedMachineStateChange" = '(?i)-ApprovedMachineStateChange\b'
    "install-yune-windows-ime.ps1" = '(?i)(?:^|[^\w-])\.?\s*(?:&\s*)?["'']?[^"'']*install-yune-windows-ime\.ps1'
    "uninstall-yune-windows-ime.ps1" = '(?i)(?:^|[^\w-])\.?\s*(?:&\s*)?["'']?[^"'']*uninstall-yune-windows-ime\.ps1'
}

$Failures = [System.Collections.Generic.List[string]]::new()
foreach ($Script in $Scripts) {
    $Text = Get-Content -Raw -LiteralPath $Script.FullName
    foreach ($Name in $ForbiddenPatterns.Keys) {
        if ($Text -match $ForbiddenPatterns[$Name]) {
            $RelativePath = [System.IO.Path]::GetRelativePath($RepoRoot, $Script.FullName)
            $Failures.Add("$RelativePath contains forbidden pattern: $Name") | Out-Null
        }
    }
}

if ($Failures.Count -gt 0) {
    throw "Dev tooling safety contract failed: $($Failures -join '; ')"
}

Write-Host "Dev tooling safety contract passed for $($Scripts.Count) script(s)."
