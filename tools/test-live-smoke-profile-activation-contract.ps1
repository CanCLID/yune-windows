param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"
$LiveSmoke = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
foreach ($Required in @(
        'function Assert-YuneWindowsProfileActive',
        'ConvertFrom-Json',
        'Assert-JsonBooleanProperty\s+-Object\s+\$ProfileState\s+-Name\s+"registered"\s+-Expected\s+\$true',
        'Assert-JsonBooleanProperty\s+-Object\s+\$ProfileState\s+-Name\s+"active"\s+-Expected\s+\$true',
        'profile activation did not verify'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "live smoke support is missing active-profile verification pattern: $Required"
    }
}

$LiveSource = Get-Content -Raw -LiteralPath $LiveSmoke
if ($LiveSource -notmatch 'text-field-smoke-profile-activation') {
    throw "live orchestrator must activate the YuneWindows profile once before text-field smokes."
}
if ($LiveSource -notmatch 'Invoke-YuneWindowsProfileTool(?s:.*?)-ProfileToolPath\s+\$TextFieldProfileTool(?s:.*?)-Arguments\s+@\("--activate"\)(?s:.*?)-Operation\s+"text-field smoke profile activation"') {
    throw "live orchestrator must activate the YuneWindows profile through the bounded profile-tool helper before text-field smokes."
}
if ($LiveSource -notmatch 'text-field-smoke-profile-activation(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)notepad-smoke') {
    throw "live orchestrator must verify active profile state after activation and before Notepad smoke."
}

foreach ($SmokeScript in @($NotepadSmoke, $ChromiumSmoke)) {
    $SmokeSource = Get-Content -Raw -LiteralPath $SmokeScript
    $SmokeName = Split-Path -Leaf $SmokeScript
    if ($SmokeSource -match '--activate') {
        throw "$SmokeName must not activate the YuneWindows profile; the live orchestrator owns one-time activation."
    }
    if ($SmokeSource -notmatch 'Assert-YuneWindowsProfileActive(?s:.*?)-ProfileToolPath\s+\$ProfileTool') {
        throw "$SmokeName must verify registered and active YuneWindows profile state before app automation."
    }
    if ($SmokeSource -notmatch 'profile-preflight(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)(notepad-launch|browser-launch)') {
        throw "$SmokeName must verify active profile state before launching app automation."
    }
    $AssertCount = ([regex]::Matches($SmokeSource, 'Assert-YuneWindowsProfileActive')).Count
    if ($AssertCount -lt 2) {
        throw "$SmokeName must verify active profile state both before app launch and after focusing the app."
    }
    if ($SmokeSource -notmatch '(Set-YuneWindowsForegroundProcess|Set-YuneWindowsForegroundNotepadWindow|Set-YuneWindowsForegroundChromiumWindow)(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)StructuralLogStartLineCount') {
        throw "$SmokeName must re-verify active profile state after focusing the app and before typing."
    }
    if ($SmokeSource -notmatch 'ActiveProfileVerifiedBeforeTyping') {
        throw "$SmokeName must record active-profile verification before typing in result evidence."
    }
    if ($SmokeSource -notmatch '(Set-YuneWindowsForegroundProcess|Set-YuneWindowsForegroundNotepadWindow|Set-YuneWindowsForegroundChromiumWindow)(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)ActiveProfileVerifiedBeforeTyping\s*=\s*\$true(?s:.*?)StructuralLogStartLineCount') {
        throw "$SmokeName must set active-profile proof only after focused-app profile verification and before typing."
    }
    if ($SmokeSource -notmatch 'Active profile verified before typing: \$ActiveProfileVerifiedBeforeTyping') {
        throw "$SmokeName result evidence must report whether active profile was verified before typing."
    }
}

Write-Host "Live orchestrator activates once, and app smokes verify active YuneWindows profile state before typing."
