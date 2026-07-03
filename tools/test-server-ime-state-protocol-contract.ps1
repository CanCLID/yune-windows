param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = "",
    [int]$TimeoutMs = 180000
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m05-ime-state-$ProcessId"
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][object]$Actual,
        [Parameter(Mandatory = $true)][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Invoke-RawYuneWindowsServerRequest {
    param(
        [Parameter(Mandatory = $true)][string]$PipeLeaf,
        [Parameter(Mandatory = $true)][string]$Payload,
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [int]$TimeoutMs = 180000
    )

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $LastError = ""

    while ([DateTime]::UtcNow -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "server exited before request completed with code $($Process.ExitCode)"
        }

        $Client = $null
        try {
            $Client = [System.IO.Pipes.NamedPipeClientStream]::new(
                ".",
                $PipeLeaf,
                [System.IO.Pipes.PipeDirection]::InOut,
                [System.IO.Pipes.PipeOptions]::None)
            $Client.Connect(250)
            $Client.Write($RequestBytes, 0, $RequestBytes.Length)
            $Client.Flush()

            $Buffer = New-Object byte[] 65536
            $RemainingMs = [int][Math]::Max(1, ($Deadline - [DateTime]::UtcNow).TotalMilliseconds)
            $ReadTask = $Client.ReadAsync($Buffer, 0, $Buffer.Length)
            if (-not $ReadTask.Wait($RemainingMs)) {
                $LastError = "timed out reading response"
                continue
            }

            $BytesRead = $ReadTask.Result
            if ($BytesRead -le 0) {
                $LastError = "empty response"
                continue
            }

            $ResponseText = [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $BytesRead)
            return ($ResponseText | ConvertFrom-Json)
        }
        catch {
            $LastError = $_.Exception.Message
            Start-Sleep -Milliseconds 100
        }
        finally {
            if ($Client) {
                $Client.Dispose()
            }
        }
    }

    throw "timed out waiting for server response on $PipeLeaf. Last error: $LastError"
}

function Assert-State {
    param(
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)][string]$SchemaId,
        [Parameter(Mandatory = $true)][bool]$AsciiMode,
        [Parameter(Mandatory = $true)][bool]$FullShape,
        [Parameter(Mandatory = $true)][string]$OutputStandard,
        [bool]$ToolbarPositionSet = $false,
        [int]$ToolbarX = 0,
        [int]$ToolbarY = 0,
        [string]$ToolbarSkin = "default"
    )

    if ($null -eq $Response.state) {
        throw "server response is missing state block"
    }

    Assert-Equal ([string]$Response.state.schema_id) $SchemaId "state.schema_id mismatch."
    Assert-Equal ([bool]$Response.state.ascii_mode) $AsciiMode "state.ascii_mode mismatch."
    Assert-Equal ([bool]$Response.state.full_shape) $FullShape "state.full_shape mismatch."
    Assert-Equal ([string]$Response.state.output_standard) $OutputStandard "state.output_standard mismatch."
    if ($null -eq $Response.state.toolbar) {
        throw "server response state is missing toolbar block"
    }
    Assert-Equal ([bool]$Response.state.toolbar.position_set) $ToolbarPositionSet "state.toolbar.position_set mismatch."
    Assert-Equal ([int]$Response.state.toolbar.x) $ToolbarX "state.toolbar.x mismatch."
    Assert-Equal ([int]$Response.state.toolbar.y) $ToolbarY "state.toolbar.y mismatch."
    Assert-Equal ([string]$Response.state.toolbar.skin) $ToolbarSkin "state.toolbar.skin mismatch."
}

function Assert-ServerAlive {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $Process.Refresh()
    if ($Process.HasExited) {
        throw "$Context killed the server with exit code $($Process.ExitCode)"
    }
}

function Assert-ErrorResponse {
    param(
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-Equal ([bool]$Response.ready) $false "$Context readiness mismatch."
    if ([string]::IsNullOrWhiteSpace([string]$Response.error)) {
        throw "$Context response is missing a structured error message."
    }
    if ($null -eq $Response.state) {
        throw "$Context response is missing state for client reconciliation."
    }
}

$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
& $BuildScript -OutputDir $OutputDir -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$Server = Join-Path $OutputDir "YuneWindowsServer.exe"
$RimeDll = Join-Path $YuneRoot "target\yune-windows-native\x86_64-pc-windows-msvc\dist\lib\rime.dll"
$SourceSchemaDir = Join-Path $YuneRoot "apps\yune-web\public\schema"
$SharedDataDir = Join-Path $OutputDir "schema"
$UserDataDir = Join-Path $OutputDir "user-data"
$StateFile = Join-Path $OutputDir "state\ime-state.json"
$PipeLeaf = "yune-windows-ime-state-$ProcessId"
$PipeName = "\\.\pipe\$PipeLeaf"

& (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
    -SourceSchemaDir $SourceSchemaDir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

function Start-TestServer {
    return Start-Process -FilePath $Server -ArgumentList @(
        "--rime-dll", $RimeDll,
        "--shared-dir", $SharedDataDir,
        "--user-dir", $UserDataDir,
        "--pipe", $PipeName
    ) -WindowStyle Hidden -PassThru
}

$Process = Start-TestServer

try {
    $Initial = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=get-state`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-Equal ([bool]$Initial.ready) $true "get-state response readiness mismatch."
    Assert-State $Initial "jyut6ping3" $false $false "hong_kong_traditional"

    $NormalInput = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "input=nihao`ncommit=0`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-Equal ([bool]$NormalInput.ready) $true "ascii-off non-empty input readiness mismatch."
    Assert-State $NormalInput "jyut6ping3" $false $false "hong_kong_traditional"

    $Schemas = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=list-schemas`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    $SchemaIds = @($Schemas.schemas | ForEach-Object { [string]$_.schema_id })
    foreach ($RequiredSchema in @("jyut6ping3", "cangjie5", "luna_pinyin")) {
        if ($SchemaIds -notcontains $RequiredSchema) {
            throw "list-schemas response is missing $RequiredSchema"
        }
    }

    $Ascii = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=set-option`nname=ascii_mode`nvalue=1`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-State $Ascii "jyut6ping3" $true $false "hong_kong_traditional"

    $AsciiInput = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "input=nihao`ncommit=0`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-Equal ([bool]$AsciiInput.ready) $true "ascii-on non-empty input readiness mismatch."
    Assert-State $AsciiInput "jyut6ping3" $true $false "hong_kong_traditional"
    Assert-ServerAlive $Process "ascii_mode=true non-empty input"

    $ToolbarPosition = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=set-toolbar-position`nx=-120`ny=240`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-State $ToolbarPosition "jyut6ping3" $true $false "hong_kong_traditional" $true -120 240 "default"

    $ToolbarSkin = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=set-skin`nname=default`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-State $ToolbarSkin "jyut6ping3" $true $false "hong_kong_traditional" $true -120 240 "default"

    Stop-Process -Id $Process.Id -Force
    $Process.WaitForExit(10000) | Out-Null
    $Process = Start-TestServer

    $PersistedAsciiInput = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "input=nihao`ncommit=0`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-Equal ([bool]$PersistedAsciiInput.ready) $true "persisted ascii-on non-empty input readiness mismatch."
    Assert-State $PersistedAsciiInput "jyut6ping3" $true $false "hong_kong_traditional" $true -120 240 "default"
    Assert-ServerAlive $Process "persisted ascii_mode=true non-empty input"

    foreach ($InvalidCase in @(
            @{
                name = "unknown op"
                payload = "op=does-not-exist`n.`n"
            },
            @{
                name = "unknown option"
                payload = "op=set-option`nname=unknown_option`nvalue=1`n.`n"
            },
            @{
                name = "bad boolean option value"
                payload = "op=set-option`nname=ascii_mode`nvalue=not-a-bool`n.`n"
            },
            @{
                name = "bad output standard"
                payload = "op=set-option`nname=output_standard`nvalue=not-a-standard`n.`n"
            },
            @{
                name = "invalid schema"
                payload = "op=select-schema`nschema=missing_schema`n.`n"
            },
            @{
                name = "version-skewed request"
                payload = "op=set-option`nname=ascii_mode`nvalue=1`nclient_version=future`nunknown_field=kept`n.`n"
            }
        )) {
        $Invalid = Invoke-RawYuneWindowsServerRequest `
            -PipeLeaf $PipeLeaf `
            -Payload ([string]$InvalidCase.payload) `
            -Process $Process `
            -TimeoutMs $TimeoutMs
        Assert-ErrorResponse $Invalid ([string]$InvalidCase.name)
        Assert-ServerAlive $Process ([string]$InvalidCase.name)

        $AfterInvalid = Invoke-RawYuneWindowsServerRequest `
            -PipeLeaf $PipeLeaf `
            -Payload "op=get-state`n.`n" `
            -Process $Process `
            -TimeoutMs $TimeoutMs
        Assert-Equal ([bool]$AfterInvalid.ready) $true "server did not answer get-state after $($InvalidCase.name)."
    }

    $FullShape = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=set-option`nname=full_shape`nvalue=1`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-State $FullShape "jyut6ping3" $true $true "hong_kong_traditional" $true -120 240 "default"

    $Standard = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=set-option`nname=output_standard`nvalue=mainland_simplified`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-State $Standard "jyut6ping3" $true $true "mainland_simplified" $true -120 240 "default"

    $Schema = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "op=select-schema`nschema=luna_pinyin`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-State $Schema "luna_pinyin" $true $true "mainland_simplified" $true -120 240 "default"

    $Input = Invoke-RawYuneWindowsServerRequest `
        -PipeLeaf $PipeLeaf `
        -Payload "input=nihao`ncommit=0`n.`n" `
        -Process $Process `
        -TimeoutMs $TimeoutMs
    Assert-Equal ([bool]$Input.ready) $true "input response readiness mismatch."
    Assert-State $Input "luna_pinyin" $true $true "mainland_simplified" $true -120 240 "default"

    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        throw "server did not persist state file at $StateFile"
    }
    $Persisted = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    Assert-Equal ([string]$Persisted.schema_id) "luna_pinyin" "persisted schema mismatch."
    Assert-Equal ([bool]$Persisted.ascii_mode) $true "persisted ascii_mode mismatch."
    Assert-Equal ([bool]$Persisted.full_shape) $true "persisted full_shape mismatch."
    Assert-Equal ([string]$Persisted.output_standard) "mainland_simplified" "persisted output_standard mismatch."
    if ($null -eq $Persisted.toolbar) {
        throw "persisted state is missing toolbar block."
    }
    Assert-Equal ([bool]$Persisted.toolbar.position_set) $true "persisted toolbar.position_set mismatch."
    Assert-Equal ([int]$Persisted.toolbar.x) -120 "persisted toolbar.x mismatch."
    Assert-Equal ([int]$Persisted.toolbar.y) 240 "persisted toolbar.y mismatch."
    Assert-Equal ([string]$Persisted.toolbar.skin) "default" "persisted toolbar.skin mismatch."

    Write-Host "Server IME state protocol persists IME and toolbar state and returns it on op and input responses."
}
finally {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
    }
}
