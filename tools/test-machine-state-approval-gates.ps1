param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Scripts = @(
    "tools\install-yune-windows-ime.ps1",
    "tools\uninstall-yune-windows-ime.ps1",
    "tools\clear-yune-windows-machine-residue.ps1",
    "tools\run-notepad-smoke.ps1",
    "tools\run-chromium-smoke.ps1",
    "tools\run-m01-live-smoke.ps1"
)

foreach ($Script in $Scripts) {
    $Path = Join-Path $RepoRoot $Script
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Path 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    if ($ExitCode -eq 0) {
        throw "$Script unexpectedly succeeded without approval"
    }
    $Text = $Output | Out-String
    if ($Text -notmatch "without explicit approval") {
        throw "$Script did not report the approval gate. Output: $Text"
    }
}

foreach ($Script in @(
        "tools\install-yune-windows-ime.ps1",
        "tools\uninstall-yune-windows-ime.ps1",
        "tools\clear-yune-windows-machine-residue.ps1",
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1",
        "tools\run-m01-live-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $Script
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Path -ApprovedMachineStateChange 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    if ($ExitCode -eq 0) {
        throw "$Script unexpectedly succeeded without an approval note"
    }
    $Text = $Output | Out-String
    if ($Text -notmatch "requires -ApprovalNote") {
        throw "$Script did not report the approval-note gate before machine-state work. Output: $Text"
    }
}

foreach ($Script in @(
        "tools\install-yune-windows-ime.ps1",
        "tools\uninstall-yune-windows-ime.ps1",
        "tools\clear-yune-windows-machine-residue.ps1",
        "tools\run-notepad-smoke.ps1",
        "tools\run-chromium-smoke.ps1",
        "tools\run-m01-live-smoke.ps1"
    )) {
    $Path = Join-Path $RepoRoot $Script
    $PlaceholderNote = "<current-session approval note>"
    if ($Script -eq "tools\clear-yune-windows-machine-residue.ps1") {
        $PlaceholderNote = "<current-session cleanup approval note>"
    }

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Path -ApprovedMachineStateChange -ApprovalNote $PlaceholderNote 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    if ($ExitCode -eq 0) {
        throw "$Script unexpectedly succeeded with placeholder approval note"
    }
    $Text = $Output | Out-String
    if ($Text -notmatch "placeholder") {
        throw "$Script did not reject placeholder approval-note text before machine-state work. Output: $Text"
    }
}

Write-Host "Machine-state approval gates refused unapproved install, uninstall, Notepad smoke, Chromium smoke, and live sequence runs. Cleanup helper also refused before machine residue cleanup. Standalone approved machine-state scripts and the full live sequence also refused blank or approval-brief placeholder approval notes before post-approval context checks or machine-state work."
