param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$NotepadSmoke = Join-Path $RepoRoot "tools\run-notepad-smoke.ps1"
$ChromiumSmoke = Join-Path $RepoRoot "tools\run-chromium-smoke.ps1"

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

foreach ($SmokeScript in @($NotepadSmoke, $ChromiumSmoke)) {
    $SmokeSource = Get-Content -Raw -LiteralPath $SmokeScript
    $SmokeName = Split-Path -Leaf $SmokeScript
    if ($SmokeSource -notmatch '--activate') {
        throw "$SmokeName must activate the YuneWindows profile before app automation."
    }
    if ($SmokeSource -notmatch 'Assert-YuneWindowsProfileActive(?s:.*?)-ProfileToolPath\s+\$ProfileTool') {
        throw "$SmokeName must verify registered and active YuneWindows profile state before app automation."
    }
    if ($SmokeSource -notmatch '--activate(?s:.*?)Assert-YuneWindowsProfileActive(?s:.*?)(notepad-launch|browser-launch)') {
        throw "$SmokeName must verify active profile state after activation and before launching or typing in the app."
    }
    $AssertCount = ([regex]::Matches($SmokeSource, 'Assert-YuneWindowsProfileActive')).Count
    if ($AssertCount -lt 2) {
        throw "$SmokeName must verify active profile state both after activation and after focusing the app."
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

Write-Host "Live app smokes verify and record active YuneWindows profile state after activation and app focus."
