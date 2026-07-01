param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$InstallerScript = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"
$UninstallerScript = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
$NotepadSmokeScript = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmokeScript = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$LiveSmokeScript = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"

foreach ($Path in @($SupportScript, $InstallerScript, $UninstallerScript, $NotepadSmokeScript, $ChromiumSmokeScript, $LiveSmokeScript)) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing required script: $Path"
    }
}

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function\s+Invoke-YuneWindowsBoundedProcess',
        'WaitForExit\(\$TimeoutSeconds\s*\*\s*1000\)',
        '\.Kill\(\)',
        'timed out after \$TimeoutSeconds seconds',
        'function\s+Invoke-YuneWindowsProfileTool',
        'function\s+Invoke-YuneWindowsRegsvr32',
        'TimeoutSeconds\s*=\s*30',
        'TimeoutSeconds\s*=\s*60'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support must provide bounded external process helpers: $Required"
    }
}

. $SupportScript
$Success = Invoke-YuneWindowsBoundedProcess `
    -FilePath $env:ComSpec `
    -ArgumentList @("/c", "echo yune_windows") `
    -Operation "bounded helper success smoke"
if ($Success.exit_code -ne 0 -or $Success.stdout -notmatch "yune_windows") {
    throw "bounded helper must capture stdout and zero exit code"
}

$NonZero = Invoke-YuneWindowsBoundedProcess `
    -FilePath $env:ComSpec `
    -ArgumentList @("/c", "exit /b 7") `
    -Operation "bounded helper nonzero smoke"
if ($NonZero.exit_code -ne 7) {
    throw "bounded helper must return nonzero exit codes without hanging"
}

try {
    $PowerShellExe = Join-Path $PSHOME "powershell.exe"
    Invoke-YuneWindowsBoundedProcess `
        -FilePath $PowerShellExe `
        -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 3") `
        -TimeoutSeconds 1 `
        -Operation "bounded helper timeout smoke" | Out-Null
    throw "bounded helper timeout smoke unexpectedly completed"
}
catch {
    if ($_.Exception.Message -notmatch "timed out after 1 seconds") {
        throw
    }
}

$InstallerSource = Get-Content -Raw -LiteralPath $InstallerScript
foreach ($Required in @(
        'Invoke-YuneWindowsRegsvr32(?s:.*?)-Arguments\s+@\("/s",\s*\$TsfDll\)(?s:.*?)-Operation\s+"regsvr32 registration"',
        'Invoke-YuneWindowsRegsvr32(?s:.*?)-Arguments\s+@\("/u",\s*"/s",\s*\$TsfDllPath\)(?s:.*?)-Operation\s+"regsvr32 rollback unregistration"',
        'Invoke-YuneWindowsProfileTool(?s:.*?)-ProfileToolPath\s+\$ProfileToolPath(?s:.*?)-Arguments\s+@\("--state"\)'
    )) {
    if ($InstallerSource -notmatch $Required) {
        throw "installer must use bounded helpers for approved external calls: $Required"
    }
}
foreach ($Forbidden in @(
        '&\s+\$Regsvr',
        '&\s+\$ProfileToolPath\s+--state'
    )) {
    if ($InstallerSource -match $Forbidden) {
        throw "installer must not use a raw blocking approved external call: $Forbidden"
    }
}

$UninstallerSource = Get-Content -Raw -LiteralPath $UninstallerScript
foreach ($Required in @(
        'Invoke-YuneWindowsRegsvr32(?s:.*?)-Arguments\s+@\("/u",\s*"/s",\s*\$TsfDll\)(?s:.*?)-Operation\s+"regsvr32 unregistration"',
        'Invoke-YuneWindowsProfileTool(?s:.*?)-ProfileToolPath\s+\$ProfileToolPath(?s:.*?)-Arguments\s+@\("--state"\)'
    )) {
    if ($UninstallerSource -notmatch $Required) {
        throw "uninstaller must use bounded helpers for approved external calls: $Required"
    }
}
foreach ($Forbidden in @(
        '&\s+\$Regsvr',
        '&\s+\$ProfileToolPath\s+--state'
    )) {
    if ($UninstallerSource -match $Forbidden) {
        throw "uninstaller must not use a raw blocking approved external call: $Forbidden"
    }
}

$LiveSmokeSource = Get-Content -Raw -LiteralPath $LiveSmokeScript
if ($LiveSmokeSource -notmatch 'Invoke-YuneWindowsProfileTool(?s:.*?)-ProfileToolPath\s+\$TextFieldProfileTool(?s:.*?)-Arguments\s+@\("--activate"\)') {
    throw "live smoke orchestrator must activate the YuneWindows profile through the bounded profile-tool helper before text-field smokes."
}
if ($LiveSmokeSource -match '&\s+\$TextFieldProfileTool\s+--activate') {
    throw "live smoke orchestrator must not activate YuneWindows profile through a raw blocking call."
}

foreach ($SmokeScript in @($NotepadSmokeScript, $ChromiumSmokeScript)) {
    $SmokeSource = Get-Content -Raw -LiteralPath $SmokeScript
    $SmokeName = Split-Path -Leaf $SmokeScript
    if ($SmokeSource -match '--activate') {
        throw "$SmokeName must not activate the YuneWindows profile; the live orchestrator owns one-time selection."
    }
    if ($SmokeSource -match '&\s+\$ProfileTool\s+--activate') {
        throw "$SmokeName must not activate YuneWindows profile through a raw blocking call."
    }
}

Write-Host "Approved external registration and profile-tool calls are timeout bounded."
