param()

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ReloadScript = Join-Path $RepoRoot "tools\dev\dev-reload-tsf.ps1"

if (-not (Test-Path -LiteralPath $ReloadScript -PathType Leaf)) {
    throw "missing TSF reload dev script: tools\dev\dev-reload-tsf.ps1"
}

$Source = Get-Content -Raw -LiteralPath $ReloadScript

function Require-Pattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ($Source -notmatch $Pattern) {
        throw "dev-reload-tsf.ps1 must contain $Reason."
    }
}

function Forbid-Pattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ($Source -match $Pattern) {
        throw "dev-reload-tsf.ps1 must not contain $Reason."
    }
}

Require-Pattern -Pattern 'YuneWindowsTSF\.dll' -Reason "the installed TSF DLL target"
Require-Pattern -Pattern 'Get-YuneWindowsDevProcessesUsingModule' -Reason "read-only holder enumeration through dev-support.ps1"
Require-Pattern -Pattern 'Copy-Item(?s:.*?)YuneWindowsTSF\.dll' -Reason "a DLL copy/overwrite path"
Require-Pattern -Pattern 'dev-backup' -Reason "a timestamped backup path"
Require-Pattern -Pattern 'rollback|Restore-' -Reason "rollback logic after failed validation"
Require-Pattern -Pattern 'Get-FileHash|Length' -Reason "post-copy validation"

Forbid-Pattern -Pattern '(?i)\bregsvr32\b' -Reason "regsvr32"
Forbid-Pattern -Pattern '(?i)\bRegister-[A-Za-z]' -Reason "Register-* calls"
Forbid-Pattern -Pattern '(?i)install-yune-windows-ime\.ps1' -Reason "installer invocation"
Forbid-Pattern -Pattern '(?i)uninstall-yune-windows-ime\.ps1' -Reason "uninstaller invocation"
Forbid-Pattern -Pattern '(?is)\bStart-Process\b[^\r\n]*\b-Verb\s+RunAs\b' -Reason "elevated Start-Process"
Forbid-Pattern -Pattern '(?i)-ApprovedMachineStateChange\b' -Reason "approved machine-state mutation switches"

Write-Host "TSF reload no-reregister contract passed."
