param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$OrchestratorScript = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
$StandaloneMachineStateScripts = @(
    "tools\install-yune-windows-ime.ps1",
    "tools\uninstall-yune-windows-ime.ps1",
    "tools\run-notepad-smoke.ps1",
    "tools\run-chromium-smoke.ps1"
)

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Require-LiveSmokeApprovalNote',
        'Approved live smoke requires -ApprovalNote',
        'function Write-LiveSmokeApprovalEvidence',
        'Date:',
        'Approval note:',
        'Machine state changed before approval evidence: false',
        'Administrator:',
        'STA:',
        '$BrowserEvidence = Find-ChromiumBrowserPath -RequestedPath $BrowserPath'
    )) {
    if ($SupportSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke support is missing approval-note evidence pattern: $Required"
    }
}

. $SupportScript

$MissingNoteFailed = $false
try {
    Require-LiveSmokeApprovalNote -ApprovalNote ""
}
catch {
    $MissingNoteFailed = $_.Exception.Message -match "Approved live smoke requires -ApprovalNote"
}
if (-not $MissingNoteFailed) {
    throw "blank approval notes must be rejected before live machine-state work."
}

foreach ($PlaceholderNote in @(
        "<current-session approval note>",
        "<current-session cleanup approval note>"
    )) {
    $PlaceholderNoteFailed = $false
    try {
        Require-LiveSmokeApprovalNote -ApprovalNote $PlaceholderNote
    }
    catch {
        $PlaceholderNoteFailed = $_.Exception.Message -match "placeholder"
    }
    if (-not $PlaceholderNoteFailed) {
        throw "placeholder approval notes must be rejected before live machine-state work: $PlaceholderNote"
    }
}

$TempDir = Join-Path $env:TEMP "yune-windows\approval-note-contract"
$ApprovalPath = Join-Path $TempDir "approval.md"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
$ContractBrowserPath = Join-Path $TempDir "browser\msedge.exe"
New-Item -ItemType Directory -Force (Split-Path -Parent $ContractBrowserPath) | Out-Null
$ContractBrowserBytes = [byte[]]::new(160)
$ContractBrowserBytes[0] = [byte][char]'M'
$ContractBrowserBytes[1] = [byte][char]'Z'
$ContractBrowserPeOffset = 0x80
[BitConverter]::GetBytes([int]$ContractBrowserPeOffset).CopyTo($ContractBrowserBytes, 0x3c)
$ContractBrowserBytes[$ContractBrowserPeOffset] = [byte][char]'P'
$ContractBrowserBytes[$ContractBrowserPeOffset + 1] = [byte][char]'E'
$ContractBrowserBytes[$ContractBrowserPeOffset + 2] = 0
$ContractBrowserBytes[$ContractBrowserPeOffset + 3] = 0
[BitConverter]::GetBytes([UInt16]0x8664).CopyTo($ContractBrowserBytes, $ContractBrowserPeOffset + 4)
[System.IO.File]::WriteAllBytes($ContractBrowserPath, $ContractBrowserBytes)
$ContractBrowserPath = [System.IO.Path]::GetFullPath($ContractBrowserPath)
Write-LiveSmokeApprovalEvidence `
    -Path $ApprovalPath `
    -ApprovalNote "User approved elevated live smoke in this session." `
    -InstallDir "C:\YuneWindowsContractInstall" `
    -YuneRoot "C:\YuneWindowsContractYune" `
    -BrowserPath $ContractBrowserPath

$ApprovalText = Get-Content -Raw -LiteralPath $ApprovalPath
foreach ($Required in @(
        'Date:',
        'Approval note: User approved elevated live smoke in this session.',
        'Machine state changed before approval evidence: false',
        'Administrator:',
        'STA:',
        'Install dir: C:\YuneWindowsContractInstall',
        'Yune root: C:\YuneWindowsContractYune',
        "Browser path: $ContractBrowserPath"
    )) {
    if ($ApprovalText -notmatch [regex]::Escape($Required)) {
        throw "approval evidence is missing: $Required"
    }
}

$OrchestratorSource = Get-Content -Raw -LiteralPath $OrchestratorScript
foreach ($Required in @(
        '[string]$ApprovalNote = ""',
        'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote',
        'Write-LiveSmokeApprovalEvidence',
        '-ApprovalNote $(Format-CommandValue $ApprovalNote)'
    )) {
    if ($OrchestratorSource -notmatch [regex]::Escape($Required)) {
        throw "live smoke orchestrator is missing approval-note pattern: $Required"
    }
}

$InstallPathNormalizationIndex = $OrchestratorSource.IndexOf('$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)')
$YuneRootNormalizationIndex = $OrchestratorSource.IndexOf('$YuneRoot = [System.IO.Path]::GetFullPath($YuneRoot)')
$ApprovalEvidenceIndex = $OrchestratorSource.IndexOf('Write-LiveSmokeApprovalEvidence')
$LivePreflightCommandIndex = $OrchestratorSource.IndexOf('$LivePreflightCommand = "tools\run-p2-win01-live-smoke.ps1')
$InstallCommandIndex = $OrchestratorSource.IndexOf('$InstallCommand = "tools\install-yune-windows-ime.ps1')
$NotepadCommandIndex = $OrchestratorSource.IndexOf('$NotepadCommand = "tools\run-notepad-smoke.ps1')
$ChromiumCommandIndex = $OrchestratorSource.IndexOf('$ChromiumCommand = "tools\run-chromium-smoke.ps1')
foreach ($RequiredIndex in @(
        @{ Name = "install path normalization"; Index = $InstallPathNormalizationIndex },
        @{ Name = "Yune root normalization"; Index = $YuneRootNormalizationIndex },
        @{ Name = "approval evidence write"; Index = $ApprovalEvidenceIndex },
        @{ Name = "live preflight transcript"; Index = $LivePreflightCommandIndex },
        @{ Name = "install transcript"; Index = $InstallCommandIndex },
        @{ Name = "Notepad transcript"; Index = $NotepadCommandIndex },
        @{ Name = "Chromium transcript"; Index = $ChromiumCommandIndex }
    )) {
    if ($RequiredIndex.Index -lt 0) {
        throw "run-p2-win01-live-smoke.ps1 is missing path-consistency step: $($RequiredIndex.Name)"
    }
}
foreach ($TranscriptIndex in @($ApprovalEvidenceIndex, $LivePreflightCommandIndex, $InstallCommandIndex, $NotepadCommandIndex, $ChromiumCommandIndex)) {
    if ($InstallPathNormalizationIndex -ge $TranscriptIndex) {
        throw "run-p2-win01-live-smoke.ps1 must normalize InstallDir before approval evidence and transcript command construction."
    }
    if ($YuneRootNormalizationIndex -ge $TranscriptIndex) {
        throw "run-p2-win01-live-smoke.ps1 must normalize YuneRoot before approval evidence and transcript command construction."
    }
}

foreach ($RelativeScript in $StandaloneMachineStateScripts) {
    $ScriptPath = Join-Path $RepoRoot $RelativeScript
    $ScriptSource = Get-Content -Raw -LiteralPath $ScriptPath
    foreach ($Required in @(
            '[string]$ApprovalNote = ""',
            'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote'
        )) {
        if ($ScriptSource -notmatch [regex]::Escape($Required)) {
            throw "$RelativeScript is missing standalone approval-note pattern: $Required"
        }
    }

    $ApprovalSwitchIndex = $ScriptSource.LastIndexOf("Require-Approval")
    if ($ApprovalSwitchIndex -lt 0) {
        $ApprovalSwitchIndex = $ScriptSource.IndexOf("Require-ApprovedMachineStateChange")
    }
    $ApprovalNoteIndex = $ScriptSource.IndexOf('Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote')
    $PostNoteGuardIndex = $ScriptSource.LastIndexOf("Require-Administrator")
    if ($PostNoteGuardIndex -lt 0) {
        $PostNoteGuardIndex = $ScriptSource.IndexOf('[Threading.Thread]::CurrentThread.ApartmentState')
    }
    if ($ApprovalSwitchIndex -lt 0 -or $ApprovalNoteIndex -lt 0 -or $PostNoteGuardIndex -lt 0) {
        throw "$RelativeScript is missing approval-note ordering anchors."
    }
    if ($ApprovalNoteIndex -le $ApprovalSwitchIndex) {
        throw "$RelativeScript must require the approval note after the approval switch gate."
    }
    if ($ApprovalNoteIndex -ge $PostNoteGuardIndex) {
        throw "$RelativeScript must require the approval note before post-approval context checks or machine-state work."
    }
}

foreach ($ChildInvocation in @(
        'tools\install-yune-windows-ime.ps1 -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)',
        'tools\run-notepad-smoke.ps1 -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -EvidenceDir $(Format-CommandValue $TsfEvidence) -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)',
        'tools\run-chromium-smoke.ps1 -YuneRoot $(Format-CommandValue $YuneRoot) -InstallDir $(Format-CommandValue $InstallDir) -EvidenceDir $(Format-CommandValue $TsfEvidence)',
        'tools\uninstall-yune-windows-ime.ps1 -InstallDir $(Format-CommandValue $InstallDir) -ApprovedMachineStateChange -ApprovalNote $(Format-CommandValue $ApprovalNote)'
    )) {
    if ($OrchestratorSource -notmatch [regex]::Escape($ChildInvocation)) {
        throw "live smoke orchestrator does not propagate approval note in child command: $ChildInvocation"
    }
}

$Sequence = @(
    @{ Name = "approval switch gate"; Index = $OrchestratorSource.IndexOf("Require-ApprovedMachineStateChange") },
    @{ Name = "approval note guard"; Index = $OrchestratorSource.IndexOf('Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote') },
    @{ Name = "elevated STA guard"; Index = $OrchestratorSource.IndexOf("Require-ApprovedLiveSmokeContext") },
    @{ Name = "installer evidence path"; Index = $OrchestratorSource.IndexOf('$InstallerEvidence =') },
    @{ Name = "installer evidence directory"; Index = $OrchestratorSource.IndexOf('New-Item -ItemType Directory -Force $InstallerEvidence') },
    @{ Name = "approval evidence write"; Index = $OrchestratorSource.IndexOf("Write-LiveSmokeApprovalEvidence") },
    @{ Name = "command transcript path"; Index = $OrchestratorSource.IndexOf('$CommandsPath =') },
    @{ Name = "profile probe build"; Index = $OrchestratorSource.IndexOf('$CurrentStage = "profile-probe-build"') }
)
foreach ($Step in $Sequence) {
    if ($Step.Index -lt 0) {
        throw "run-p2-win01-live-smoke.ps1 is missing sequence step: $($Step.Name)"
    }
}
for ($Index = 1; $Index -lt $Sequence.Count; $Index++) {
    if ($Sequence[$Index].Index -le $Sequence[$Index - 1].Index) {
        throw "run-p2-win01-live-smoke.ps1 must place '$($Sequence[$Index].Name)' after '$($Sequence[$Index - 1].Name)'."
    }
}

Write-Host "Live smoke requires and records the current-session approval note before context checks and machine-state work."
