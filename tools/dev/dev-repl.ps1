param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$ScratchRoot = "",
    [string]$PipeName = "\\.\pipe\yune-windows-ime-dev",
    [string]$InputText = "",
    [switch]$Once,
    [switch]$Commit,
    [int]$TimeoutMs = 180000
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "dev-support.ps1")

function Write-YuneWindowsDevResponse {
    param([Parameter(Mandatory = $true)]$Response)

    Write-Host "schema_id: $($Response.schema_id)"
    Write-Host "candidate_count: $($Response.candidate_count)"
    if (-not [string]::IsNullOrEmpty([string]$Response.commit_text)) {
        Write-Host "commit_text: $($Response.commit_text)"
    }

    $Index = 1
    foreach ($Candidate in @($Response.candidates)) {
        $Comment = [string]$Candidate.comment
        if ([string]::IsNullOrWhiteSpace($Comment)) {
            Write-Host ("[{0}] {1}" -f $Index, $Candidate.text)
        }
        else {
            Write-Host ("[{0}] {1}`t{2}" -f $Index, $Candidate.text, $Comment)
        }
        $Index += 1
    }
}

if ($ScratchRoot -eq "") {
    $ScratchRoot = Join-Path $env:TEMP ("yune-windows\dev-repl-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N").Substring(0, 8))
}
$ScratchRoot = Resolve-YuneWindowsDevFullPath $ScratchRoot
$BuildDir = Join-Path $ScratchRoot "build"
$SharedDir = Join-Path $ScratchRoot "schema"
$UserDir = Join-Path $ScratchRoot "user-data"

$ServerProcess = $null
try {
    $Package = Get-YuneWindowsDevPackage -YuneRoot $YuneRoot
    New-Item -ItemType Directory -Force $BuildDir | Out-Null

    & (Join-Path $RepoRoot "tools\build-tsf-shell.ps1") `
        -OutputDir $BuildDir `
        -YuneRoot $Package.yune_root

    & (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
        -SourceSchemaDir $Package.schema_source_dir `
        -DestinationSchemaDir $SharedDir `
        -UserDataDir $UserDir

    $ServerProcess = Start-YuneWindowsDevScratchServer `
        -ServerPath (Join-Path $BuildDir "YuneWindowsServer.exe") `
        -RimeDll $Package.rime_dll `
        -SharedDir $SharedDir `
        -UserDir $UserDir `
        -PipeName $PipeName
    Write-Host "Started dev server PID $($ServerProcess.Id) on $PipeName"

    if ($Once) {
        if ([string]::IsNullOrWhiteSpace($InputText)) {
            throw "-InputText is required with -Once"
        }
        $Response = Invoke-YuneWindowsDevServerRequest `
            -PipeName $PipeName `
            -InputText $InputText `
            -Commit ([bool]$Commit) `
            -Process $ServerProcess `
            -TimeoutMs $TimeoutMs
        Write-YuneWindowsDevResponse -Response $Response
        return
    }

    Write-Host "Enter jyutping, :commit <input>, or :quit."
    while ($true) {
        $Line = Read-Host "yune-dev"
        if ($null -eq $Line) {
            break
        }
        if ($Line -eq ":quit") {
            break
        }
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        $RequestCommit = $false
        $RequestInput = $Line
        if ($Line.StartsWith(":commit ", [System.StringComparison]::OrdinalIgnoreCase)) {
            $RequestCommit = $true
            $RequestInput = $Line.Substring(":commit ".Length).Trim()
            if ([string]::IsNullOrWhiteSpace($RequestInput)) {
                Write-Warning "missing input after :commit"
                continue
            }
        }

        $Response = Invoke-YuneWindowsDevServerRequest `
            -PipeName $PipeName `
            -InputText $RequestInput `
            -Commit $RequestCommit `
            -Process $ServerProcess `
            -TimeoutMs $TimeoutMs
        Write-YuneWindowsDevResponse -Response $Response
    }
}
finally {
    Stop-YuneWindowsDevStartedProcess -Process $ServerProcess
}
