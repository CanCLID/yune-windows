param(
    [switch]$RunPostRestartLiveVerification,
    [string]$LiveCandidateManifest = "",
    [string]$LiveVerificationResultPath = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$DeployScript = Join-Path $RepoRoot "tools\dev\deploy-m10-frozen-candidate.ps1"
$VerifyScript = Join-Path $RepoRoot "tools\dev\verify-m10-frozen-candidate.ps1"
foreach ($RequiredScript in @($DeployScript, $VerifyScript)) {
    if (-not (Test-Path -LiteralPath $RequiredScript -PathType Leaf)) {
        throw "missing M10 frozen-candidate helper: $RequiredScript"
    }
}

$Source = Get-Content -Raw -LiteralPath $DeployScript
$VerifySource = Get-Content -Raw -LiteralPath $VerifyScript
$ContractSource = Get-Content -Raw -LiteralPath $PSCommandPath

foreach ($Required in @(
        'RunPostRestartLiveVerification',
        'opt_in_required_after_restart',
        'LiveCandidateManifest',
        'LiveVerificationResultPath'
    )) {
    if ($ContractSource -notmatch [regex]::Escape($Required)) {
        throw "M10 deploy contract is missing static/live split marker: $Required"
    }
}
$DisallowedAncientBoundary = "2000" + "-01-01T00:00"
if ($ContractSource.Contains($DisallowedAncientBoundary)) {
    throw "M10 deploy contract must not use an ancient timestamp as installed proof"
}

foreach ($Required in @(
        'ExpectedSourceCommit',
        'status.*--porcelain.*--untracked-files=all',
        'ValidateSet\("DryRun", "StageOnly", "Deploy"\)',
        'ApprovedMachineStateChange',
        'ApprovalNote',
        'AllowLoadedTsfHolders',
        'DurableManifestPath',
        'docs\\evidence\\m10\\machine-state\\frozen-candidate\.json',
        'durable candidate manifest must be outside the OS temp tree',
        'Write-M10AtomicResultFile',
        '\[System.IO.File\]::Replace',
        'build-tsf-shell\.ps1',
        'invocation_count = 1',
        'Get-FileHash -Algorithm SHA256',
        'Get-M10PeSizeOfImage',
        'tsf_pe_size_of_image',
        'module_memory_size',
        'PendingFileRenameOperations',
        'session_restart_required',
        'live_test_allowed_without_restart',
        'Move-Item -LiteralPath \$Destination',
        'rollback_attempted',
        'Set-M10FailedDeploymentSessionState',
        'post_rollback_preflight',
        'deploying_restart_required',
        'rollback_complete_scope = "filesystem_only"',
        'RefreshedInstalledRimeHash',
        'installed rime.dll changed during the candidate build',
        'DryRun is read-only'
    )) {
    if ($Source -notmatch $Required) {
        throw "M10 frozen-candidate helper is missing required safety marker: $Required"
    }
}

foreach ($Forbidden in @(
        '(?i)\bRemove-Item\b',
        '(?i)\bStop-Process\b',
        '(?i)\.Kill\s*\(',
        '(?i)\btaskkill\b',
        '(?i)\bshutdown(?:\.exe)?\b',
        '(?i)\bMoveFileEx',
        '(?i)\bregsvr32\b',
        '(?i)install-yune-windows-ime\.ps1',
        '(?i)uninstall-yune-windows-ime\.ps1',
        '(?i)\bSet-ItemProperty\b',
        '(?i)\bNew-ItemProperty\b',
        '(?is)Start-Process.*-Verb\s+RunAs'
    )) {
    if ($Source -match $Forbidden) {
        throw "M10 frozen-candidate helper contains forbidden mutation: $Forbidden"
    }
}

foreach ($Required in @(
        'CandidateManifest',
        'ReadAllBytes',
        'ManifestSha256',
        'Get-FileHash -Algorithm SHA256',
        'tsf_pe_size_of_image',
        'ModuleMemorySize',
        'matches_candidate_image_size',
        'PendingFileRenameOperations',
        'YuneWindowsProfileTool',
        '--state',
        'HKEY_CLASSES_ROOT\CLSID',
        'InprocServer32',
        'privacy_note',
        'source_post_build_verified',
        'package_post_build_verified',
        'Assert-M10VerifyManifestAdmission',
        'Assert-M10VerifyDurableManifestPath',
        'Test-M10VerifyExactBoolean',
        'deployed_restart_required',
        'rollback_attempted',
        'rollback_complete',
        'deployment_completed_at_valid',
        'all_started_strictly_after_deployment',
        'all_use_current_installed_path',
        'exactly_one_running_installed_server',
        'install_root_old_or_aside_path',
        'Get-M10VerifyNamedProcesses',
        'total_processes_considered',
        'module_enumeration_succeeded',
        'module_enumeration_failure_count',
        'coverage_incomplete',
        'enumeration_failures',
        'm10_frozen_candidate_post_restart_verify'
    )) {
    if ($VerifySource -notmatch [regex]::Escape($Required)) {
        throw "M10 post-restart verifier is missing required marker: $Required"
    }
}

foreach ($Forbidden in @(
        '(?i)\bCopy-Item\b',
        '(?i)\bMove-Item\b',
        '(?i)\bRemove-Item\b',
        '(?i)\bStop-Process\b',
        '(?i)\bStart-Process\b',
        '(?i)\bSet-ItemProperty\b',
        '(?i)\bNew-ItemProperty\b',
        '(?i)\bregsvr32\b',
        '(?i)build-tsf-shell\.ps1',
        '(?i)install-yune-windows-ime\.ps1',
        '(?i)uninstall-yune-windows-ime\.ps1'
    )) {
    if ($VerifySource -match $Forbidden) {
        throw "M10 post-restart verifier must stay read-only: $Forbidden"
    }
}

$BuildInvocations = [regex]::Matches(
    $Source,
    '(?m)^\$BuildOutput = @\(& \$BuildScript ').Count
if ($BuildInvocations -ne 1) {
    throw "M10 frozen-candidate helper must invoke the shell build exactly once; found $BuildInvocations"
}

$DeployOrderStart = $Source.IndexOf(
    '# The order is protocol-significant',
    [System.StringComparison]::Ordinal)
if ($DeployOrderStart -lt 0) {
    throw "M10 frozen-candidate helper is missing the protocol-order deployment block"
}
$DeployOrderSource = $Source.Substring($DeployOrderStart)
$OrderMarkers = [ordered]@{
    server = '-Name "server"'
    tsf = '-Name "tsf"'
    settings = '-Name "settings"'
    profile = '-Name "profile"'
    skins = 'Install-M10CandidateSkins'
}
$PreviousIndex = -1
foreach ($Entry in $OrderMarkers.GetEnumerator()) {
    $Index = $DeployOrderSource.IndexOf(
        $Entry.Value,
        [System.StringComparison]::Ordinal)
    if ($Index -lt 0 -or $Index -le $PreviousIndex) {
        throw "M10 frozen-candidate deployment order is not server -> TSF -> settings -> profile -> skins at $($Entry.Key)"
    }
    $PreviousIndex = $Index
}

$TempRoot = Join-Path $env:TEMP (
    "yune-windows\m10-frozen-dry-run-contract-{0}-{1}" -f
    $PID,
    [Guid]::NewGuid().ToString("N").Substring(0, 8))
$FakeInstall = Join-Path $TempRoot "install"
New-Item -Path $FakeInstall -ItemType Directory -Force | Out-Null
$Marker = Join-Path $FakeInstall "must-remain.txt"
Set-Content -LiteralPath $Marker -Value "unchanged" -Encoding utf8
$Before = @(Get-ChildItem -LiteralPath $FakeInstall -Force | Select-Object Name, Length)

try {
    $Head = (& git -C $RepoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Head)) {
        throw "could not resolve repository HEAD for dry-run contract"
    }
    $DryRunOutput = @(& $DeployScript `
            -Mode DryRun `
            -ExpectedSourceCommit $Head `
            -InstallDir $FakeInstall)
    $DryRunText = ($DryRunOutput | Out-String).Trim()
    $DryRun = $DryRunText | ConvertFrom-Json

    if ($DryRun.mode -ne "DryRun" -or
        $DryRun.build.performed -ne $false -or
        $DryRun.build.invocation_count -ne 0 -or
        $DryRun.deployment.performed -ne $false) {
        throw "dry-run unexpectedly built or deployed the M10 candidate"
    }
    if ($DryRun.source.actual_commit -ne $Head -or
        $DryRun.source.expected_commit -ne $Head) {
        throw "dry-run did not preserve pinned source provenance"
    }
    $ExpectedOrder = @("server", "tsf", "settings", "profile", "skins")
    if ((@($DryRun.deployment.intended_order) -join ",") -ne
        ($ExpectedOrder -join ",")) {
        throw "dry-run did not report the required deployment order"
    }

    $After = @(Get-ChildItem -LiteralPath $FakeInstall -Force | Select-Object Name, Length)
    if (($Before | ConvertTo-Json -Compress) -ne
        ($After | ConvertTo-Json -Compress)) {
        throw "dry-run changed the fake install directory"
    }
    if ((Get-Content -Raw -LiteralPath $Marker).Trim() -ne "unchanged") {
        throw "dry-run changed the fake install marker"
    }

    # Exercise the exact rollback function with the state left behind when the
    # initial destination-to-aside Move-Item fails. The original destination
    # must not be moved to a failed-candidate path or otherwise changed.
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $DeployScript,
        [ref]$Tokens,
        [ref]$ParseErrors)
    if (@($ParseErrors).Count -gt 0) {
        throw "could not parse deploy helper for rollback fault contract"
    }
    foreach ($FunctionName in @(
            "Write-M10AtomicResultFile",
            "New-M10AsidePath",
            "Restore-M10DeploymentOperations",
            "Set-M10FailedDeploymentSessionState"
        )) {
        $FunctionAst = $Ast.Find({
                param($Node)
                $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $Node.Name -eq $FunctionName
            }, $true)
        if (-not $FunctionAst) {
            throw "missing rollback function for fault contract: $FunctionName"
        }
        Invoke-Expression $FunctionAst.Extent.Text
    }

    $AtomicManifestPath = Join-Path $TempRoot "atomic-manifest.json"
    Write-M10AtomicResultFile `
        -Result ([ordered]@{ status = "deploying_restart_required" }) `
        -Path $AtomicManifestPath
    Write-M10AtomicResultFile `
        -Result ([ordered]@{ status = "deployed_restart_required" }) `
        -Path $AtomicManifestPath
    $AtomicManifest = Get-Content -Raw -LiteralPath $AtomicManifestPath |
        ConvertFrom-Json
    if ($AtomicManifest.status -ne "deployed_restart_required" -or
        @(Get-ChildItem `
                -LiteralPath $TempRoot `
                -Filter ".atomic-manifest.json.*.tmp*" `
                -ErrorAction SilentlyContinue).Count -ne 0) {
        throw "atomic manifest refresh did not leave exactly one complete current JSON file"
    }

    $FaultOriginal = Join-Path $FakeInstall "initial-move-failure.dll"
    Set-Content -LiteralPath $FaultOriginal -Value "original-bytes" -Encoding utf8
    $OriginalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $FaultOriginal).Hash
    $FaultOperations = [System.Collections.Generic.List[object]]::new()
    $FaultOperations.Add([ordered]@{
            name = "initial_move_failure"
            kind = "file"
            destination = $FaultOriginal
            aside_path = "$FaultOriginal.never-created"
            aside_created = $false
            candidate_installed = $false
            rollback_attempted = $false
            rollback_succeeded = $false
            failed_candidate_path = ""
        }) | Out-Null
    Restore-M10DeploymentOperations `
        -Operations $FaultOperations `
        -Tag "contract"
    if (-not (Test-Path -LiteralPath $FaultOriginal -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $FaultOriginal).Hash -ne
        $OriginalHash) {
        throw "rollback changed the original after an initial move failure"
    }
    if (-not $FaultOperations[0].rollback_succeeded -or
        -not [string]::IsNullOrWhiteSpace(
            [string]$FaultOperations[0].failed_candidate_path)) {
        throw "rollback misclassified the initial move failure"
    }
    if (@(Get-ChildItem `
            -LiteralPath $FakeInstall `
            -Filter "initial-move-failure.dll.m10-failed-*" `
            -ErrorAction SilentlyContinue).Count -ne 0) {
        throw "rollback displaced the untouched original after an initial move failure"
    }

    $PartialFailureResult = [ordered]@{
        status = "staged"
        deployment = [ordered]@{
            session_restart_required = $false
            live_test_allowed_without_restart = $true
        }
    }
    $PartialFailureOperations = [System.Collections.Generic.List[object]]::new()
    $PartialFailureOperations.Add([ordered]@{
            name = "server"
            aside_created = $true
            candidate_installed = $true
            rollback_attempted = $true
            rollback_succeeded = $true
        }) | Out-Null
    Set-M10FailedDeploymentSessionState `
        -Result $PartialFailureResult `
        -Operations $PartialFailureOperations
    if (-not $PartialFailureResult.deployment.session_restart_required -or
        $PartialFailureResult.deployment.live_test_allowed_without_restart -or
        $PartialFailureResult.status -ne "deploy_failed") {
        throw "partial deployment rollback incorrectly claimed the session was live-safe"
    }

    $VerifyTokens = $null
    $VerifyParseErrors = $null
    $VerifyAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $VerifyScript,
        [ref]$VerifyTokens,
        [ref]$VerifyParseErrors)
    if (@($VerifyParseErrors).Count -gt 0) {
        throw "could not parse post-restart verifier for boundary contracts"
    }
    foreach ($FunctionName in @(
            "Resolve-M10VerifyFullPath",
            "Test-M10VerifyPathUnderRoot",
            "Get-M10VerifyStartState",
            "Test-M10VerifyProperty",
            "Test-M10VerifyExactBoolean",
            "Assert-M10VerifyManifestAdmission",
            "Assert-M10VerifyDurableManifestPath"
        )) {
        $FunctionAst = $VerifyAst.Find({
                param($Node)
                $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $Node.Name -eq $FunctionName
            }, $true)
        if (-not $FunctionAst) {
            throw "missing verifier boundary function: $FunctionName"
        }
        Invoke-Expression $FunctionAst.Extent.Text
    }
    # Synthetic unit-only timestamps exercise strict comparison semantics.
    # They are never presented as post-restart or installed temporal proof.
    $SyntheticDeploymentBoundary = [DateTimeOffset]::Parse(
        "2026-07-10T12:00:00Z",
        [Globalization.CultureInfo]::InvariantCulture)
    $UnknownStart = Get-M10VerifyStartState `
        -StartedAt "" `
        -DeploymentCompletedAt $SyntheticDeploymentBoundary
    $OldStart = Get-M10VerifyStartState `
        -StartedAt "2026-07-10T11:59:59Z" `
        -DeploymentCompletedAt $SyntheticDeploymentBoundary
    $EqualStart = Get-M10VerifyStartState `
        -StartedAt "2026-07-10T12:00:00Z" `
        -DeploymentCompletedAt $SyntheticDeploymentBoundary
    $NewStart = Get-M10VerifyStartState `
        -StartedAt "2026-07-10T12:00:00.001Z" `
        -DeploymentCompletedAt $SyntheticDeploymentBoundary
    if ($UnknownStart.start_time_known -or
        $UnknownStart.started_strictly_after_deployment -or
        -not $OldStart.start_time_known -or
        $OldStart.started_strictly_after_deployment -or
        -not $EqualStart.start_time_known -or
        $EqualStart.started_strictly_after_deployment -or
        -not $NewStart.start_time_known -or
        -not $NewStart.started_strictly_after_deployment) {
        throw "post-restart verifier does not fail closed at the strict deployment-time boundary"
    }

    $SyntheticDurablePath = Join-Path $RepoRoot (
        "docs\evidence\m10\machine-state\synthetic-never-written.json")
    $SyntheticAdmissibleManifest = [ordered]@{
        schema_version = 1
        operation = "m10_frozen_candidate"
        status = "deployed_restart_required"
        source = [ordered]@{
            expected_commit = "1111111111111111111111111111111111111111"
            actual_commit = "1111111111111111111111111111111111111111"
            clean = $true
            post_build_verified = $true
        }
        package = [ordered]@{ post_build_verified = $true }
        build = [ordered]@{ performed = $true }
        manifest = [ordered]@{
            durable_path = $SyntheticDurablePath
            durable_outside_os_temp = $true
            atomic_refresh = $true
        }
        deployment = [ordered]@{
            performed = $true
            error = ""
            rollback_attempted = $false
            rollback_complete = $false
            completed_at = "2026-07-10T12:00:00Z"
        }
    } | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    Assert-M10VerifyManifestAdmission `
        -Manifest $SyntheticAdmissibleManifest `
        -DeploymentCompletedAtValid $true
    Assert-M10VerifyDurableManifestPath `
        -Manifest $SyntheticAdmissibleManifest `
        -ManifestPath $SyntheticDurablePath
    $SyntheticTempManifest = $SyntheticAdmissibleManifest |
        ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $SyntheticTempManifest.manifest.durable_path =
        (Join-Path $TempRoot "synthetic-manifest.json")
    $RejectedTempManifest = $false
    try {
        Assert-M10VerifyDurableManifestPath `
            -Manifest $SyntheticTempManifest `
            -ManifestPath $SyntheticTempManifest.manifest.durable_path
    }
    catch {
        $RejectedTempManifest = $true
    }
    if (-not $RejectedTempManifest) {
        throw "post-restart verifier admitted a synthetic OS-temp manifest"
    }

    foreach ($RejectedCase in @(
            [ordered]@{ field = "status"; value = "deploy_failed" },
            [ordered]@{ field = "error"; value = "fault" },
            [ordered]@{ field = "rollback_attempted"; value = $true },
            [ordered]@{ field = "rollback_attempted"; value = "false" },
            [ordered]@{ field = "rollback_complete"; value = $true },
            [ordered]@{ field = "performed"; value = $false }
        )) {
        $RejectedManifest = $SyntheticAdmissibleManifest |
            ConvertTo-Json -Depth 8 | ConvertFrom-Json
        if ($RejectedCase.field -eq "status") {
            $RejectedManifest.status = $RejectedCase.value
        }
        else {
            $RejectedManifest.deployment.($RejectedCase.field) =
                $RejectedCase.value
        }
        $Rejected = $false
        try {
            Assert-M10VerifyManifestAdmission `
                -Manifest $RejectedManifest `
                -DeploymentCompletedAtValid $true
        }
        catch {
            $Rejected = $true
        }
        if (-not $Rejected) {
            throw "post-restart verifier admitted synthetic invalid deployment field: $($RejectedCase.field)"
        }
    }
    $PathRoot = Join-Path $TempRoot "path-root"
    if (-not (Test-M10VerifyPathUnderRoot `
            -Path (Join-Path $PathRoot "YuneWindowsTSF.dll.m10-old-test") `
            -Root $PathRoot) -or
        (Test-M10VerifyPathUnderRoot `
            -Path (Join-Path $TempRoot "outside\YuneWindowsTSF.dll") `
            -Root $PathRoot)) {
        throw "post-restart verifier does not classify install-root aside paths safely"
    }

}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

$LiveLane = [ordered]@{
    operation = "m10_frozen_candidate_post_restart_live_lane"
    status = "skipped"
    reason = "opt_in_required_after_restart"
    candidate_manifest = ""
    verification_result_path = ""
}
if ($RunPostRestartLiveVerification) {
    if ([string]::IsNullOrWhiteSpace($LiveCandidateManifest) -or
        -not (Test-Path -LiteralPath $LiveCandidateManifest -PathType Leaf)) {
        throw "post-restart live verification requires -LiveCandidateManifest"
    }
    if ([string]::IsNullOrWhiteSpace($LiveVerificationResultPath)) {
        throw "post-restart live verification requires -LiveVerificationResultPath"
    }
    $LiveManifestPath = [System.IO.Path]::GetFullPath($LiveCandidateManifest)
    $LiveResultPath = [System.IO.Path]::GetFullPath($LiveVerificationResultPath)
    $TempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd("\")
    if ($LiveResultPath.StartsWith(
            $TempPath + "\",
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "post-restart live verification result must be outside the OS temp tree"
    }
    $VerifyOutput = @(& $VerifyScript `
            -CandidateManifest $LiveManifestPath)
    $VerifyText = ($VerifyOutput | Out-String).Trim()
    $VerifyResult = $VerifyText | ConvertFrom-Json
    if ($VerifyResult.pass -ne $true -or
        $VerifyResult.operation -ne
            "m10_frozen_candidate_post_restart_verify" -or
        -not $VerifyResult.holders.coverage_complete) {
        throw "opt-in post-restart installed verification did not pass"
    }
    $LiveResultParent = Split-Path -Parent $LiveResultPath
    New-Item -Path $LiveResultParent -ItemType Directory -Force | Out-Null
    $VerifyText | Out-File -LiteralPath $LiveResultPath -Encoding utf8
    $LiveLane.status = "passed"
    $LiveLane.reason = ""
    $LiveLane.candidate_manifest = $LiveManifestPath
    $LiveLane.verification_result_path = $LiveResultPath
}

Write-Host "M10 frozen-candidate static deploy, rollback, dry-run, and verifier-admission contract passed."
Write-Output ($LiveLane | ConvertTo-Json -Depth 4)
