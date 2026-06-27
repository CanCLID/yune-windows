param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PlanScript = Join-Path $RepoRoot "tools\plan-yune-windows-machine-cleanup.ps1"
if (-not (Test-Path -LiteralPath $PlanScript)) {
    throw "missing machine-cleanup plan script: $PlanScript"
}

$Source = Get-Content -Raw -LiteralPath $PlanScript
foreach ($Required in @(
        '[string]$CurrentResiduePath = ""',
        '[switch]$RefreshCurrentResidue',
        'Machine cleanup planning requires -CurrentResiduePath or -RefreshCurrentResidue.',
        'elseif ($RefreshCurrentResidue.IsPresent)',
        'Require-LiveSmokeApprovalNote -ApprovalNote $ApprovalNote',
        'machine_residue_source = $MachineResidueSource'
    )) {
    if (-not $Source.Contains($Required)) {
        throw "machine-cleanup plan is missing residue-source guard pattern: $Required"
    }
}

$CurrentResiduePathIndex = $Source.IndexOf('if (-not [string]::IsNullOrWhiteSpace($CurrentResiduePath))')
$RefreshIndex = $Source.IndexOf('elseif ($RefreshCurrentResidue.IsPresent)')
$DetectorIndex = $Source.IndexOf('Get-YuneWindowsMachineResidue -InstallDir $InstallRoot')
if ($CurrentResiduePathIndex -lt 0 -or $RefreshIndex -lt 0 -or $DetectorIndex -lt 0) {
    throw "machine-cleanup plan is missing current-residue branch anchors."
}
if ($DetectorIndex -lt $RefreshIndex) {
    throw "machine-cleanup plan must not call Get-YuneWindowsMachineResidue before the explicit refresh branch."
}

$TempDir = Join-Path $env:TEMP "yune-windows\p2-win01-machine-cleanup-plan-residue-source-guard-test"
New-Item -ItemType Directory -Force $TempDir | Out-Null
$ResiduePath = Join-Path $TempDir "current-residue.json"
$OutputPath = Join-Path $TempDir "machine-cleanup-plan.json"
$RefreshHarnessDir = Join-Path $TempDir "refresh-harness"
New-Item -ItemType Directory -Force $RefreshHarnessDir | Out-Null
Copy-Item -LiteralPath $PlanScript -Destination (Join-Path $RefreshHarnessDir "plan-yune-windows-machine-cleanup.ps1") -Force
@'
function Require-LiveSmokeApprovalNote {
    param([string]$ApprovalNote)
    if ([string]::IsNullOrWhiteSpace($ApprovalNote)) {
        throw "missing approval note"
    }
}

function Get-YuneWindowsMachineResidue {
    param([string]$InstallDir)
    return [ordered]@{
        machine_state_issues = @("Registry key remains: Registry::HKEY_CLASSES_ROOT\YuneWindows.Test")
        filesystem_leftovers = @("C:\Windows\System32\YuneWindowsTest.dll")
    }
}

function Get-JsonEvidenceProperty {
    param([object]$Object, [string]$Name)
    $Property = $Object.PSObject.Properties[$Name]
    return [pscustomobject]@{
        Found = $null -ne $Property
        Value = if ($null -ne $Property) { $Property.Value } else { $null }
    }
}

function Get-RequiredJsonBooleanProperty {
    param([object]$Object, [string]$Name, [string]$Context)
    $Property = Get-JsonEvidenceProperty -Object $Object -Name $Name
    if (-not $Property.Found -or $Property.Value -isnot [bool]) {
        throw "$Context $Name must be a JSON boolean."
    }
    return $Property.Value
}

function Get-UniqueStringItems {
    param([object[]]$Items)
    return @($Items | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}
'@ | Out-File -LiteralPath (Join-Path $RefreshHarnessDir "live-smoke-support.ps1") -Encoding utf8
$RefreshHarnessPlan = Join-Path $RefreshHarnessDir "plan-yune-windows-machine-cleanup.ps1"
$RefreshOutputPath = Join-Path $TempDir "refresh-machine-cleanup-plan.json"

& powershell -NoProfile -ExecutionPolicy Bypass -File $RefreshHarnessPlan `
    -OutputPath $RefreshOutputPath `
    -InstallDir (Join-Path $TempDir "install") `
    -RefreshCurrentResidue `
    -ApprovalNote "test approval note" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "machine-cleanup plan failed with refreshed residue evidence"
}

$RefreshPlan = Get-Content -Raw -LiteralPath $RefreshOutputPath | ConvertFrom-Json
if ($RefreshPlan.machine_residue_source -ne "Get-YuneWindowsMachineResidue") {
    throw "machine-cleanup plan did not record refreshed residue source."
}
if ($RefreshPlan.machine_state_checked -ne $true) {
    throw "machine-cleanup plan did not stamp machine_state_checked=true for refreshed residue evidence."
}
if ([string]::IsNullOrWhiteSpace([string]$RefreshPlan.generated_at)) {
    throw "machine-cleanup plan did not stamp generated_at for refreshed residue evidence."
}
if (@($RefreshPlan.machine_state_issues).Count -ne 1 -or
    @($RefreshPlan.filesystem_leftovers).Count -ne 1) {
    throw "machine-cleanup plan did not preserve refreshed residue arrays."
}

$Residue = [ordered]@{
    machine_state_checked = $true
    machine_state_issues = @("PendingFileRenameOperations contains YuneWindows residue: \??\C:\Windows\System32\YuneWindows.dll.old.0")
    filesystem_leftovers = @("C:\Windows\System32\YuneWindows.dll.old.0")
} | ConvertTo-Json -Depth 6
$Residue | Out-File -LiteralPath $ResiduePath -Encoding utf8
$ExpectedResiduePath = [System.IO.Path]::GetFullPath($ResiduePath)

$MissingSourceSucceeded = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
        -OutputPath (Join-Path $TempDir "implicit-refresh-plan.json") 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $MissingSourceSucceeded = $false
    }
}
catch {
    $MissingSourceSucceeded = $false
}
if ($MissingSourceSucceeded) {
    throw "machine-cleanup plan must reject implicit machine-residue inspection."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
    -OutputPath $OutputPath `
    -CurrentResiduePath $ResiduePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "machine-cleanup plan failed with supplied residue evidence"
}

$Plan = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
if ($Plan.machine_residue_source -ne $ExpectedResiduePath) {
    throw "machine-cleanup plan did not record supplied residue source."
}
if ($Plan.machine_state_checked -ne $true) {
    throw "machine-cleanup plan did not preserve machine_state_checked=true."
}
if (@($Plan.machine_state_issues).Count -ne 1 -or
    @($Plan.filesystem_leftovers).Count -ne 1) {
    throw "machine-cleanup plan did not use supplied residue arrays."
}
if ($Plan.blocked_live_preflight -ne $true) {
    throw "machine-cleanup plan must be blocked when supplied residue is dirty."
}

$StringTypedResiduePath = Join-Path $TempDir "string-typed-current-residue.json"
$StringTypedOutputPath = Join-Path $TempDir "string-typed-machine-cleanup-plan.json"
[ordered]@{
    machine_state_checked = "true"
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $StringTypedResiduePath -Encoding utf8

$StringTypedResidueThrew = $false
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
        -OutputPath $StringTypedOutputPath `
        -CurrentResiduePath $StringTypedResiduePath 2>&1
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
}
$Text = ($Output | Out-String)
if ($ExitCode -ne 0 -and $Text -match "machine_state_checked must be a JSON boolean") {
    $StringTypedResidueThrew = $true
}
if (-not $StringTypedResidueThrew) {
    throw "machine-cleanup plan accepted string-typed machine_state_checked residue evidence. Output: $Text"
}

$MissingCheckedResiduePath = Join-Path $TempDir "missing-checked-current-residue.json"
$MissingCheckedOutputPath = Join-Path $TempDir "missing-checked-machine-cleanup-plan.json"
[ordered]@{
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $MissingCheckedResiduePath -Encoding utf8

$MissingCheckedResidueThrew = $false
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
        -OutputPath $MissingCheckedOutputPath `
        -CurrentResiduePath $MissingCheckedResiduePath 2>&1
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
}
$Text = ($Output | Out-String)
if ($ExitCode -ne 0 -and $Text -match "machine_state_checked must be a JSON boolean") {
    $MissingCheckedResidueThrew = $true
}
if (-not $MissingCheckedResidueThrew) {
    throw "machine-cleanup plan accepted supplied residue evidence without machine_state_checked. Output: $Text"
}

$FalseCheckedResiduePath = Join-Path $TempDir "false-checked-current-residue.json"
$FalseCheckedOutputPath = Join-Path $TempDir "false-checked-machine-cleanup-plan.json"
[ordered]@{
    machine_state_checked = $false
    machine_state_issues = @()
    filesystem_leftovers = @()
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $FalseCheckedResiduePath -Encoding utf8

$FalseCheckedResidueThrew = $false
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $PlanScript `
        -OutputPath $FalseCheckedOutputPath `
        -CurrentResiduePath $FalseCheckedResiduePath 2>&1
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
}
$Text = ($Output | Out-String)
if ($ExitCode -ne 0 -and $Text -match "machine_state_checked=true") {
    $FalseCheckedResidueThrew = $true
}
if (-not $FalseCheckedResidueThrew) {
    throw "machine-cleanup plan accepted supplied residue evidence with machine_state_checked=false. Output: $Text"
}

Write-Host "Machine cleanup plan requires explicit machine-residue source evidence."
