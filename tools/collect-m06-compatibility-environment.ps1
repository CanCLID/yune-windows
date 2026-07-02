param(
    [string]$OutputPath = "",
    [string]$InstallDir = "",
    [int]$LogTail = 200,
    [int]$ProfileToolTimeoutMs = 10000
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($OutputPath -eq "") {
    $OutputPath = Join-Path $RepoRoot "docs\evidence\m06\environment.json"
}
if ($InstallDir -eq "") {
    $InstallDir = Join-Path $env:LOCALAPPDATA "Yune\WindowsIme"
}
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)

function Write-CollectorTrace {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ([string]::IsNullOrWhiteSpace($env:YUNE_M06_COLLECTOR_TRACE)) {
        return
    }
    Add-Content -LiteralPath $env:YUNE_M06_COLLECTOR_TRACE -Value (
        "{0} {1}" -f (Get-Date).ToString("o"), $Step)
}

function Get-OsInfo {
    $OperatingSystem = $null
    try {
        $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    }
    catch {
        $OperatingSystem = $null
    }

    $Info = [ordered]@{
        caption = [Environment]::OSVersion.VersionString
        version = [Environment]::OSVersion.Version.ToString()
        build = [Environment]::OSVersion.Version.Build.ToString()
        os_architecture = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
        process_architecture = if ([Environment]::Is64BitProcess) { "64-bit" } else { "32-bit" }
    }
    if ($null -ne $OperatingSystem) {
        if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.Caption)) {
            $Info.caption = [string]$OperatingSystem.Caption
        }
        if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.Version)) {
            $Info.version = [string]$OperatingSystem.Version
        }
        if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.BuildNumber)) {
            $Info.build = [string]$OperatingSystem.BuildNumber
        }
        if (-not [string]::IsNullOrWhiteSpace($OperatingSystem.OSArchitecture)) {
            $Info.os_architecture = [string]$OperatingSystem.OSArchitecture
        }
    }
    return [pscustomobject]$Info
}

function Get-FileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            path = $FullPath
            exists = $false
        }
    }
    $Item = Get-Item -LiteralPath $FullPath
    return [pscustomobject][ordered]@{
        path = $FullPath
        exists = $true
        sha256 = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
        length = [int64]$Item.Length
        last_write_utc = $Item.LastWriteTimeUtc.ToString("o")
    }
}

function Invoke-ProfileStateProbe {
    param([Parameter(Mandatory = $true)][string]$ProfileToolPath)

    if (-not (Test-Path -LiteralPath $ProfileToolPath -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            available = $false
            path = [System.IO.Path]::GetFullPath($ProfileToolPath)
        }
    }

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = [System.IO.Path]::GetFullPath($ProfileToolPath)
    $StartInfo.Arguments = "--state"
    $StartInfo.UseShellExecute = $false
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    [void]$Process.Start()
    if (-not $Process.WaitForExit($ProfileToolTimeoutMs)) {
        try {
            $Process.Kill()
        }
        catch {
        }
        return [pscustomobject][ordered]@{
            available = $true
            path = $StartInfo.FileName
            timed_out = $true
        }
    }

    return [pscustomobject][ordered]@{
        available = $true
        path = $StartInfo.FileName
        timed_out = $false
        exit_code = [int]$Process.ExitCode
        stdout = $Process.StandardOutput.ReadToEnd().Trim()
        stderr = $Process.StandardError.ReadToEnd().Trim()
    }
}

Write-CollectorTrace "before artifacts"
$Artifacts = [pscustomobject][ordered]@{
    tsf_dll = Get-FileSnapshot (Join-Path $InstallDir "YuneWindowsTSF.dll")
    server_exe = Get-FileSnapshot (Join-Path $InstallDir "YuneWindowsServer.exe")
    profile_tool = Get-FileSnapshot (Join-Path $InstallDir "YuneWindowsProfileTool.exe")
    settings_exe = Get-FileSnapshot (Join-Path $InstallDir "YuneWindowsSettings.exe")
    rime_dll = Get-FileSnapshot (Join-Path $InstallDir "rime.dll")
}
Write-CollectorTrace "after artifacts"

$LogPath = Join-Path $InstallDir "logs\tsf-events.log"
$LogTailLines = @()
if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
    Write-CollectorTrace "before log tail"
    $LogTailLines = [string[]]@(Get-Content -LiteralPath $LogPath -Tail $LogTail |
        ForEach-Object { [string]$_ })
    Write-CollectorTrace "after log tail"
}

$GitHead = ""
try {
    Write-CollectorTrace "before git"
    $GitHead = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim()
    Write-CollectorTrace "after git"
}
catch {
    $GitHead = ""
}

Write-CollectorTrace "before profile"
$ProfileState = Invoke-ProfileStateProbe (Join-Path $InstallDir "YuneWindowsProfileTool.exe")
Write-CollectorTrace "after profile"

Write-CollectorTrace "before environment"
$Environment = [pscustomobject][ordered]@{
    generated_at = (Get-Date).ToString("o")
    machine_state_changed = $false
    milestone = "M06"
    repo_root = [string]$RepoRoot
    git_head = $GitHead
    install_dir = $InstallDir
    os = Get-OsInfo
    installed_artifacts = $Artifacts
    profile_state = $ProfileState
    structural_log = [pscustomobject][ordered]@{
        path = [System.IO.Path]::GetFullPath($LogPath)
        exists = Test-Path -LiteralPath $LogPath -PathType Leaf
        tail_line_count = @($LogTailLines).Count
        tail = @($LogTailLines)
    }
    live_holder_free_verification_required = $true
    elevated_steps_run = $false
}
Write-CollectorTrace "after environment"

New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null
Write-CollectorTrace "before json"
$Json = $Environment | ConvertTo-Json -Depth 8
Write-CollectorTrace "after json"
Set-Content -LiteralPath $OutputPath -Encoding UTF8 -Value $Json
Write-CollectorTrace "after write"
Write-Output $OutputPath
