param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OrchestratorPath = Join-Path $RepoRoot "tools\run-p2-win01-live-smoke.ps1"
if (-not (Test-Path -LiteralPath $OrchestratorPath)) {
    throw "missing live smoke orchestrator: $OrchestratorPath"
}

$Source = Get-Content -Raw -LiteralPath $OrchestratorPath
if ($Source -notmatch '\$ApprovalDate\s*=') {
    throw "live smoke orchestrator must keep the current-session approval timestamp for diagnostics validation."
}
if ($Source -notmatch 'Assert-DiagnosticsBundleEvidence\s+-Path\s+\$DiagnosticsBundleText\s+-OutputDir\s+\$DiagnosticsDir\s+-NotBefore\s+\$ApprovalDate') {
    throw "live smoke orchestrator must reject diagnostics bundles generated before the current-session approval."
}
if ($Source -notmatch 'Assert-DiagnosticsBundleEvidence\s+-Path\s+\$DiagnosticsBundleText\s+-OutputDir\s+\$DiagnosticsDir\s+-NotBefore\s+\$ApprovalDate\s+-PreStatePath\s+\$DiagnosticsPreStatePath') {
    throw "live smoke orchestrator must reject diagnostics bundles generated before diagnostics-pre-state evidence."
}

$ParseErrors = $null
$Tokens = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $OrchestratorPath,
    [ref]$Tokens,
    [ref]$ParseErrors)
if (($null -ne $ParseErrors) -and ($ParseErrors.Count -gt 0)) {
    throw "could not parse live smoke orchestrator: $($ParseErrors[0].Message)"
}

$FunctionAst = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $Node.Name -eq "Assert-DiagnosticsBundleEvidence"
    }, $true)
if ($null -eq $FunctionAst) {
    throw "live smoke orchestrator is missing Assert-DiagnosticsBundleEvidence"
}
Invoke-Expression $FunctionAst.Extent.Text

$OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-diagnostics-bundle-validator-test"
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

function New-DiagnosticsBundleFixture {
    param(
        [string]$Name,
        [hashtable]$Manifest,
        [hashtable]$Logs = @{}
    )

    $BundleRoot = Join-Path $OutputDir $Name
    $ZipPath = Join-Path $OutputDir "$Name.zip"
    New-Item -ItemType Directory -Force $BundleRoot | Out-Null
    $Manifest | ConvertTo-Json -Depth 8 |
        Out-File -LiteralPath (Join-Path $BundleRoot "manifest.json") -Encoding utf8

    if ($Logs.Count -gt 0) {
        $LogDir = Join-Path $BundleRoot "logs"
        New-Item -ItemType Directory -Force $LogDir | Out-Null
        foreach ($LogName in $Logs.Keys) {
            $Logs[$LogName] | Out-File -LiteralPath (Join-Path $LogDir $LogName) -Encoding utf8
        }
    }

    Compress-Archive -Path (Join-Path $BundleRoot "*") -DestinationPath $ZipPath -Force
    return $ZipPath
}

function New-DiagnosticsPreStateFixture {
    param(
        [string]$Name,
        [string]$CapturedAt
    )

    $Path = Join-Path $OutputDir "$Name.json"
    [ordered]@{
        captured_at = $CapturedAt
    } | ConvertTo-Json -Depth 4 |
        Out-File -LiteralPath $Path -Encoding utf8
    return $Path
}

function Assert-BundleRejected {
    param(
        [string]$Path,
        [string]$MessagePattern,
        [string]$Context,
        [System.DateTimeOffset]$NotBefore = [System.DateTimeOffset]::MinValue,
        [string]$PreStatePath = ""
    )

    try {
        $Arguments = @{
            Path = $Path
            OutputDir = $OutputDir
        }
        if ($NotBefore -ne [System.DateTimeOffset]::MinValue) {
            $Arguments.NotBefore = $NotBefore
        }
        if (-not [string]::IsNullOrWhiteSpace($PreStatePath)) {
            $Arguments.PreStatePath = $PreStatePath
        }
        Assert-DiagnosticsBundleEvidence @Arguments
    }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw "$Context rejected with unclear message: $($_.Exception.Message)"
        }
        return
    }

    throw "$Context was accepted"
}

$GeneratedAt = "2026-06-26T18:20:00.0000000-07:00"
$ApprovalNotBefore = [System.DateTimeOffset]::Parse(
    $GeneratedAt,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::RoundtripKind)
$ValidLogText = @(
    "event=candidate_update sequence=1 candidate_count=5",
    "event=commit_text sequence=2 candidate_count=5"
) -join "`n"
$ValidDiagnosticsPreStatePath = New-DiagnosticsPreStateFixture `
    -Name "valid-diagnostics-pre-state" `
    -CapturedAt "2026-06-26T18:19:59.0000000-07:00"
$LateDiagnosticsPreStatePath = New-DiagnosticsPreStateFixture `
    -Name "late-diagnostics-pre-state" `
    -CapturedAt "2026-06-26T18:20:01.0000000-07:00"

$MissingMetadataBundle = New-DiagnosticsBundleFixture `
    -Name "missing-diagnostics-log-metadata" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
    })
Assert-BundleRejected `
    -Path $MissingMetadataBundle `
    -MessagePattern "diagnostics_logs" `
    -Context "bundle without diagnostics log metadata"

$ZeroLogBundle = New-DiagnosticsBundleFixture `
    -Name "zero-diagnostics-logs" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 0
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    })
Assert-BundleRejected `
    -Path $ZeroLogBundle `
    -MessagePattern "file_count|positive" `
    -Context "bundle with zero diagnostics log count"

$StringBooleanBundle = New-DiagnosticsBundleFixture `
    -Name "string-diagnostics-log-booleans" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = "true"
            file_count = 1
            directory = "logs"
            typed_content_logs = "false"
            structural_events_only = "true"
        }
    }) `
    -Logs @{
        "tsf-events.log" = $ValidLogText
    }
Assert-BundleRejected `
    -Path $StringBooleanBundle `
    -MessagePattern "typed JSON boolean|boolean" `
    -Context "bundle with string-typed diagnostics log booleans"

$MismatchedLogCountBundle = New-DiagnosticsBundleFixture `
    -Name "mismatched-diagnostics-log-count" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 2
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = $ValidLogText
    }
Assert-BundleRejected `
    -Path $MismatchedLogCountBundle `
    -MessagePattern "file_count|log file count" `
    -Context "bundle with mismatched diagnostics log count"

$MissingCandidateUpdateBundle = New-DiagnosticsBundleFixture `
    -Name "missing-candidate-update-event" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = "event=commit_text sequence=2 candidate_count=5"
    }
Assert-BundleRejected `
    -Path $MissingCandidateUpdateBundle `
    -MessagePattern "candidate_update" `
    -Context "bundle without exact candidate_update event"

$MissingCommitBundle = New-DiagnosticsBundleFixture `
    -Name "missing-commit-event" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = "event=candidate_update sequence=1 candidate_count=5`nevent=commit_text_failed sequence=2 candidate_count=5"
    }
Assert-BundleRejected `
    -Path $MissingCommitBundle `
    -MessagePattern "commit_text" `
    -Context "bundle without exact commit_text event"

$ZeroCandidateCountBundle = New-DiagnosticsBundleFixture `
    -Name "zero-candidate-count-event" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = "event=candidate_update sequence=1 candidate_count=0`nevent=commit_text sequence=2 candidate_count=5"
    }
Assert-BundleRejected `
    -Path $ZeroCandidateCountBundle `
    -MessagePattern "candidate_count|candidate_update" `
    -Context "bundle without positive candidate_update candidate_count"

$CandidateWindowFailureBundle = New-DiagnosticsBundleFixture `
    -Name "candidate-window-failure-event" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = "event=candidate_update sequence=1 candidate_count=5`nevent=candidate_window_failed sequence=2 candidate_count=5`nevent=commit_text sequence=3 candidate_count=5"
    }
Assert-BundleRejected `
    -Path $CandidateWindowFailureBundle `
    -MessagePattern "candidate_window_failed" `
    -Context "bundle with candidate_window_failed event"

$TypedContentBundle = New-DiagnosticsBundleFixture `
    -Name "typed-content-event" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = "event=candidate_update sequence=1 candidate_count=5 raw_input=ngohaig`nevent=commit_text sequence=2 candidate_count=5"
    }
Assert-BundleRejected `
    -Path $TypedContentBundle `
    -MessagePattern "typed content" `
    -Context "bundle with typed-content leakage"

$PreApprovalTimestampBundle = New-DiagnosticsBundleFixture `
    -Name "pre-approval-generated-at" `
    -Manifest ([ordered]@{
        generated_at = "2026-06-26T18:19:59.0000000-07:00"
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = $ValidLogText
    }
Assert-BundleRejected `
    -Path $PreApprovalTimestampBundle `
    -MessagePattern "generated_at|approval|current-session" `
    -Context "bundle generated before approval" `
    -NotBefore $ApprovalNotBefore

$ValidBundle = New-DiagnosticsBundleFixture `
    -Name "valid-diagnostics-logs" `
    -Manifest ([ordered]@{
        generated_at = $GeneratedAt
        diagnostics_logs = [ordered]@{
            included = $true
            file_count = 1
            directory = "logs"
            typed_content_logs = $false
            structural_events_only = $true
        }
    }) `
    -Logs @{
        "tsf-events.log" = $ValidLogText
    }
Assert-BundleRejected `
    -Path $ValidBundle `
    -MessagePattern "diagnostics-pre-state|captured_at|manifest" `
    -Context "bundle generated before diagnostics pre-state" `
    -NotBefore $ApprovalNotBefore `
    -PreStatePath $LateDiagnosticsPreStatePath

Assert-DiagnosticsBundleEvidence `
    -Path $ValidBundle `
    -OutputDir $OutputDir `
    -NotBefore $ApprovalNotBefore `
    -PreStatePath $ValidDiagnosticsPreStatePath

Write-Host "Live smoke diagnostics bundle validator rejects weak log metadata, weak structural logs, and accepts a structural-log bundle."
