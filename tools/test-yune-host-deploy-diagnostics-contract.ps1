$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HostSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\host\yune_host_smoke.cpp")

function Require-SourceText([string]$Pattern, [string]$Description) {
    if ($HostSource -notmatch $Pattern) {
        throw "host smoke source is missing deploy diagnostic contract: $Description"
    }
}

Require-SourceText "struct\s+DeployDiagnostics" "deploy diagnostic result struct"
Require-SourceText "deploy_config_file\([^;]+default\.yaml[^;]+config_version" "default config deploy probe"
Require-SourceText 'args\.schema\s*\+\s*"\.schema\.yaml"' "selected schema file construction"
Require-SourceText "deploy_schema\(schema_file\.c_str\(\)\)" "selected schema deploy probe"
Require-SourceText 'workspace_update:\s*"\s*\+\s*args\.schema' "selected schema workspace-update task"
Require-SourceText "run_task\(workspace_update_task\.c_str\(\)\)" "selected schema workspace-update probe"
Require-SourceText "WriteFailureResult" "failure result writer"
Require-SourceText "failure_stage" "failure stage JSON field"
Require-SourceText "deploy_diagnostics" "deploy diagnostics JSON object"

Write-Host "Yune host smoke records staged deploy diagnostics on failure."
