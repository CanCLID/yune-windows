param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PlanScript = Join-Path $RepoRoot "tools\plan-yune-windows-machine-cleanup.ps1"
if (-not (Test-Path -LiteralPath $PlanScript)) {
    throw "missing non-mutating machine-cleanup plan script: $PlanScript"
}

$Source = Get-Content -Raw -LiteralPath $PlanScript
foreach ($Required in @(
        'live-smoke-support\.ps1',
        'Get-YuneWindowsMachineResidue',
        'machine_state_changed\s*=\s*\$false',
        'requires_current_session_approval\s*=\s*\$true',
        'blocked_live_preflight',
        'recommended_steps',
        'machine_state_issues',
        'filesystem_leftovers'
    )) {
    if ($Source -notmatch $Required) {
        throw "machine-cleanup plan script is missing required pattern: $Required"
    }
}

foreach ($Forbidden in @(
        'Remove-Item',
        'Remove-ItemProperty',
        'Set-ItemProperty',
        'New-ItemProperty',
        'reg\.exe',
        'regsvr32',
        'Stop-Process',
        'Start-Process'
    )) {
    if ($Source -match $Forbidden) {
        throw "machine-cleanup plan script must be non-mutating and must not contain: $Forbidden"
    }
}

$OutputPath = Join-Path $env:TEMP "yune-windows\p2-win01-machine-cleanup-plan-test.json"
$CurrentResiduePath = Join-Path $env:TEMP "yune-windows\p2-win01-machine-cleanup-plan-test-current-residue.json"
[ordered]@{
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $CurrentResiduePath -Encoding utf8
& powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
    -OutputPath $OutputPath `
    -CurrentResiduePath $CurrentResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "machine-cleanup plan script failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "machine-cleanup plan script did not write output: $OutputPath"
}

$Plan = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
if ($Plan.machine_state_changed -ne $false) {
    throw "machine-cleanup plan must record machine_state_changed=false"
}
if ($Plan.machine_residue_source -ne [System.IO.Path]::GetFullPath($CurrentResiduePath)) {
    throw "machine-cleanup plan must record supplied machine residue source"
}
if ($Plan.requires_current_session_approval -ne $true) {
    throw "machine-cleanup plan must record requires_current_session_approval=true"
}
if ($Plan.blocked_live_preflight -ne ((@($Plan.machine_state_issues).Count + @($Plan.filesystem_leftovers).Count) -gt 0)) {
    throw "machine-cleanup plan blocked_live_preflight does not match residue counts"
}
if ($null -eq $Plan.recommended_steps) {
    throw "machine-cleanup plan must include recommended_steps"
}

Write-Host "Machine cleanup plan is non-mutating and records approval-gated residue steps."
