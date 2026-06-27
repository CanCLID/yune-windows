$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HostSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\host\yune_host_smoke.cpp")
$ServerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "src\server\yune_windows_server.cpp")

function Require-Text([string]$Source, [string]$Pattern, [string]$Description) {
    if ($Source -notmatch $Pattern) {
        throw "missing Yune deploy artifact fallback contract: $Description"
    }
}

foreach ($Source in @($HostSource, $ServerSource)) {
    Require-Text $Source "SelectedSchemaArtifactsExist" "selected schema artifact readiness check"
    Require-Text $Source "artifact_fallback" "deploy diagnostic artifact fallback field"
    Require-Text $Source "workspace_update_schema" "workspace update diagnostic field"
    Require-Text $Source "full_deploy" "full deploy diagnostic field"
}

Require-Text $HostSource "WriteDeployDiagnosticsJson" "host writes deploy fallback diagnostics"
Require-Text $ServerSource "Yune deploy failed and selected schema artifacts are missing" "server rejects deploy failure without artifacts"

Write-Host "Yune host/server tolerate partial deploy only when selected schema artifacts exist."
