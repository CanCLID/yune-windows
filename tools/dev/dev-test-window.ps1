param(
    [string]$StatePath = $script:YuneWindowsDevDefaultTestWindowStatePath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dev-support.ps1")

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = $script:YuneWindowsDevDefaultTestWindowStatePath
}

$Process = Start-Process -FilePath "notepad.exe" -PassThru
Start-Sleep -Milliseconds 300

$ProcessPath = ""
try {
    $Process.Refresh()
    $ProcessPath = [string]$Process.Path
}
catch {
}

$State = [ordered]@{
    owner = "yune-windows-dev-test-window"
    app = "notepad"
    process_id = [int]$Process.Id
    process_name = [string]$Process.ProcessName
    process_path = $ProcessPath
    launched_at = (Get-Date).ToString("o")
    state_path = (Resolve-YuneWindowsDevFullPath $StatePath)
}

Write-YuneWindowsDevJsonFile -Value $State -Path $StatePath

Write-Host "Started dev-owned Notepad PID $($Process.Id)."
Write-Host "State file: $StatePath"
Write-Host "Use Win+Space in that window to select Yune Windows before testing TSF changes."
