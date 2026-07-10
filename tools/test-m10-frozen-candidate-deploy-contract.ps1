param()

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

foreach ($Required in @(
        'ExpectedSourceCommit',
        'status.*--porcelain.*--untracked-files=all',
        'ValidateSet\("DryRun", "StageOnly", "Deploy"\)',
        'ApprovedMachineStateChange',
        'ApprovalNote',
        'AllowLoadedTsfHolders',
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
        'deployment_completed_at_valid',
        'all_started_strictly_after_deployment',
        'all_use_current_installed_path',
        'exactly_one_running_installed_server',
        'install_root_old_or_aside_path',
        'Get-M10VerifyNamedProcesses',
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
            "Get-M10VerifyStartState"
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
    $DeploymentBoundary = [DateTimeOffset]::Parse(
        "2026-07-10T12:00:00Z",
        [Globalization.CultureInfo]::InvariantCulture)
    $UnknownStart = Get-M10VerifyStartState `
        -StartedAt "" `
        -DeploymentCompletedAt $DeploymentBoundary
    $OldStart = Get-M10VerifyStartState `
        -StartedAt "2026-07-10T11:59:59Z" `
        -DeploymentCompletedAt $DeploymentBoundary
    $EqualStart = Get-M10VerifyStartState `
        -StartedAt "2026-07-10T12:00:00Z" `
        -DeploymentCompletedAt $DeploymentBoundary
    $NewStart = Get-M10VerifyStartState `
        -StartedAt "2026-07-10T12:00:00.001Z" `
        -DeploymentCompletedAt $DeploymentBoundary
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
    $PathRoot = Join-Path $TempRoot "path-root"
    if (-not (Test-M10VerifyPathUnderRoot `
            -Path (Join-Path $PathRoot "YuneWindowsTSF.dll.m10-old-test") `
            -Root $PathRoot) -or
        (Test-M10VerifyPathUnderRoot `
            -Path (Join-Path $TempRoot "outside\YuneWindowsTSF.dll") `
            -Root $PathRoot)) {
        throw "post-restart verifier does not classify install-root aside paths safely"
    }

    # When a registered local install is available, exercise the read-only
    # verifier end to end against a manifest synthesized from that exact
    # installed artifact set. Portable source-only environments skip this lane.
    $RealInstall = Join-Path $env:LOCALAPPDATA "Yune\WindowsIme"
    $RealPaths = [ordered]@{
        server = Join-Path $RealInstall "YuneWindowsServer.exe"
        tsf = Join-Path $RealInstall "YuneWindowsTSF.dll"
        settings = Join-Path $RealInstall "YuneWindowsSettings.exe"
        profile = Join-Path $RealInstall "YuneWindowsProfileTool.exe"
        default_skin = Join-Path $RealInstall "skins\default\theme.json"
        rime = Join-Path $RealInstall "rime.dll"
    }
    $RealInstallReady = $true
    foreach ($RealPath in $RealPaths.Values) {
        if (-not (Test-Path -LiteralPath $RealPath -PathType Leaf)) {
            $RealInstallReady = $false
            break
        }
    }
    if ($RealInstallReady) {
        $ProfileText = (& $RealPaths.profile --state 2>&1 | Out-String).Trim()
        $ProfileState = if ($LASTEXITCODE -eq 0) {
            try { $ProfileText | ConvertFrom-Json } catch { $null }
        }
        else {
            $null
        }
        if ($ProfileState -and
            [bool]$ProfileState.registered -and
            [bool]$ProfileState.active) {
            $PeFunction = $VerifyAst.Find({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $Node.Name -eq "Get-M10VerifyPeSizeOfImage"
                }, $true)
            if (-not $PeFunction -or @($VerifyParseErrors).Count -gt 0) {
                throw "could not load verifier PE parser for installed-state contract"
            }
            Invoke-Expression $PeFunction.Extent.Text

            $InstalledArtifacts = @()
            foreach ($Name in @("server", "tsf", "settings", "profile", "default_skin")) {
                $Path = [string]$RealPaths[$Name]
                $InstalledArtifacts += [ordered]@{
                    name = $Name
                    path = $Path
                    length = [long](Get-Item -LiteralPath $Path).Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
                }
            }
            $InstalledManifest = [ordered]@{
                schema_version = 1
                operation = "m10_frozen_candidate"
                source = [ordered]@{
                    expected_commit = "1111111111111111111111111111111111111111"
                    actual_commit = "1111111111111111111111111111111111111111"
                    clean = $true
                    post_build_verified = $true
                }
                package = [ordered]@{
                    post_build_verified = $true
                    rime = [ordered]@{
                        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $RealPaths.rime).Hash
                    }
                }
                build = [ordered]@{
                    performed = $true
                    output_dir = "installed-contract-fixture"
                    artifacts = $InstalledArtifacts
                    tsf_pe_size_of_image =
                        Get-M10VerifyPeSizeOfImage -Path $RealPaths.tsf
                }
                deployment = [ordered]@{
                    performed = $true
                    started_at = "2000-01-01T00:00:00Z"
                    completed_at = "2000-01-01T00:00:01Z"
                }
            }
            $InstalledManifestPath = Join-Path $TempRoot "installed-candidate.json"
            $InstalledManifest | ConvertTo-Json -Depth 10 |
                Out-File -LiteralPath $InstalledManifestPath -Encoding utf8
            $VerifyOutput = @(& $VerifyScript `
                    -CandidateManifest $InstalledManifestPath `
                    -InstallDir $RealInstall `
                    -AllowNoHolders)
            $VerifyResult = (($VerifyOutput | Out-String).Trim() | ConvertFrom-Json)
            if ($VerifyResult.pass -ne $true -or
                $VerifyResult.operation -ne
                    "m10_frozen_candidate_post_restart_verify" -or
                -not $VerifyResult.candidate.deployment_completed_at_valid -or
                -not $VerifyResult.holders.all_start_times_known -or
                -not $VerifyResult.holders.all_started_strictly_after_deployment -or
                -not $VerifyResult.holders.all_use_current_installed_path -or
                -not $VerifyResult.installed_processes.server.exactly_one_running_installed_server -or
                -not $VerifyResult.installed_processes.server.all_installed_started_strictly_after_deployment -or
                -not $VerifyResult.installed_processes.settings.all_installed_started_strictly_after_deployment) {
                throw "read-only installed-state verifier did not pass its exact-artifact fixture"
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

Write-Host "M10 frozen-candidate deploy, rollback, dry-run, and post-restart verification contract passed."
