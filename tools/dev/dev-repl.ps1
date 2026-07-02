param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$ScratchRoot = "",
    [string]$PipeName = "",
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

    if (($Response.PSObject.Properties.Name -contains "ready") -and
        ([bool]$Response.ready -eq $false)) {
        Write-Host "ready: false"
        if ($Response.PSObject.Properties.Name -contains "error") {
            Write-Host "error: $($Response.error)"
        }
    }
    if ($Response.PSObject.Properties.Name -contains "state") {
        $State = $Response.state
        Write-Host "state: schema=$($State.schema_id) ascii_mode=$($State.ascii_mode) full_shape=$($State.full_shape) output_standard=$($State.output_standard)"
    }
    if ($Response.PSObject.Properties.Name -contains "session") {
        Write-Host "session: $($Response.session)"
    }
    if ($Response.PSObject.Properties.Name -contains "ended") {
        Write-Host "ended: $($Response.ended)"
    }
    if ($Response.PSObject.Properties.Name -contains "schema_id") {
        Write-Host "schema_id: $($Response.schema_id)"
    }
    if ($Response.PSObject.Properties.Name -contains "handled") {
        Write-Host "handled: $($Response.handled)"
    }
    if ($Response.PSObject.Properties.Name -contains "raw_input") {
        Write-Host "raw_input: $($Response.raw_input)"
    }
    if (($Response.PSObject.Properties.Name -contains "composition") -and
        ($null -ne $Response.composition)) {
        Write-Host "preedit: $($Response.composition.preedit)"
    }
    if ($Response.PSObject.Properties.Name -contains "candidate_count") {
        Write-Host "candidate_count: $($Response.candidate_count)"
    }
    if (($Response.PSObject.Properties.Name -contains "commit_text") -and
        -not [string]::IsNullOrEmpty([string]$Response.commit_text)) {
        Write-Host "commit_text: $($Response.commit_text)"
    }

    if ($Response.PSObject.Properties.Name -contains "schemas") {
        foreach ($Schema in @($Response.schemas)) {
            Write-Host ("schema: {0}`t{1}" -f $Schema.schema_id, $Schema.name)
        }
    }

    if ($Response.PSObject.Properties.Name -contains "candidates") {
        $Index = 0
        foreach ($Candidate in @($Response.candidates)) {
            if ($null -eq $Candidate -or
                [string]::IsNullOrWhiteSpace([string]$Candidate.text)) {
                continue
            }
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
}

function Convert-YuneWindowsDevReplCommandToPayload {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [string]$ComposeSession = ""
    )

    $Trimmed = $Line.Trim()
    if ($Trimmed -eq ":state") {
        return "op=get-state`n.`n"
    }
    if ($Trimmed -eq ":schemas") {
        return "op=list-schemas`n.`n"
    }
    if ($Trimmed -match '^:ascii\s+(.+)$') {
        return "op=set-option`nname=ascii_mode`nvalue=$($Matches[1].Trim())`n.`n"
    }
    if ($Trimmed -match '^:full-shape\s+(.+)$') {
        return "op=set-option`nname=full_shape`nvalue=$($Matches[1].Trim())`n.`n"
    }
    if ($Trimmed -match '^:standard\s+(.+)$') {
        return "op=set-option`nname=output_standard`nvalue=$($Matches[1].Trim())`n.`n"
    }
    if ($Trimmed -match '^:schema\s+(.+)$') {
        return "op=select-schema`nschema=$($Matches[1].Trim())`n.`n"
    }
    if ($Trimmed -eq ":compose-begin") {
        return "op=compose-begin`n.`n"
    }
    if ($Trimmed -match '^:compose-key\s+(.+)$') {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-key"
        }
        return "op=compose-key`nsession=$ComposeSession`nkey=$($Matches[1].Trim())`nmask=0`n.`n"
    }
    if ($Trimmed -match '^:compose-select\s+(\d+)$') {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-select"
        }
        return "op=compose-select`nsession=$ComposeSession`nindex=$($Matches[1])`n.`n"
    }
    if ($Trimmed -eq ":compose-back") {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-back"
        }
        return "op=compose-back`nsession=$ComposeSession`n.`n"
    }
    if ($Trimmed -match '^:compose-page\s+(next|forward|down|prev|previous|back|backward|up)$') {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-page"
        }
        return "op=compose-page`nsession=$ComposeSession`ndirection=$($Matches[1])`n.`n"
    }
    if ($Trimmed -eq ":compose-cancel") {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-cancel"
        }
        return "op=compose-cancel`nsession=$ComposeSession`n.`n"
    }
    if ($Trimmed -eq ":compose-commit") {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-commit"
        }
        return "op=compose-commit`nsession=$ComposeSession`n.`n"
    }
    if ($Trimmed -eq ":compose-commit-raw") {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-commit-raw"
        }
        return "op=compose-commit-raw`nsession=$ComposeSession`n.`n"
    }
    if ($Trimmed -eq ":compose-end") {
        if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
            throw "run :compose-begin before :compose-end"
        }
        return "op=compose-end`nsession=$ComposeSession`n.`n"
    }
    return ""
}

function Get-YuneWindowsDevUpdatedComposeSession {
    param(
        [string]$CurrentSession,
        [Parameter(Mandatory = $true)]$Response
    )

    if (($Response.PSObject.Properties.Name -contains "ended") -and
        ([bool]$Response.ended)) {
        return ""
    }
    if (($Response.PSObject.Properties.Name -contains "ready") -and
        ([bool]$Response.ready -eq $false)) {
        return $CurrentSession
    }
    if ($Response.PSObject.Properties.Name -contains "session") {
        return [string]$Response.session
    }
    return $CurrentSession
}

function New-YuneWindowsDevReplPipeName {
    return "\\.\pipe\yune-windows-ime-dev-$PID-$([Guid]::NewGuid().ToString("N").Substring(0, 8))"
}

if ($ScratchRoot -eq "") {
    $ScratchRoot = Join-Path $env:TEMP ("yune-windows\dev-repl-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N").Substring(0, 8))
}
$ScratchRoot = Resolve-YuneWindowsDevFullPath $ScratchRoot
$PipeName = if ([string]::IsNullOrWhiteSpace($PipeName)) {
    New-YuneWindowsDevReplPipeName
}
else {
    $PipeName
}
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
    $ComposeSession = ""

    if ($Once) {
        if ([string]::IsNullOrWhiteSpace($InputText)) {
            throw "-InputText is required with -Once"
        }
        $StatePayload = Convert-YuneWindowsDevReplCommandToPayload `
            -Line $InputText `
            -ComposeSession $ComposeSession
        if (-not [string]::IsNullOrWhiteSpace($StatePayload)) {
            $Response = Invoke-YuneWindowsDevServerRawRequest `
                -PipeName $PipeName `
                -Payload $StatePayload `
                -Process $ServerProcess `
                -TimeoutMs $TimeoutMs
            $ComposeSession = Get-YuneWindowsDevUpdatedComposeSession `
                -CurrentSession $ComposeSession `
                -Response $Response
        }
        else {
            $Response = Invoke-YuneWindowsDevServerRequest `
                -PipeName $PipeName `
                -InputText $InputText `
                -Commit ([bool]$Commit) `
                -Process $ServerProcess `
                -TimeoutMs $TimeoutMs
        }
        Write-YuneWindowsDevResponse -Response $Response
        return
    }

    Write-Host "Enter jyutping, :commit <input>, :state, :schemas, :ascii <0|1>, :full-shape <0|1>, :standard <id>, :schema <id>, :compose-begin, :compose-type <input>, :compose-key <key>, :compose-select <0-based-index>, :compose-back, :compose-page <next|prev>, :compose-cancel, :compose-commit, :compose-commit-raw, :compose-end, or :quit."
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

        if ($Line.Trim() -match '^:compose-type\s+(.+)$') {
            if ([string]::IsNullOrWhiteSpace($ComposeSession)) {
                Write-Warning "run :compose-begin before :compose-type"
                continue
            }
            $Response = $null
            foreach ($Char in $Matches[1].ToCharArray()) {
                $Payload = "op=compose-key`nsession=$ComposeSession`nkey=$Char`nmask=0`n.`n"
                $Response = Invoke-YuneWindowsDevServerRawRequest `
                    -PipeName $PipeName `
                    -Payload $Payload `
                    -Process $ServerProcess `
                    -TimeoutMs $TimeoutMs
                $ComposeSession = Get-YuneWindowsDevUpdatedComposeSession `
                    -CurrentSession $ComposeSession `
                    -Response $Response
            }
            Write-YuneWindowsDevResponse -Response $Response
            continue
        }

        $StatePayload = Convert-YuneWindowsDevReplCommandToPayload `
            -Line $Line `
            -ComposeSession $ComposeSession
        if (-not [string]::IsNullOrWhiteSpace($StatePayload)) {
            $Response = Invoke-YuneWindowsDevServerRawRequest `
                -PipeName $PipeName `
                -Payload $StatePayload `
                -Process $ServerProcess `
                -TimeoutMs $TimeoutMs
            $ComposeSession = Get-YuneWindowsDevUpdatedComposeSession `
                -CurrentSession $ComposeSession `
                -Response $Response
            Write-YuneWindowsDevResponse -Response $Response
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
