param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProfileToolPath = Join-Path $RepoRoot "src\tools\yune_windows_profile_tool.cpp"
$UninstallerPath = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"

if (-not (Test-Path -LiteralPath $ProfileToolPath)) {
    throw "missing profile tool source: $ProfileToolPath"
}
if (-not (Test-Path -LiteralPath $UninstallerPath)) {
    throw "missing uninstaller script: $UninstallerPath"
}

$ProfileToolSource = Get-Content -Raw -LiteralPath $ProfileToolPath
$UninstallerSource = Get-Content -Raw -LiteralPath $UninstallerPath

foreach ($RequiredProfileToolText in @(
        'const bool deactivate',
        'std::wstring(argv[1]) == L"--deactivate"',
        'usage: YuneWindowsProfileTool.exe [--state|--activate|--deactivate]',
        'profile_mgr->DeactivateProfile',
        'failed to deactivate YuneWindows profile'
    )) {
    if ($ProfileToolSource -notmatch [regex]::Escape($RequiredProfileToolText)) {
        throw "profile tool must support explicit YuneWindows profile deactivation before uninstall: $RequiredProfileToolText"
    }
}

foreach ($RequiredUninstallerText in @(
        'function Invoke-YuneWindowsProfileDeactivation',
        '-Arguments @("--deactivate")',
        '-Operation "profile deactivation before unregister"',
        'Assert-JsonBooleanProperty -Object $ProfileState -Name "active" -Expected $false -Context "profile deactivation"',
        'Invoke-YuneWindowsProfileDeactivation -ProfileToolPath $ProfileTool'
    )) {
    if ($UninstallerSource -notmatch [regex]::Escape($RequiredUninstallerText)) {
        throw "uninstaller must deactivate the active YuneWindows profile before regsvr32 /u: $RequiredUninstallerText"
    }
}

$DeactivateIndex = $UninstallerSource.IndexOf('Invoke-YuneWindowsProfileDeactivation -ProfileToolPath $ProfileTool')
$UnregisterIndex = $UninstallerSource.IndexOf('Invoke-YuneWindowsRegsvr32')
$RemoveIndex = $UninstallerSource.IndexOf('Remove-YuneWindowsInstallDirectoryWithRetry -Path $InstallRoot')
if ($DeactivateIndex -lt 0 -or $UnregisterIndex -lt 0 -or $RemoveIndex -lt 0) {
    throw "uninstaller source is missing deactivate, unregister, or remove steps."
}
if ($DeactivateIndex -gt $UnregisterIndex -or $DeactivateIndex -gt $RemoveIndex) {
    throw "uninstaller must deactivate the YuneWindows profile before unregistering or removing installed files."
}

Write-Host "Uninstaller deactivates the YuneWindows profile before unregistering and removing installed files."
