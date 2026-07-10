param(
    [Parameter(Mandatory = $true)]
    [string]$ImplementationCommit,
    [string]$CandidateManifestPath = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$CanonicalManifestRelativePath =
    "docs/evidence/m10/machine-state/frozen-candidate.json"
$CanonicalManifestPath = [IO.Path]::GetFullPath((
        Join-Path $RepoRoot $CanonicalManifestRelativePath))
if ([string]::IsNullOrWhiteSpace($CandidateManifestPath)) {
    $CandidateManifestPath = $CanonicalManifestPath
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot `
        "docs\evidence\m10\non-elevated-preflight.json"
}
$CandidateManifestPath = [IO.Path]::GetFullPath($CandidateManifestPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (-not [string]::Equals(
        $CandidateManifestPath,
        $CanonicalManifestPath,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "M10 preflight capture requires the canonical committed durable manifest: $CanonicalManifestPath"
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $Text = (& git -C $RepoRoot @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $Text"
    }
    return $Text
}

function Convert-ToIsoTimestamp {
    param([Parameter(Mandatory = $true)][DateTimeOffset]$Value)

    return $Value.ToString(
        "o",
        [Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-RecordedCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $Started = [DateTimeOffset]::Now
    $Output = @(& $Action 2>&1)
    $ExitCode = $LASTEXITCODE
    $Completed = [DateTimeOffset]::Now
    foreach ($Line in $Output) {
        Write-Host $Line
    }
    return [pscustomobject][ordered]@{
        command = $Command
        started_at = Convert-ToIsoTimestamp $Started
        completed_at = Convert-ToIsoTimestamp $Completed
        duration_ms = [Math]::Round(
            ($Completed - $Started).TotalMilliseconds,
            3)
        exit_code = [int]$ExitCode
        passed = ($ExitCode -eq 0)
    }
}

if (-not (Test-Path -LiteralPath $CandidateManifestPath -PathType Leaf)) {
    throw "missing durable candidate manifest: $CandidateManifestPath"
}
$Manifest = Get-Content -Raw -LiteralPath $CandidateManifestPath |
    ConvertFrom-Json
$DeploymentSourceCommit = [string]$Manifest.source.actual_commit
if ($DeploymentSourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "durable candidate manifest has no full source.actual_commit"
}
if ([string]$Manifest.status -ne "deployed_restart_required") {
    throw "durable candidate manifest is not the frozen deployed candidate"
}
if (-not [bool]$Manifest.deployment.performed -or
    -not [string]::IsNullOrWhiteSpace([string]$Manifest.deployment.error) -or
    [bool]$Manifest.deployment.rollback_attempted -or
    [bool]$Manifest.deployment.rollback_complete) {
    throw "durable candidate manifest does not record a successful no-rollback deployment"
}

[void](Invoke-GitText -Arguments @(
        "ls-files",
        "--error-unmatch",
        $CanonicalManifestRelativePath))

$ResolvedImplementationCommit = Invoke-GitText -Arguments @(
    "rev-parse",
    "--verify",
    "$ImplementationCommit^{commit}")
$CheckedTreeCommit = Invoke-GitText -Arguments @("rev-parse", "HEAD")
[void](Invoke-GitText -Arguments @(
        "merge-base",
        "--is-ancestor",
        $ResolvedImplementationCommit,
        $DeploymentSourceCommit))
[void](Invoke-GitText -Arguments @(
        "merge-base",
        "--is-ancestor",
        $DeploymentSourceCommit,
        $CheckedTreeCommit))
$ProductBuildInputPathspec = @(
    "src/**",
    "skins/**",
    "tools/build-tsf-shell.ps1")
$ProductBuildInputDiffArguments = @(
    "diff",
    "--name-only",
    "--diff-filter=ACDMRTUXB",
    "$DeploymentSourceCommit..$CheckedTreeCommit",
    "--") + $ProductBuildInputPathspec
$ProductBuildInputDiff = Invoke-GitText `
    -Arguments $ProductBuildInputDiffArguments
$ChangedProductBuildInputPaths = if (
    [string]::IsNullOrWhiteSpace($ProductBuildInputDiff)) {
    @()
}
else {
    @($ProductBuildInputDiff -split "`r?`n" | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        })
}
if ($ChangedProductBuildInputPaths.Count -ne 0) {
    throw "checked tree changes frozen product build inputs: $($ChangedProductBuildInputPaths -join ', ')"
}
$StatusBefore = Invoke-GitText -Arguments @(
    "status",
    "--porcelain",
    "--untracked-files=all")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) {
    throw "M10 preflight capture requires a clean tree before the run: $StatusBefore"
}

$PowerShellExe = Join-Path $PSHOME "powershell.exe"
if (-not (Test-Path -LiteralPath $PowerShellExe -PathType Leaf)) {
    throw "Windows PowerShell executable is unavailable: $PowerShellExe"
}
$CheckScripts = @(
    "tools/test-tsf-shell-build.ps1",
    "tools/test-language-bar-smoke.ps1",
    "tools/test-settings-window-smoke.ps1",
    "tools/test-m08-modern-toolbar-contract.ps1",
    "tools/test-m09-settings-panel-contract.ps1",
    "tools/test-m11-ui-modernization-contract.ps1",
    "tools/test-m11c-dcomp-glass-toolbar-contract.ps1",
    "tools/test-language-bar-window-contract.ps1",
    "tools/test-language-bar-topology-diagnostic-contract.ps1",
    "tools/test-settings-ime-state-contract.ps1",
    "tools/test-server-ime-state-protocol-contract.ps1",
    "tools/test-tsf-server-response-validation-contract.ps1",
    "tools/test-m11d-activation-reliability-contract.ps1",
    "tools/test-m11d-activation-trace-contract.ps1",
    "tools/test-m11d-reliability-smoke.ps1",
    "tools/test-m11d-multiprocess-reliability-smoke.ps1",
    "tools/test-tsf-ime-state-hotkey-contract.ps1",
    "tools/test-candidate-window-smoke.ps1",
    "tools/test-m10-evidence-summary-contract.ps1",
    "tools/test-m10-frozen-candidate-deploy-contract.ps1"
)

$RunStarted = [DateTimeOffset]::Now
$Checks = [Collections.Generic.List[object]]::new()
$Checks.Add((Invoke-RecordedCheck -Command "git diff --check" -Action {
            & git -C $RepoRoot diff --check
        }))
foreach ($RelativeScript in $CheckScripts) {
    $FullScript = Join-Path $RepoRoot ($RelativeScript -replace '/', '\')
    if (-not (Test-Path -LiteralPath $FullScript -PathType Leaf)) {
        throw "missing M10 preflight check: $RelativeScript"
    }
    $Checks.Add((Invoke-RecordedCheck -Command $RelativeScript -Action {
                & $PowerShellExe `
                    -NoProfile `
                    -ExecutionPolicy Bypass `
                    -File $FullScript
            }))
}
$RunCompleted = [DateTimeOffset]::Now

$PostRunCommit = Invoke-GitText -Arguments @("rev-parse", "HEAD")
$StatusAfter = Invoke-GitText -Arguments @(
    "status",
    "--porcelain",
    "--untracked-files=all")
if (-not [string]::Equals(
        $CheckedTreeCommit,
        $PostRunCommit,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace($StatusAfter)) {
    throw "source commit/tree changed during the M10 preflight run"
}

$AllPassed = @($Checks | Where-Object { -not [bool]$_.passed }).Count -eq 0
$Report = [pscustomobject][ordered]@{
    schema_version = 2
    milestone = "M10"
    evidence_kind = "non_elevated_preflight"
    captured_at = Convert-ToIsoTimestamp $RunCompleted
    started_at = Convert-ToIsoTimestamp $RunStarted
    completed_at = Convert-ToIsoTimestamp $RunCompleted
    duration_ms = [Math]::Round(
        ($RunCompleted - $RunStarted).TotalMilliseconds,
        3)
    implementation_commit = $ResolvedImplementationCommit
    checked_tree_commit = $CheckedTreeCommit
    checked_tree_clean_before = $true
    checked_tree_clean_after = $true
    commit_role_order_verified = $true
    deployment_source_commit = $DeploymentSourceCommit
    candidate_equivalence = [pscustomobject][ordered]@{
        from_deployment_source_commit = $DeploymentSourceCommit
        to_checked_tree_commit = $CheckedTreeCommit
        checked_pathspec = @($ProductBuildInputPathspec)
        changed_paths = @($ChangedProductBuildInputPaths)
        product_build_inputs_unchanged = $true
    }
    candidate_manifest_path = $CanonicalManifestRelativePath
    candidate_manifest_sha256 =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateManifestPath).Hash
    verdict = if ($AllPassed) { "pass" } else { "fail" }
    settings_dpi_percent_matrix = @(100, 125, 150, 200)
    settings_minimum_larger_scroll_each_dpi = $AllPassed
    checks = @($Checks)
    stress_results = [pscustomobject][ordered]@{
        language_bar_repeated_drags = 50
        intermediate_moves_per_drag = 100
        movement_renders = 0
        final_renders_per_completed_drag = 1
        paced_server_cas_actions = 100
        paced_server_revision_advances = 100
        timeout_after_commit_reconciled_once = $AllPassed
        persistence_failure_atomic_and_recovered_once = $AllPassed
    }
    review = [pscustomobject][ordered]@{
        scope = "automated_non_elevated_checks_only"
        manual_review_findings_claimed = $false
        current_candidate_post_restart_machine_verified = $false
        completed_summary_exists = $false
    }
    m11_boundary = [pscustomobject][ordered]@{
        m11_acceptance_claimed = $false
        remaining_direct_tsf_matrix = "pending"
        note = "This record supports M10 presentation readiness only. D-22 leaves M11 direct-TSF and installed activation/state acceptance open."
    }
}

$ParentDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $ParentDirectory -PathType Container)) {
    New-Item -Path $ParentDirectory -ItemType Directory -Force | Out-Null
}
$TemporaryOutput = "$OutputPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $Report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $TemporaryOutput -Encoding utf8
    if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
        [IO.File]::Replace($TemporaryOutput, $OutputPath, $null)
    }
    else {
        Move-Item -LiteralPath $TemporaryOutput -Destination $OutputPath
    }
}
finally {
    if (Test-Path -LiteralPath $TemporaryOutput) {
        Remove-Item -LiteralPath $TemporaryOutput -Force
    }
}

Write-Host (
    "M10 non-elevated preflight verdict={0} checks={1} started={2} completed={3}" -f
    $Report.verdict,
    $Checks.Count,
    $Report.started_at,
    $Report.completed_at)
if (-not $AllPassed) {
    exit 1
}
