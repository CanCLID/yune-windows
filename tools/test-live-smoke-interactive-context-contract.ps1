param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$SnapshotScriptPath = Join-Path $RepoRoot "tools\write-yune-windows-state-snapshot.ps1"

foreach ($Path in @($SupportPath, $OrchestratorPath, $SnapshotScriptPath)) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing live-smoke interactive-context file: $Path"
    }
}

$SupportSource = Get-Content -Raw -LiteralPath $SupportPath
$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorPath
$SnapshotScriptSource = Get-Content -Raw -LiteralPath $SnapshotScriptPath

foreach ($Required in @(
        'function\s+Invoke-YuneWindowsInteractiveScript',
        'Shell\.Application',
        'ShellExecute',
        'interactive_child_status',
        'ChildArgumentList',
        '-File \(\[string\]\`\$Payload\.script_path\) @ChildArgumentList',
        'Assert-YuneWindowsInteractiveScriptResult'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live-smoke support must launch interactive child scripts and verify their status: $Required"
    }
}

foreach ($Required in @(
        'Invoke-YuneWindowsInteractiveScript[\s\S]*run-notepad-smoke\.ps1',
        'Invoke-YuneWindowsInteractiveScript[\s\S]*run-chromium-smoke\.ps1',
        'Invoke-YuneWindowsInteractiveScript[\s\S]*write-yune-windows-state-snapshot\.ps1[\s\S]*\$DiagnosticsPreStatePath'
    )) {
    if ($OrchestratorSource -notmatch $Required) {
        throw "live-smoke orchestrator must run interactive profile/app work through Invoke-YuneWindowsInteractiveScript: $Required"
    }
}

foreach ($Required in @(
        'Write-YuneWindowsStateSnapshot',
        'Assert-YuneWindowsActiveInstalledSnapshot',
        '\$AssertActiveInstalled'
    )) {
    if ($SnapshotScriptSource -notmatch $Required) {
        throw "interactive snapshot helper must write and assert active installed state: $Required"
    }
}

Write-Host "Live smoke orchestrator runs profile-sensitive app work in the interactive context."
