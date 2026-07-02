param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune",
    [string]$OutputDir = "",
    [int]$TimeoutMs = 180000
)

# M07 Slice A contract: the shared server must own persistent Rime sessions for
# client composition, expose raw input/preedit state, preserve remaining input
# after partial candidate selection, and support raw Enter commits without
# relying on a stateless replay.

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m07-persistent-composition-$ProcessId"
}

. (Join-Path $RepoRoot "tools\dev\dev-support.ps1")

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

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-NonEmpty {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw $Message
    }
}

function Invoke-ComposeRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Payload
    )

    return Invoke-YuneWindowsDevServerRawRequest `
        -PipeName $PipeName `
        -Payload $Payload `
        -Process $ServerProcess `
        -TimeoutMs $TimeoutMs
}

function New-ComposeSession {
    $Response = Invoke-ComposeRequest -Payload "op=compose-begin`n.`n"
    Assert-Equal ([bool]$Response.ready) $true "compose-begin readiness mismatch."
    Assert-NonEmpty ([string]$Response.session) "compose-begin did not return a session token."
    Assert-Equal ([string]$Response.raw_input) "" "new composition session should start with empty raw input."
    return [string]$Response.session
}

function Send-ComposeText {
    param(
        [Parameter(Mandatory = $true)][string]$Session,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $Response = $null
    foreach ($Char in $Text.ToCharArray()) {
        $Response = Invoke-ComposeRequest -Payload (
            "op=compose-key`nsession=$Session`nkey=$Char`nmask=0`n.`n")
        Assert-Equal ([bool]$Response.ready) $true "compose-key readiness mismatch for '$Char'."
    }
    return $Response
}

$BuildScript = Join-Path $RepoRoot "tools\build-tsf-shell.ps1"
& $BuildScript -OutputDir $OutputDir -YuneRoot $YuneRoot
if ($LASTEXITCODE -ne 0) {
    throw "build failed with exit code $LASTEXITCODE"
}

$Package = Get-YuneWindowsDevPackage -YuneRoot $YuneRoot
$SharedDataDir = Join-Path $OutputDir "schema"
$UserDataDir = Join-Path $OutputDir "user-data"
$ServerPath = Join-Path $OutputDir "YuneWindowsServer.exe"
$PipeName = "\\.\pipe\yune-windows-persistent-composition-$ProcessId"

& (Join-Path $RepoRoot "tools\prepare-yune-product-data.ps1") `
    -SourceSchemaDir $Package.schema_source_dir `
    -DestinationSchemaDir $SharedDataDir `
    -UserDataDir $UserDataDir

$ServerProcess = Start-YuneWindowsDevScratchServer `
    -ServerPath $ServerPath `
    -RimeDll $Package.rime_dll `
    -SharedDir $SharedDataDir `
    -UserDir $UserDataDir `
    -PipeName $PipeName

try {
    $Warm = Invoke-ComposeRequest -Payload "op=get-state`n.`n"
    Assert-Equal ([bool]$Warm.ready) $true "warm-up get-state readiness mismatch."

    $Session = New-ComposeSession
    $Typed = Send-ComposeText -Session $Session -Text "ngohaig"
    Assert-Equal ([string]$Typed.session) $Session "compose-key changed the session token."
    Assert-Equal ([string]$Typed.raw_input) "ngohaig" "compose-key did not preserve raw input."
    Assert-True ([int]$Typed.candidate_count -gt 0) "compose-key did not expose candidates."
    Assert-NonEmpty ([string]$Typed.composition.preedit) "compose-key did not expose inline preedit text."

    $Back = Invoke-ComposeRequest -Payload "op=compose-back`nsession=$Session`n.`n"
    Assert-Equal ([bool]$Back.ready) $true "compose-back readiness mismatch."
    Assert-Equal ([string]$Back.raw_input) "ngohai" "compose-back did not edit the live raw input."

    $End = Invoke-ComposeRequest -Payload "op=compose-end`nsession=$Session`n.`n"
    Assert-Equal ([bool]$End.ready) $true "compose-end readiness mismatch."
    Assert-Equal ([bool]$End.ended) $true "compose-end did not acknowledge session disposal."

    $AfterEnd = Invoke-ComposeRequest -Payload "op=compose-key`nsession=$Session`nkey=a`nmask=0`n.`n"
    Assert-Equal ([bool]$AfterEnd.ready) $false "ended compose session should not accept more keys."

    $FixturePath = Join-Path $YuneRoot "crates\yune-core\tests\fixtures\typeduck-v1.1.2\jyut6ping3-m28-partial-selection.json"
    $Fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    # Windows product data repackages the fixture's jyut6ping3_mobile template
    # behind the profile-owned jyut6ping3 schema id.
    $FixtureSchema = "jyut6ping3"
    $FixtureInput = [string]$Fixture.input
    $SelectionIndex = [int]$Fixture.selection_request.actual_candidate_index
    $RemainingInput = [string]$Fixture.captured_active_remaining_input_by_consumed_span

    $Schema = Invoke-ComposeRequest -Payload "op=select-schema`nschema=$FixtureSchema`n.`n"
    Assert-Equal ([bool]$Schema.ready) $true "fixture schema selection failed."
    Assert-Equal ([string]$Schema.state.schema_id) $FixtureSchema "fixture schema did not become active."

    $PartialSession = New-ComposeSession
    $BeforeSelect = Send-ComposeText -Session $PartialSession -Text $FixtureInput
    Assert-Equal ([string]$BeforeSelect.raw_input) $FixtureInput "fixture input was not retained before selection."
    Assert-True ([int]$BeforeSelect.candidate_count -gt $SelectionIndex) "fixture did not expose the selected candidate index."

    $Selected = Invoke-ComposeRequest -Payload (
        "op=compose-select`nsession=$PartialSession`nindex=$SelectionIndex`n.`n")
    Assert-Equal ([bool]$Selected.ready) $true "compose-select readiness mismatch."
    Assert-NonEmpty ([string]$Selected.commit_text) "partial selection did not return committed text."
    Assert-Equal ([string]$Selected.raw_input) $RemainingInput "partial selection discarded or misreported remaining input."
    Assert-NonEmpty ([string]$Selected.composition.preedit) "partial selection did not keep inline preedit for remaining input."
    Assert-True ([int]$Selected.candidate_count -gt 0) "partial selection did not expose next candidates."

    $RawSession = New-ComposeSession
    $null = Send-ComposeText -Session $RawSession -Text "caksi"
    $RawCommit = Invoke-ComposeRequest -Payload "op=compose-commit-raw`nsession=$RawSession`n.`n"
    Assert-Equal ([bool]$RawCommit.ready) $true "compose-commit-raw readiness mismatch."
    Assert-Equal ([string]$RawCommit.commit_text) "caksi" "raw Enter commit did not return the typed letters."
    Assert-Equal ([string]$RawCommit.raw_input) "" "raw Enter commit did not clear the composition."

    $CandidateSession = New-ComposeSession
    $null = Send-ComposeText -Session $CandidateSession -Text "caksi"
    $CandidateCommit = Invoke-ComposeRequest -Payload "op=compose-commit`nsession=$CandidateSession`n.`n"
    Assert-Equal ([bool]$CandidateCommit.ready) $true "compose-commit readiness mismatch."
    Assert-NonEmpty ([string]$CandidateCommit.commit_text) "candidate commit did not return committed text."
    Assert-True (([string]$CandidateCommit.commit_text) -ne "caksi") "candidate commit unexpectedly returned the raw typed letters."
    Assert-Equal ([string]$CandidateCommit.raw_input) "" "candidate commit did not clear the composition."

    Write-Host "Persistent composition server protocol contract passed."
}
finally {
    if ($ServerProcess -and -not $ServerProcess.HasExited) {
        Stop-Process -Id $ServerProcess.Id -Force
    }
}
