param(
    [string]$StatePath = "",
    [string]$TestFile = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dev-support.ps1")

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = $script:YuneWindowsDevDefaultTestWindowStatePath
}

if ([string]::IsNullOrWhiteSpace($TestFile)) {
    $TestFile = Join-Path $script:YuneWindowsDevDefaultStateRoot (
        "dev-test-window-{0}-{1}.txt" -f $PID, [Guid]::NewGuid().ToString("N").Substring(0, 8))
}
$TestFile = Resolve-YuneWindowsDevFullPath $TestFile
$TestFileParent = Split-Path -Parent $TestFile
if (-not [string]::IsNullOrWhiteSpace($TestFileParent)) {
    New-Item -Path $TestFileParent -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $TestFile -PathType Leaf)) {
    Set-Content -LiteralPath $TestFile -Encoding UTF8 -Value ""
}

$LaunchStartedAt = Get-Date
$Launcher = Start-Process -FilePath "notepad.exe" -ArgumentList @($TestFile) -PassThru
$TestFileName = Split-Path -Leaf $TestFile

$Process = $null
$Deadline = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $Deadline) {
    $Candidates = @(Get-Process -Name "Notepad" -ErrorAction SilentlyContinue |
        Where-Object {
            $StartedAfterLaunch = $false
            try {
                $StartedAfterLaunch = $_.StartTime -ge $LaunchStartedAt.AddSeconds(-2)
            }
            catch {
            }
            $TitleMatches = $false
            try {
                $TitleMatches = [string]$_.MainWindowTitle -like "*$TestFileName*"
            }
            catch {
            }
            $_.Id -eq $Launcher.Id -or ($StartedAfterLaunch -and $TitleMatches)
        } |
        Sort-Object StartTime -Descending)
    if ($Candidates.Count -gt 0) {
        $Process = $Candidates[0]
        break
    }
    Start-Sleep -Milliseconds 100
}

if (-not $Process) {
    throw "failed to identify dev-owned Notepad process for $TestFile"
}

$Process.Refresh()
$ProcessPath = ""
$ProcessStartTime = $null
try {
    $ProcessPath = [string]$Process.Path
    $ProcessStartTime = $Process.StartTime
}
catch {
}

$State = [ordered]@{
    owner = "yune-windows-dev-test-window"
    app = "notepad"
    process_id = [int]$Process.Id
    process_name = [string]$Process.ProcessName
    process_path = $ProcessPath
    process_start_time = if ($ProcessStartTime) { $ProcessStartTime.ToString("o") } else { "" }
    launched_at = (Get-Date).ToString("o")
    test_file = $TestFile
    state_path = (Resolve-YuneWindowsDevFullPath $StatePath)
}

Write-YuneWindowsDevJsonFile -Value $State -Path $StatePath

Write-Host "Started dev-owned Notepad PID $($Process.Id)."
Write-Host "State file: $StatePath"
Write-Host "Test file: $TestFile"
Write-Host "Use Win+Space in that window to select Yune Windows before testing TSF changes."
